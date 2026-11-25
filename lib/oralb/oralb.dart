// Edge+: an Oral-B toothbrush (iO and Smart/Genius series) as a source.
//
// WHAT THE BRUSH GIVES US. Nothing is read over a connection: an Oral-B brush
// broadcasts its live state in the manufacturer data of its BLE advertisement
// (company id 0x00DC) while it is awake — state, the session timer, the
// pressure flag, the brushing mode and the current mouth sector. The decode
// below is a port of `oralb-ble` (Bluetooth-Devices, MIT; the parser Home
// Assistant uses), itself from Ernst79/bleparser:
// https://github.com/Bluetooth-Devices/oralb-ble/blob/main/src/oralb_ble/parser.py
//
// The brush's own stored history (what the Oral-B app syncs) sits behind a
// proprietary, undocumented GATT protocol nobody has published; it is not read
// here. So a session is only known if this app HEARD it: [BrushTracker] turns
// the stream of adverts into sessions, and [OralBStore] keeps them in Prefs.
//
// Fork-only and kept out of the upstream schema (like meal_plan_store.dart):
// no table, no migration, nothing feeds analytics.

import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../data/day_label.dart' show dayLabelOf;
import '../state/prefs.dart';

/// Bluetooth SIG company id of Procter & Gamble (Oral-B).
const kOralBCompanyId = 0x00DC;

/// A brushing session shorter than this is a tap on the button, not a clean.
const kMinBrushSeconds = 10;

/// The dentists' two minutes, and the Oral-B app's goal.
const kBrushGoalSeconds = 120;

/// One decoded advertisement.
class OralBAdvert {
  const OralBAdvert({
    required this.modelId,
    required this.state,
    required this.highPressure,
    required this.seconds,
    required this.mode,
    required this.sector,
    this.sectors,
  });

  /// Byte 1: which brush family (see [oralBModelName]).
  final int modelId;

  /// Byte 3: 2 idle, 3 running, 4 charging, 10 post-brushing statistics, …
  final int state;

  /// Bit 7 of byte 4, the red pressure ring. A button press in the same byte
  /// takes precedence, as in oralb-ble.
  final bool highPressure;

  /// Bytes 5-6: the session timer, minutes and seconds.
  final int seconds;

  /// Byte 7: the brushing mode (iO: 0 daily clean, 1 sensitive, …).
  final int mode;

  /// Byte 8, low three bits: 1..n the current sector, 0 none.
  final int sector;

  /// Byte 10 when present: how many sectors the brush counts.
  final int? sectors;

  bool get brushing => state == 3;
}

/// Decode Oral-B manufacturer data (the bytes after the company id). Null for
/// anything that is not a 9- or 11-byte Oral-B payload.
OralBAdvert? parseOralB(List<int> d) {
  if (d.length != 9 && d.length != 11) return null;
  final p = d[4];
  final sectors = d.length == 11 ? d[10] : null;
  var sector = d[8] & 0x07;
  // 7 is "the last sector": its real number is the sector count (4 if absent).
  if (sector == 7) sector = ((sectors ?? 0) & 0x07) == 0 ? 4 : sectors! & 0x07;
  return OralBAdvert(
    modelId: d[1],
    state: d[3],
    highPressure: p & 0x0C == 0 && p & 0x80 != 0,
    seconds: d[5] * 60 + d[6],
    mode: d[7],
    sector: sector,
    sectors: sectors,
  );
}

/// The family name oralb-ble gives byte 1.
String oralBModelName(int id) => switch (id) {
  >= 48 && <= 54 => 'Oral-B iO',
  >= 0 && <= 2 => 'Oral-B Triumph',
  >= 32 && <= 34 || >= 112 && <= 119 => 'Oral-B Genius',
  _ => 'Oral-B',
};

/// One heard session.
class BrushSession {
  const BrushSession({
    required this.startSec,
    required this.seconds,
    this.pressureWarnings = 0,
    this.mode,
    this.zones = const {},
  });

  /// Epoch seconds the session started (arrival time minus its timer).
  final int startSec;

  /// How long the brush ran, by its own timer.
  final int seconds;

  /// How often the pressure ring went red.
  final int pressureWarnings;
  final int? mode;

  /// Seconds the brush's timer spent in each zone it reported (byte 8),
  /// zone number to seconds. Empty for sessions heard before this existed.
  /// What the zone number MEANS on an iO is not settled: oralb-ble reads it
  /// as the 30-second pacer, not a detected position.
  final Map<int, int> zones;

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startSec * 1000);

  Map<String, Object?> toJson() =>
      {'s': startSec, 'd': seconds, 'p': pressureWarnings, 'm': mode,
        if (zones.isNotEmpty) 'z': {for (final e in zones.entries) '${e.key}': e.value}};

  static BrushSession? fromJson(Object? m) {
    if (m is! Map || m['s'] is! int || m['d'] is! int) return null;
    return BrushSession(
      startSec: m['s'] as int,
      seconds: m['d'] as int,
      pressureWarnings: m['p'] is int ? m['p'] as int : 0,
      mode: m['m'] is int ? m['m'] as int : null,
      zones: {
        if (m['z'] case final Map z)
          for (final e in z.entries)
            if (e.value is int) ?int.tryParse('${e.key}'): e.value as int,
      },
    );
  }
}

/// Folds adverts into sessions. Pure: the caller passes the arrival time.
///
/// A pause (the button, or lifting the brush out) stops the timer without
/// ending the session, so a session only closes once the brush has not been
/// brushing for [idleClose] — or when the timer starts again from below where
/// it was, which is a new session.
class BrushTracker {
  BrushTracker({this.idleClose = const Duration(seconds: 30)});

  final Duration idleClose;

  int? _startSec;
  int _seconds = 0, _warnings = 0, _lastBrushMs = 0;
  int? _mode;
  bool _red = false;
  int _lastTimer = 0;
  Map<int, int> _zones = {};

  bool get open => _startSec != null;

  /// Feed one advert heard at [atMs]. Returns a session it closed, if any.
  BrushSession? feed(OralBAdvert a, int atMs) {
    BrushSession? closed;
    // After a stop the brush keeps showing the final time; it still counts.
    if (open && !a.brushing && a.seconds > _seconds) _seconds = a.seconds;
    if (a.brushing) {
      if (open && a.seconds + 2 < _seconds) closed = _close();
      if (!open) {
        _startSec = atMs ~/ 1000 - a.seconds;
        _seconds = _warnings = 0;
        _red = false;
        _zones = {};
        _lastTimer = a.seconds;
      }
      // The timer's advance since the last advert goes to the zone this
      // advert reports. A gap longer than a few seconds (a missed stretch) is
      // dropped rather than guessed onto one zone.
      final step = a.seconds - _lastTimer;
      if (a.sector > 0 && step > 0 && step <= 5) {
        _zones[a.sector] = (_zones[a.sector] ?? 0) + step;
      }
      _lastTimer = a.seconds;
      _lastBrushMs = atMs;
      _mode = a.mode;
      if (a.highPressure && !_red) _warnings++;
      _red = a.highPressure;
      if (a.seconds > _seconds) _seconds = a.seconds;
    } else {
      closed = flush(atMs);
    }
    return closed;
  }

  /// Close the open session if it has been quiet for [idleClose].
  BrushSession? flush(int nowMs) =>
      open && nowMs - _lastBrushMs >= idleClose.inMilliseconds ? _close() : null;

  BrushSession? _close() {
    final s = BrushSession(
      startSec: _startSec!,
      seconds: _seconds,
      pressureWarnings: _warnings,
      mode: _mode,
      zones: _zones,
    );
    _startSec = null;
    return s.seconds >= kMinBrushSeconds ? s : null;
  }
}

/// The paired brush and its sessions, in Prefs.
class OralBStore {
  OralBStore._();

  static const kDeviceKey = 'edgeplus.oralb.device';
  static const kNameKey = 'edgeplus.oralb.name';
  static const kSessionsKey = 'edgeplus.oralb.sessions.v1';

  // ponytail: a capped JSON list in Prefs (two years at twice a day). Move to
  // a table only if anything ever needs more history than that.
  static const _keep = 1500;

  /// Bumps on every change, so a screen can listen.
  static final changed = ValueNotifier<int>(0);

  static String get deviceId => Prefs.getString(kDeviceKey, '');
  static String get deviceName => Prefs.getString(kNameKey, '');
  static bool get paired => deviceId.isNotEmpty;

  static void pair(String remoteId, String name) {
    Prefs.setString(kDeviceKey, remoteId);
    Prefs.setString(kNameKey, name);
    changed.value++;
  }

  /// Forget the brush. Its sessions stay: they are the user's history.
  static void unpair() {
    Prefs.setString(kDeviceKey, '');
    Prefs.setString(kNameKey, '');
    changed.value++;
  }

  /// Newest first.
  static List<BrushSession> sessions() {
    final raw = Prefs.getString(kSessionsKey, '');
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final m in list) ?BrushSession.fromJson(m)]
        ..sort((a, b) => b.startSec.compareTo(a.startSec));
    } catch (_) {
      return [];
    }
  }

  static void add(BrushSession s) {
    final all = sessions();
    // The same session heard twice (an app restart mid-brush) starts within a
    // few seconds of itself: keep the longer one.
    all.removeWhere((o) => (o.startSec - s.startSec).abs() < 20 && o.seconds <= s.seconds);
    if (all.any((o) => (o.startSec - s.startSec).abs() < 20)) return;
    all.insert(0, s);
    all.sort((a, b) => b.startSec.compareTo(a.startSec));
    Prefs.setString(
        kSessionsKey, jsonEncode([for (final x in all.take(_keep)) x.toJson()]));
    changed.value++;
  }
}

/// What the Zahnhygiene page shows, from the sessions alone.
class BrushStats {
  BrushStats(List<BrushSession> sessions, DateTime now) {
    final byDay = <String, int>{};
    for (final s in sessions) {
      final d = dayLabelOf(s.start);
      byDay[d] = (byDay[d] ?? 0) + 1;
    }
    final today = DateTime(now.year, now.month, now.day);
    String day(int back) => dayLabelOf(DateTime(today.year, today.month, today.day - back));
    todayCount = byDay[day(0)] ?? 0;
    twiceDays = [for (var i = 0; i < 7; i++) if ((byDay[day(i)] ?? 0) >= 2) i].length;
    // Today still counts while it is under way: the streak runs from
    // yesterday until today reaches two.
    var i = todayCount >= 2 ? 0 : 1;
    var run = 0;
    while ((byDay[day(i)] ?? 0) >= 2) {
      run++;
      i++;
    }
    streak = run;
    final cutoff = DateTime(today.year, today.month, today.day - 6);
    final week = [for (final s in sessions) if (!s.start.isBefore(cutoff)) s];
    weekSessions = week.length;
    avgSeconds = week.isEmpty
        ? null
        : (week.fold<int>(0, (a, s) => a + s.seconds) / week.length).round();
    pressureSessions = week.where((s) => s.pressureWarnings > 0).length;
  }

  late final int todayCount, twiceDays, streak, weekSessions, pressureSessions;

  /// Average length over the last 7 days; null with no session in them.
  late final int? avgSeconds;
}

/// How long the timer ran in each zone on average, over the sessions of the
/// last [days] that carry zones. Null when none do. A zone a session never
/// reached counts as 0 for it: stopping early is exactly what this shows.
({int sessions, int zones, Map<int, double> avg})? zoneTrend(
    List<BrushSession> all, DateTime now, {int days = 30}) {
  final cutoff = DateTime(now.year, now.month, now.day - days + 1);
  final with_ = [
    for (final s in all)
      if (s.zones.isNotEmpty && !s.start.isBefore(cutoff)) s,
  ];
  if (with_.isEmpty) return null;
  final most = with_.expand((s) => s.zones.keys).reduce((a, b) => a > b ? a : b);
  final zones = most > 4 ? 6 : 4;
  return (
    sessions: with_.length,
    zones: zones,
    avg: {
      for (var z = 1; z <= zones; z++)
        z: with_.fold<int>(0, (a, s) => a + (s.zones[z] ?? 0)) / with_.length,
    },
  );
}

/// "2:05".
String brushClock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
