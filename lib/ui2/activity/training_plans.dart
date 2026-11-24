// Edge+: saved training plans (Push / Pull / Legs …) and the progress math
// behind them.
//
// Fork-only and kept in its own file so upstream files carry only a few hook
// lines. Plans live in Prefs as JSON: a handful of names and exercise keys,
// nothing the strength_set table does not already own. Progress is derived on
// read from strength_set, the same rows "Previous" and "Best" come from.

import 'dart:convert';

import '../../state/prefs.dart';

/// One saved plan: a name and its exercises, in order.
class TrainingPlan {
  final String id;
  final String name;
  final List<String> exercises;

  const TrainingPlan(this.id, this.name, this.exercises);

  TrainingPlan copyWith({String? name, List<String>? exercises}) =>
      TrainingPlan(id, name ?? this.name, exercises ?? this.exercises);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'exercises': exercises,
  };

  static TrainingPlan? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], name = m['name'], ex = m['exercises'];
    if (id is! String || name is! String || ex is! List) return null;
    return TrainingPlan(id, name, [
      for (final e in ex)
        if (e is String) e,
    ]);
  }
}

/// Ready-made starting points, offered while the list is empty.
const kPlanTemplates = <(String, List<String>)>[
  (
    'Push',
    ['bench_press', 'overhead_press', 'incline_db_press', 'triceps_pushdown'],
  ),
  ('Pull', ['barbell_row', 'pull_up', 'lat_pulldown', 'barbell_curl']),
  ('Legs', ['back_squat', 'romanian_deadlift', 'leg_press', 'hip_thrust']),
];

class TrainingPlanStore {
  TrainingPlanStore._();

  static const _key = 'edgeplus.training_plans';

  static List<TrainingPlan> load() {
    final raw = Prefs.getString(_key, '');
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final e in list) ?TrainingPlan.fromJson(e)];
    } catch (_) {
      return [];
    }
  }

  static void _save(List<TrainingPlan> plans) =>
      Prefs.setString(_key, jsonEncode([for (final p in plans) p.toJson()]));

  /// Insert or replace by id.
  static void put(TrainingPlan plan) {
    final plans = load();
    final i = plans.indexWhere((p) => p.id == plan.id);
    if (i < 0) {
      plans.add(plan);
    } else {
      plans[i] = plan;
    }
    _save(plans);
  }

  static void remove(String id) =>
      _save(load()..removeWhere((p) => p.id == id));

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

// ══════════════════ PROGRESS: PURE MATH ══════════════════

/// One exercise in one session, boiled down to the numbers progress needs.
class ExerciseSession {
  final String sessionId;
  final DateTime at;

  /// Heaviest load lifted, kg. Null for a bodyweight-only session.
  final double? topKg;

  /// Most reps done at [topKg] (or in any set, for bodyweight).
  final int topReps;
  final int sets;

  /// Σ load × reps over loaded sets; null when nothing was loaded.
  final double? volumeKg;

  /// The number the trend is drawn from: best estimated 1RM (Epley) for a
  /// loaded lift, most reps in a set for a bodyweight one.
  final double score;

  const ExerciseSession({
    required this.sessionId,
    required this.at,
    required this.topKg,
    required this.topReps,
    required this.sets,
    required this.volumeKg,
    required this.score,
  });

  bool get bodyweight => topKg == null;
}

/// Epley's estimated one-rep max. Reps are capped at 12: past that the
/// formula stops meaning anything and a light high-rep set would outscore a
/// heavy one.
double epley(double kg, int reps) => kg * (1 + reps.clamp(1, 12) / 30);

/// strength_set rows (one exercise, any order) → one entry per session,
/// oldest first.
List<ExerciseSession> sessionsFromRows(List<Map<String, Object?>> rows) {
  final by = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final id = r['session_id'] as String?;
    if (id == null) continue;
    (by[id] ??= []).add(r);
  }
  final out = <ExerciseSession>[];
  for (final e in by.entries) {
    double? topKg;
    var topReps = 0, maxReps = 0;
    double? volume;
    double best1rm = 0;
    var atMs = 0;
    for (final r in e.value) {
      final reps = (r['reps'] as num?)?.toInt() ?? 0;
      final kg = (r['load_kg'] as num?)?.toDouble();
      final at = (r['at_ts'] as num?)?.toInt() ?? 0;
      if (at > 0 && (atMs == 0 || at < atMs)) atMs = at;
      if (reps > maxReps) maxReps = reps;
      if (kg == null || reps <= 0) continue;
      volume = (volume ?? 0) + kg * reps;
      final est = epley(kg, reps);
      if (est > best1rm) best1rm = est;
      if (topKg == null || kg > topKg) {
        topKg = kg;
        topReps = reps;
      } else if (kg == topKg && reps > topReps) {
        topReps = reps;
      }
    }
    if (topKg == null && maxReps == 0) continue;
    out.add(
      ExerciseSession(
        sessionId: e.key,
        at: DateTime.fromMillisecondsSinceEpoch(atMs),
        topKg: topKg,
        topReps: topKg == null ? maxReps : topReps,
        sets: e.value.length,
        volumeKg: volume,
        score: topKg == null ? maxReps.toDouble() : best1rm,
      ),
    );
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// The last session against the one before it.
class SessionDelta {
  final double? kg; // top load, kg
  final int reps; // reps at top load
  final double? volumeKg;
  const SessionDelta(this.kg, this.reps, this.volumeKg);
}

SessionDelta? lastDelta(List<ExerciseSession> s) {
  if (s.length < 2) return null;
  final a = s[s.length - 2], b = s.last;
  return SessionDelta(
    a.topKg == null || b.topKg == null ? null : b.topKg! - a.topKg!,
    b.topReps - a.topReps,
    a.volumeKg == null || b.volumeKg == null ? null : b.volumeKg! - a.volumeKg!,
  );
}

/// How many of the most recent sessions a trend looks at.
const kTrendWindow = 8;

/// Change per session in percent of the window's mean score, from a least-
/// squares line through the last [kTrendWindow] scores. Null with fewer than
/// two sessions.
double? trendPct(List<double> scores) {
  final y = scores.length > kTrendWindow
      ? scores.sublist(scores.length - kTrendWindow)
      : scores;
  final n = y.length;
  if (n < 2) return null;
  final mx = (n - 1) / 2;
  final my = y.reduce((a, b) => a + b) / n;
  if (my <= 0) return null;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (i - mx) * (y[i] - my);
    den += (i - mx) * (i - mx);
  }
  return num / den / my * 100;
}

enum Tendency { up, flat, down }

/// ±1 % per session is noise: a plate on one lift, a bad day on another.
Tendency? tendencyOf(double? pct) => pct == null
    ? null
    : pct > 1
    ? Tendency.up
    : pct < -1
    ? Tendency.down
    : Tendency.flat;

/// A whole plan as one line: per session date, the mean of each exercise's
/// score relative to that exercise's first logged session (100 = where it
/// started). Oldest first.
List<(DateTime, double)> planIndex(Map<String, List<ExerciseSession>> byEx) {
  final points = <String, (DateTime, List<double>)>{};
  for (final s in byEx.values) {
    if (s.isEmpty || s.first.score <= 0) continue;
    final base = s.first.score;
    for (final e in s) {
      final slot = points[e.sessionId] ??= (e.at, <double>[]);
      slot.$2.add(e.score / base * 100);
    }
  }
  final out = [
    for (final v in points.values)
      (v.$1, v.$2.reduce((a, b) => a + b) / v.$2.length),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}
