// Glue between the sources, the model and the screens. Holds today's day
// summary, turns heart-rate samples into battery drain once per minute and
// asks the alert policy whether to vibrate.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/alerts.dart';
import '../core/energy_model.dart';
import '../core/envelope.dart';
import '../core/hr_threshold.dart';
import '../core/models.dart';
import '../data/store.dart';
import '../sources/alerter.dart';
import '../sources/ble_heart_rate.dart';
import '../sources/health_data.dart';

class PacingState extends ChangeNotifier {
  PacingState({
    PacingStore? store,
    this.model = const EnergyModel(),
    BleHeartRate? ble,
    HealthData? health,
    Alerter? alerter,
    DateTime Function()? clock,
  })  : _store = store ?? PacingStore(),
        ble = ble ?? BleHeartRate(),
        health = health ?? HealthData(),
        alerter = alerter ?? Alerter(),
        _clock = clock ?? DateTime.now;

  final PacingStore _store;
  final EnergyModel model;
  final BleHeartRate ble;
  final HealthData health;
  final Alerter alerter;
  final DateTime Function() _clock;
  final AlertPolicy _policy = AlertPolicy();

  PacingData data = PacingData();
  bool loaded = false;
  int? liveHr;
  bool sensorConnected = false;
  String? lastEnvelopeNote;

  StreamSubscription<int>? _hrSub;
  StreamSubscription<bool>? _connSub;
  final List<int> _minuteSamples = [];
  DateTime? _minuteStart;
  DateTime? _overSince;
  DateTime? _lastSave;

  PacingSettings get settings => data.settings;
  String get todayKey => dayKey(_clock());

  CheckIn? get todayCheckIn =>
      data.checkIns.where((c) => c.day == todayKey).firstOrNull;

  bool get inCrash => todayCheckIn?.crash ?? false;

  DaySummary get today {
    final k = todayKey;
    final existing = data.days.where((d) => d.day == k).firstOrNull;
    if (existing != null) return existing;
    final d = DaySummary(
        day: k,
        envelope: settings.envelope,
        startCharge: settings.envelope * _morningFactor());
    data.days.add(d);
    return d;
  }

  double get batteryShare =>
      today.envelope <= 0 ? 0 : today.remaining / today.envelope;

  MorningVitals? get todayVitals => data.vitals[todayKey];

  bool get hrMedsListed =>
      data.meds.any((m) => m.active && m.affectsHeartRate);

  HrThreshold get threshold => computeThreshold(settings,
      measuredRestingHr: todayVitals?.restingHr ?? _baselineRestingHr(),
      hrAffectingMeds: hrMedsListed);

  double? _baselineRestingHr() {
    final v = _baselineVitals()
        .map((e) => e.restingHr)
        .whereType<double>()
        .toList();
    if (v.length < 3) return null;
    v.sort();
    return v[v.length ~/ 2];
  }

  double? get restingHr => todayVitals?.restingHr ?? _baselineRestingHr() ?? settings.restingHr;

  List<MorningVitals> _baselineVitals() {
    final now = _clock();
    final keys = {
      for (var n = 1; n <= 14; n++) dayKey(now.subtract(Duration(days: n)))
    };
    return [
      for (final e in data.vitals.entries)
        if (keys.contains(e.key)) e.value
    ];
  }

  double _morningFactor() {
    final k = todayKey;
    return model.morningCharge(
      checkIn: data.checkIns.where((c) => c.day == k).firstOrNull,
      today: data.vitals[k],
      baseline: _baselineVitals(),
      recentDays: data.days.where((d) => d.day.compareTo(k) < 0).toList(),
    );
  }

  Future<void> load() async {
    data = await _store.load();
    loaded = true;
    _rollDay();
    _policy
      ..batteryWarnShare = settings.alertAtBatteryPercent / 100
      ..quietStart = settings.quietHoursStart
      ..quietEnd = settings.quietHoursEnd;
    _hrSub = ble.heartRate.listen(onHeartRate);
    _connSub = ble.connected.listen((c) {
      sensorConnected = c;
      notifyListeners();
    });
    if (settings.hrDeviceId != null) {
      unawaited(ble.connect(settings.hrDeviceId!).catchError((_) {}));
    }
    if (settings.useHealthData) unawaited(refreshHealth());
    notifyListeners();
  }

  /// New day: run the envelope adaptation once, then open today's summary.
  void _rollDay() {
    final k = todayKey;
    if (data.days.any((d) => d.day == k)) return;
    if (settings.autoAdaptEnvelope) {
      final dec = adaptEnvelope(
        envelope: settings.envelope,
        days: data.days,
        checkIns: data.checkIns,
        today: _clock(),
        lastChange: settings.lastEnvelopeChange,
      );
      if (dec.changed) {
        settings.envelope = dec.newEnvelope;
        settings.lastEnvelopeChange = k;
        data.envelopeLog.add('$k: ${dec.reason}');
        lastEnvelopeNote = dec.reason;
      }
    }
    today; // creates it
    _save(force: true);
  }

  Future<void> refreshHealth() async {
    try {
      final now = _clock();
      final v = await health.lastNight(now);
      if (v.restingHr != null || v.hrv != null || v.sleepHours != null) {
        data.vitals[todayKey] = v;
        _recomputeStart();
      }
      today.steps = await health.stepsToday(now);
      _save(force: true);
      notifyListeners();
    } catch (_) {
      // No permission or no data source: the app works on check-ins alone.
    }
  }

  /// Re-derives today's starting charge after new morning evidence, keeping
  /// whatever has already been used.
  void _recomputeStart() {
    final t = today;
    final i = data.days.indexOf(t);
    data.days[i] = DaySummary(
      day: t.day,
      envelope: t.envelope,
      startCharge: t.envelope * _morningFactor(),
      used: t.used,
      recharged: t.recharged,
      minutesOverThreshold: t.minutesOverThreshold,
      peakHr: t.peakHr,
      steps: t.steps,
    );
  }

  // ---------------------------------------------------------------- live HR

  void onHeartRate(int hr) {
    final now = _clock();
    _rollDay();
    liveHr = hr;
    final c = threshold.ceiling;
    if (c != null && hr >= c) {
      _overSince ??= now;
    } else {
      _overSince = null;
    }

    _minuteStart ??= now;
    _minuteSamples.add(hr);
    if (now.difference(_minuteStart!) >= const Duration(minutes: 1)) {
      _closeMinute();
      _minuteStart = now;
    }

    _evaluateAlerts(now);
    notifyListeners();
  }

  void _closeMinute() {
    if (_minuteSamples.isEmpty) return;
    final avg = _minuteSamples.reduce((a, b) => a + b) / _minuteSamples.length;
    final peak = _minuteSamples.reduce(math.max);
    _minuteSamples.clear();
    final resting = restingHr;
    final c = threshold.ceiling;
    final t = today;
    t.peakHr = math.max(t.peakHr ?? 0, peak);
    if (resting == null || c == null) return; // no ceiling, no HR drain
    t.used += model.minuteCost(
        hr: avg, resting: resting, ceiling: c.toDouble(), envelope: t.envelope);
    if (avg >= c) t.minutesOverThreshold++;
    final r = model.minuteRecharge(
        hr: avg, resting: resting, ceiling: c.toDouble(), envelope: t.envelope);
    t.recharged = math.min(model.maxRecharge(t.envelope), t.recharged + r);
    _save();
  }

  void _evaluateAlerts(DateTime now) {
    if (!settings.vibrationAlerts) return;
    final e = _policy.evaluate(AlertInput(
      now: now,
      batteryShare: batteryShare,
      hr: liveHr?.toDouble(),
      ceiling: threshold.ceiling,
      secondsOverCeiling:
          _overSince == null ? 0 : now.difference(_overSince!).inSeconds,
    ));
    if (e != null) unawaited(alerter.fire(e));
  }

  // ------------------------------------------------------------ user input

  void saveCheckIn(CheckIn c) {
    data.checkIns.removeWhere((x) => x.day == c.day);
    data.checkIns.add(c);
    if (c.day == todayKey) _recomputeStart();
    _save(force: true);
    notifyListeners();
  }

  void logActivity(ActivityLog a) {
    data.logs.add(a);
    final d = data.days.where((x) => x.day == a.day).firstOrNull;
    if (d != null) d.used += model.logCost(a, envelope: d.envelope);
    _evaluateAlerts(_clock());
    _save(force: true);
    notifyListeners();
  }

  void deleteActivity(ActivityLog a) {
    data.logs.removeWhere((x) => x.id == a.id);
    final d = data.days.where((x) => x.day == a.day).firstOrNull;
    if (d != null) {
      d.used = math.max(0, d.used - model.logCost(a, envelope: d.envelope));
    }
    _save(force: true);
    notifyListeners();
  }

  double costOf(ActivityLog a) {
    final d = data.days.where((x) => x.day == a.day).firstOrNull;
    return model.logCost(a, envelope: d?.envelope ?? settings.envelope);
  }

  void upsertMed(Medication m) {
    data.meds.removeWhere((x) => x.id == m.id);
    data.meds.add(m);
    _save(force: true);
    notifyListeners();
  }

  void removeMed(Medication m) {
    data.meds.removeWhere((x) => x.id == m.id);
    _save(force: true);
    notifyListeners();
  }

  void takeMed(Medication m) {
    data.intakes.add(MedIntake(medId: m.id, at: _clock()));
    _save(force: true);
    notifyListeners();
  }

  List<MedIntake> intakesToday(String medId) => data.intakes
      .where((i) => i.medId == medId && dayKey(i.at) == todayKey)
      .toList();

  void toggleIdea(String id) {
    if (!data.hiddenIdeas.remove(id)) data.hiddenIdeas.add(id);
    _save(force: true);
    notifyListeners();
  }

  void updateSettings(void Function(PacingSettings s) f) {
    f(settings);
    _policy
      ..batteryWarnShare = settings.alertAtBatteryPercent / 100
      ..quietStart = settings.quietHoursStart
      ..quietEnd = settings.quietHoursEnd;
    // A manual envelope change applies to today right away.
    final t = today;
    if (t.envelope != settings.envelope) {
      final i = data.days.indexOf(t);
      final share = t.envelope <= 0 ? 1.0 : t.startCharge / t.envelope;
      data.days[i] = DaySummary(
        day: t.day,
        envelope: settings.envelope,
        startCharge: settings.envelope * share,
        used: t.used * settings.envelope / t.envelope,
        recharged: t.recharged,
        minutesOverThreshold: t.minutesOverThreshold,
        peakHr: t.peakHr,
        steps: t.steps,
      );
    }
    _save(force: true);
    notifyListeners();
  }

  Future<void> pairSensor(String id, String name) async {
    updateSettings((s) {
      s.hrDeviceId = id;
      s.hrDeviceName = name;
    });
    await ble.connect(id);
  }

  Future<void> forgetSensor() async {
    await ble.disconnect();
    updateSettings((s) {
      s.hrDeviceId = null;
      s.hrDeviceName = null;
    });
  }

  String exportJson() => _store.export(data);

  void _save({bool force = false}) {
    final now = _clock();
    if (!force &&
        _lastSave != null &&
        now.difference(_lastSave!) < const Duration(minutes: 2)) {
      return;
    }
    _lastSave = now;
    unawaited(_store.save(data).catchError((_) {}));
  }

  @override
  void dispose() {
    _hrSub?.cancel();
    _connSub?.cancel();
    _closeMinute();
    unawaited(_store.save(data));
    super.dispose();
  }
}
