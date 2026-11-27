// Edge+: running statistics — the progress numbers a running app shows:
// weekly distance, pace and aerobic efficiency over time, best efforts.
//
// Pure: the screen loads runs (sessions + their frozen per-km splits from
// `workout_split`) and hands them here. Every figure abstains on missing
// input — a run without splits has no best km, a split without heart rate
// adds nothing to efficiency.

import 'dart:math' as math;

class RunSplit {
  final double meters;
  final int sec;
  final double? avgHr;
  final double? elev; // net metres over the split
  const RunSplit(this.meters, this.sec, {this.avgHr, this.elev});
}

class RunRecord {
  final String id;
  final DateTime start;
  final double meters;
  final int sec; // moving time when splits exist, else session duration
  final double? avgHr;
  final double? vo2max;
  final List<double> zoneMin; // five, or empty
  final List<RunSplit> splits;

  const RunRecord({
    required this.id,
    required this.start,
    required this.meters,
    required this.sec,
    this.avgHr,
    this.vo2max,
    this.zoneMin = const [],
    this.splits = const [],
  });

  /// Seconds per km, null for runs too short to have a pace.
  double? get pace => meters < 200 || sec <= 0 ? null : sec / (meters / 1000);

  /// Aerobic efficiency: metres covered per heartbeat. Rises when the same
  /// pace costs fewer beats — the "same pace, lower heart rate" signal.
  /// From splits with HR only, so a dropout does not count as zero beats.
  double? get metersPerBeat {
    var m = 0.0, beats = 0.0;
    for (final s in splits) {
      if (s.avgHr == null || s.avgHr! < 60 || s.sec <= 0) continue;
      m += s.meters;
      beats += s.avgHr! * s.sec / 60;
    }
    if (m < 1000 || beats <= 0) {
      if (splits.isEmpty && avgHr != null && avgHr! >= 60 && meters >= 1000) {
        return meters / (avgHr! * sec / 60);
      }
      return null;
    }
    return m / beats;
  }

  /// Sum of positive net elevation over splits (GPS altitude, coarse).
  double? get climb {
    final e = [for (final s in splits) ?s.elev];
    if (e.isEmpty) return null;
    return e.where((v) => v > 0).fold<double>(0, (a, b) => a + b);
  }
}

/// Fastest time over [km] consecutive FULL kilometre splits, in seconds.
int? bestOver(RunRecord r, int km) {
  final full = r.splits;
  if (full.length < km) return null;
  int? best;
  for (var i = 0; i + km <= full.length; i++) {
    var t = 0;
    var ok = true;
    for (var j = i; j < i + km; j++) {
      if (full[j].meters < 990) {
        ok = false;
        break;
      }
      t += full[j].sec;
    }
    if (ok && (best == null || t < best)) best = t;
  }
  return best;
}

class BestEffort {
  final String label;
  final int sec;
  final DateTime when;
  const BestEffort(this.label, this.sec, this.when);
}

/// Best 1 / 5 / 10 / 21.1 km times across [runs], from consecutive km splits;
/// the half also from a whole run that long. Absent when never run.
List<BestEffort> bestEfforts(List<RunRecord> runs) {
  final out = <BestEffort>[];
  for (final (label, km) in [('1 km', 1), ('5 km', 5), ('10 km', 10)]) {
    BestEffort? b;
    for (final r in runs) {
      final t = bestOver(r, km);
      if (t != null && (b == null || t < b.sec)) b = BestEffort(label, t, r.start);
    }
    if (b != null) out.add(b);
  }
  BestEffort? half;
  for (final r in runs) {
    if (r.meters < 21097.5) continue;
    final t = bestOver(r, 21);
    final est = t != null
        ? (t * 21.0975 / 21).round()
        : (r.sec * 21097.5 / r.meters).round();
    if (half == null || est < half.sec) half = BestEffort('HM', est, r.start);
  }
  if (half != null) out.add(half);
  return out;
}

/// Monday 00:00 local of the week containing [d].
DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Kilometres per week for the [n] weeks ending with the week of [now],
/// oldest first. A week with no run is 0 — a real zero, nothing was run.
List<double> weeklyKm(List<RunRecord> runs, DateTime now, {int n = 12}) {
  final first = weekStart(now);
  final starts = [
    for (var i = n - 1; i >= 0; i--)
      DateTime(first.year, first.month, first.day - 7 * i)
  ];
  final out = List<double>.filled(n, 0);
  for (final r in runs) {
    for (var i = n - 1; i >= 0; i--) {
      if (!r.start.isBefore(starts[i])) {
        if (i == n - 1 ||
            r.start.isBefore(starts[i + 1])) {
          out[i] += r.meters / 1000;
        }
        break;
      }
    }
  }
  return out;
}

/// This week's km against the average of the four weeks before. Above 1.3
/// the jump is large; Nielsen et al. 2014 saw more injuries in novices whose
/// weekly distance rose by more than 30 %.
double? loadRatio(List<double> weekly) {
  if (weekly.length < 5) return null;
  final prev = weekly.sublist(weekly.length - 5, weekly.length - 1);
  final avg = prev.reduce((a, b) => a + b) / 4;
  if (avg < 5) return null;
  return weekly.last / avg;
}

class RunTotals {
  final int runs;
  final double km;
  final int sec;
  final double? climb;
  final double? avgPace;
  final double? longestKm;
  const RunTotals(
      this.runs, this.km, this.sec, this.climb, this.avgPace, this.longestKm);
}

RunTotals totals(Iterable<RunRecord> runs) {
  var n = 0, m = 0.0, s = 0;
  double? climb, longest;
  for (final r in runs) {
    n++;
    m += r.meters;
    s += r.sec;
    final c = r.climb;
    if (c != null) climb = (climb ?? 0) + c;
    if (longest == null || r.meters / 1000 > longest) longest = r.meters / 1000;
  }
  return RunTotals(n, m / 1000, s, climb, m >= 200 ? s / (m / 1000) : null,
      longest);
}

/// Consecutive weeks (ending this week or last) with at least one run.
int weekStreak(List<RunRecord> runs, DateTime now) {
  final weeks = {
    for (final r in runs) weekStart(r.start).millisecondsSinceEpoch
  };
  var w = weekStart(now);
  if (!weeks.contains(w.millisecondsSinceEpoch)) {
    w = DateTime(w.year, w.month, w.day - 7);
  }
  var n = 0;
  while (weeks.contains(w.millisecondsSinceEpoch)) {
    n++;
    w = DateTime(w.year, w.month, w.day - 7);
  }
  return n;
}

/// Least-squares slope of [ys] per index step, or null under 3 points.
double? slope(List<double> ys) {
  if (ys.length < 3) return null;
  final n = ys.length;
  final mx = (n - 1) / 2;
  final my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (i - mx) * (ys[i] - my);
    den += (i - mx) * (i - mx);
  }
  return den == 0 ? null : num / den;
}

/// Median pace of the last [n] runs, for the route planner's default.
double? typicalPace(List<RunRecord> runs, {int n = 10}) {
  final p = [
    for (final r in (List.of(runs)..sort((a, b) => b.start.compareTo(a.start)))
        .take(n))
      ?r.pace
  ]..sort();
  if (p.isEmpty) return null;
  return p[p.length ~/ 2];
}

String fmtClock(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

String fmtHours(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
  return h > 0 ? '$h h ${m.toString().padLeft(2, '0')}' : '$m min';
}

double roundTo(double v, int d) {
  final f = math.pow(10, d);
  return (v * f).round() / f;
}
