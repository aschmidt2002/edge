// Morning numbers from Apple Health (iOS) or Health Connect (Android).
//
// The official WHOOP app can write into Apple Health / Health Connect, so
// this is also the way a WHOOP with a normal membership feeds this app its
// resting HR, HRV and sleep — without any WHOOP account login in here.
//
// iOS stores HRV as SDNN, Android as RMSSD. They are not the same number, so
// the app only ever compares a value to the person's own baseline from the
// same source, never to a fixed norm.

import 'package:health/health.dart';

import '../core/models.dart';

class HealthData {
  final _health = Health();
  bool _configured = false;

  static const _types = [
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.STEPS,
  ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  List<HealthDataType> get _platformTypes => _types
      .where((t) => _health.isDataTypeAvailable(t))
      .toList();

  Future<bool> requestAccess() async {
    await _configure();
    final types = _platformTypes;
    return _health.requestAuthorization(types,
        permissions: types.map((_) => HealthDataAccess.READ).toList());
  }

  /// Last night: resting HR, HRV and hours asleep between 18:00 yesterday and
  /// now. Fields without data stay null.
  Future<MorningVitals> lastNight(DateTime now) async {
    await _configure();
    final from = DateTime(now.year, now.month, now.day - 1, 18);
    final points = await _health.getHealthDataFromTypes(
      types: _platformTypes.where((t) => t != HealthDataType.STEPS).toList(),
      startTime: from,
      endTime: now,
    );
    double? last(bool Function(HealthDataType) pick) {
      final v = points.where((p) => pick(p.type)).toList()
        ..sort((a, b) => a.dateTo.compareTo(b.dateTo));
      if (v.isEmpty) return null;
      final hv = v.last.value;
      return hv is NumericHealthValue ? hv.numericValue.toDouble() : null;
    }

    final sleepMin = points
        .where((p) => p.type == HealthDataType.SLEEP_ASLEEP)
        .fold<int>(0, (s, p) => s + p.dateTo.difference(p.dateFrom).inMinutes);

    return MorningVitals(
      restingHr: last((t) => t == HealthDataType.RESTING_HEART_RATE),
      hrv: last((t) =>
          t == HealthDataType.HEART_RATE_VARIABILITY_SDNN ||
          t == HealthDataType.HEART_RATE_VARIABILITY_RMSSD),
      sleepHours: sleepMin == 0 ? null : sleepMin / 60,
    );
  }

  Future<int?> stepsToday(DateTime now) async {
    await _configure();
    return _health.getTotalStepsInInterval(
        DateTime(now.year, now.month, now.day), now);
  }
}
