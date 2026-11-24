// Edge+: screen time per app and unlocks (Digital Wellbeing's numbers), kept
// per day in Prefs, and the one question asked of them: is your mood different
// on the days you spend more of it?
//
// The numbers come from Android's UsageStatsManager through
// ScreenTimeBridge.kt. Fork-only and kept out of the upstream schema (like
// lib/oralb): no table, no migration, nothing feeds analytics.
//
// WHY NOT THE JOURNAL CORRELATIONS. The original engine
// (getJournalInsights → analytics' journalNumericCorrelations) tests journal
// fields against recovery, HRV, resting HR and sleep efficiency. Mood is one of
// its INPUTS, never an outcome, so screen time cannot be asked against mood
// there without changing that algorithm. [moodHints] is its own small test,
// with the same discipline: rank-based, corrected for every test it ran, and
// silent unless something clears the bar.

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart';

import '../data/day_label.dart' show dayLabelOf;
import '../data/journal_fields.dart' show JournalMetricValue;
import '../state/prefs.dart';

/// One day's screen time.
class ScreenDay {
  const ScreenDay({required this.apps, required this.unlocks, this.complete = false});

  /// Minutes in the foreground, by package. Apps under a minute are left out.
  final Map<String, int> apps;
  final int unlocks;

  /// Copied after the day had ended, so it will not change again.
  final bool complete;

  int get total => apps.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {'a': apps, 'u': unlocks, if (complete) 'c': true};

  static ScreenDay? fromJson(Object? m) {
    if (m is! Map) return null;
    final a = m['a'];
    return ScreenDay(
      apps: {
        if (a is Map)
          for (final e in a.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      unlocks: (m['u'] as num?)?.toInt() ?? 0,
      complete: m['c'] == true,
    );
  }
}

class ScreenTime {
  ScreenTime._();

  static const kOnKey = 'edgeplus.screentime.on';
  static const kDaysKey = 'edgeplus.screentime.days.v1';
  static const kLabelsKey = 'edgeplus.screentime.labels.v1';
  static const _ch = MethodChannel('edgeplus/screen_time');

  // ponytail: a capped JSON map in Prefs, about 30 apps a day. Move to a table
  // only if anything ever needs more than a year.
  static const _keepDays = 400;

  /// How far back Android still has the event log.
  static const _backDays = 6;

  /// Bumps on every change, so a screen can listen.
  static final changed = ValueNotifier<int>(0);

  /// The user connected it and Android last said access is granted.
  static bool get connected => Prefs.getBool(kOnKey, false);

  static Future<bool> hasAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('hasAccess') ?? false;
    } catch (e) {
      debugPrint('[screentime] hasAccess failed: $e');
      return false;
    }
  }

  /// Opens Settings > Usage access, where only the user can switch it on.
  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod<bool>('openSettings');
    } catch (e) {
      debugPrint('[screentime] openSettings failed: $e');
    }
  }

  static void disconnect() {
    Prefs.setBool(kOnKey, false);
    changed.value++;
  }

  static Map<String, ScreenDay> days() {
    final raw = Prefs.getString(kDaysKey, '');
    if (raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return {
        for (final e in m.entries)
          '${e.key}': ?ScreenDay.fromJson(e.value),
      };
    } catch (_) {
      return {};
    }
  }

  static Map<String, String> labels() {
    try {
      final m = jsonDecode(Prefs.getString(kLabelsKey, '{}'));
      return {if (m is Map) for (final e in m.entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return {};
    }
  }

  static String label(String pkg, [Map<String, String>? from]) =>
      (from ?? labels())[pkg] ?? pkg.split('.').last;

  /// Copy the days Android still holds. Safe to call often: finished days that
  /// were already copied are skipped.
  static Future<void> refresh({DateTime? now}) async {
    if (!await hasAccess()) {
      if (connected) disconnect();
      return;
    }
    Prefs.setBool(kOnKey, true);
    final t = now ?? DateTime.now();
    final all = days();
    final names = labels();
    for (var back = 0; back <= _backDays; back++) {
      final start = DateTime(t.year, t.month, t.day - back);
      final end = DateTime(t.year, t.month, t.day - back + 1);
      final id = dayLabelOf(start);
      if (all[id]?.complete ?? false) continue;
      try {
        final r = await _ch.invokeMethod<Map<Object?, Object?>>('day', {
          'start': start.millisecondsSinceEpoch,
          'end': end.millisecondsSinceEpoch,
        });
        if (r == null) continue;
        final apps = r['apps'] as Map? ?? const {};
        all[id] = ScreenDay(
          apps: {
            for (final e in apps.entries)
              '${e.key}': ((e.value as num) / 60000).round(),
          },
          unlocks: (r['unlocks'] as num?)?.toInt() ?? 0,
          complete: !end.isAfter(t),
        );
        for (final e in (r['labels'] as Map? ?? const {}).entries) {
          names['${e.key}'] = '${e.value}';
        }
      } catch (e) {
        debugPrint('[screentime] day $id failed: $e');
      }
    }
    final keep = (all.keys.toList()..sort()).reversed.take(_keepDays).toSet();
    Prefs.setString(kDaysKey, jsonEncode({
      for (final e in all.entries)
        if (keep.contains(e.key)) e.key: e.value.toJson(),
    }));
    Prefs.setString(kLabelsKey, jsonEncode(names));
    changed.value++;
  }
}

/// One day's mood for the comparison: that evening's `mood` and the next
/// morning's `mood_morning`, averaged where both exist (both are 1–5).
///
/// ponytail: one blended score rather than two outcomes, which halves the tests
/// and lets a day count with either check-in. Split them only if the two ever
/// need to disagree on screen.
Map<String, double> dailyMood(Map<String, Map<String, JournalMetricValue>> journal) {
  String shift(String day, int by) {
    final d = DateTime.parse(day);
    return dayLabelOf(DateTime(d.year, d.month, d.day + by));
  }

  final out = <String, double>{};
  // A morning check-in alone still describes the day before it.
  for (final day in {for (final k in journal.keys) ...[k, shift(k, -1)]}) {
    final v = [
      ?journal[day]?['mood']?.value,
      ?journal[shift(day, 1)]?['mood_morning']?.value,
    ];
    if (v.isNotEmpty) out[day] = v.reduce((a, b) => a + b) / v.length;
  }
  return out;
}

/// "On days with over [threshold] of [what], your mood runs [delta]."
class MoodHint {
  const MoodHint({
    required this.what,
    required this.threshold,
    required this.unlocks,
    required this.moodAbove,
    required this.moodBelow,
    required this.nAbove,
    required this.nBelow,
    required this.p,
  });

  /// A package name, or '' for all apps together.
  final String what;

  /// Minutes, or unlocks when [unlocks].
  final int threshold;
  final bool unlocks;
  final double moodAbove, moodBelow, p;
  final int nAbove, nBelow;

  double get delta => moodAbove - moodBelow;
}

/// Fewer paired days than this and nothing is tested at all.
const kMinMoodDays = 14;

/// Each side of a split needs at least this many days.
const kMinSideDays = 5;

/// Half a point on the 1–5 scale: smaller is not worth a line on screen.
const kMinMoodDelta = 0.5;

/// Thresholds tried, in minutes (or unlocks).
const _appCuts = [30, 60, 120, 180];
const _totalCuts = [120, 180, 240, 300, 360];
const _unlockCuts = [50, 75, 100, 150];

/// The splits whose mood difference survives a Benjamini–Hochberg correction
/// over every split tried, one per app (its clearest), worst mood first.
///
/// Days are those with both screen time and a mood. Today is left out by the
/// caller: it is not over. Association on your own days, never a cause.
List<MoodHint> moodHints(
  Map<String, ScreenDay> screen,
  Map<String, double> mood, {
  double q = 0.10,
}) {
  final days = [for (final d in screen.keys) if (mood.containsKey(d)) d];
  if (days.length < kMinMoodDays) return const [];
  final tests = <MoodHint>[];

  void tryCuts(String what, bool unlocks, List<int> cuts, int Function(ScreenDay) value) {
    for (final cut in cuts) {
      final above = <double>[], below = <double>[];
      for (final d in days) {
        (value(screen[d]!) > cut ? above : below).add(mood[d]!);
      }
      if (above.length < kMinSideDays || below.length < kMinSideDays) continue;
      tests.add(MoodHint(
        what: what,
        threshold: cut,
        unlocks: unlocks,
        moodAbove: _mean(above),
        moodBelow: _mean(below),
        nAbove: above.length,
        nBelow: below.length,
        p: mannWhitneyP(above, below),
      ));
    }
  }

  tryCuts('', false, _totalCuts, (d) => d.total);
  tryCuts('', true, _unlockCuts, (d) => d.unlocks);
  final pkgs = {for (final d in days) ...screen[d]!.apps.keys};
  for (final pkg in pkgs) {
    tryCuts(pkg, false, _appCuts, (d) => d.apps[pkg] ?? 0);
  }
  if (tests.isEmpty) return const [];

  // Benjamini–Hochberg: the largest rank k with p(k) <= k/m * q passes, and
  // every smaller p with it.
  final sorted = [...tests]..sort((a, b) => a.p.compareTo(b.p));
  final m = sorted.length;
  var pass = 0;
  for (var k = 1; k <= m; k++) {
    if (sorted[k - 1].p <= k / m * q) pass = k;
  }
  final best = <String, MoodHint>{};
  for (final t in sorted.take(pass)) {
    if (t.delta.abs() < kMinMoodDelta) continue;
    best.putIfAbsent('${t.unlocks}:${t.what}', () => t); // sorted: lowest p first
  }
  return best.values.toList()..sort((a, b) => a.delta.compareTo(b.delta));
}

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

/// Two-sided Mann–Whitney U p-value, normal approximation with tie and
/// continuity correction. Fine from about five per group, which is the floor.
double mannWhitneyP(List<double> a, List<double> b) {
  final all = [for (final x in a) (x, 0), for (final x in b) (x, 1)]
    ..sort((x, y) => x.$1.compareTo(y.$1));
  final n = all.length, n1 = a.length, n2 = b.length;
  var rankA = 0.0, tie = 0.0;
  for (var i = 0; i < n;) {
    var j = i;
    while (j < n && all[j].$1 == all[i].$1) {
      j++;
    }
    final rank = (i + j + 1) / 2; // mean of ranks i+1..j
    for (var k = i; k < j; k++) {
      if (all[k].$2 == 0) rankA += rank;
    }
    final t = (j - i).toDouble();
    tie += t * t * t - t;
    i = j;
  }
  final u = rankA - n1 * (n1 + 1) / 2;
  final mu = n1 * n2 / 2;
  final sigma = math.sqrt(n1 * n2 / 12 * ((n + 1) - tie / (n * (n - 1))));
  if (sigma == 0) return 1;
  final z = math.max(0.0, (u - mu).abs() - 0.5) / sigma;
  return (2 * (1 - _phi(z))).clamp(0.0, 1.0);
}

/// Standard normal CDF (Abramowitz & Stegun 7.1.26, error under 1.5e-7).
double _phi(double z) {
  final x = z.abs() / math.sqrt2;
  final t = 1 / (1 + 0.3275911 * x);
  final erf = 1 -
      (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t +
              0.254829592) *
          t *
          math.exp(-x * x);
  return z >= 0 ? (1 + erf) / 2 : (1 - erf) / 2;
}
