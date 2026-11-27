// Edge+: the running coach — a periodised plan built on the user's own heart
// rate zones, with workouts that differ by goal distance.
//
// Pure: no Flutter widgets, no DB. The plan is a function of the settings the
// user picked (goal, weeks, runs per week, level, start Monday), so nothing but
// those settings and the ticked-off workouts is stored.
//
// Where the shape comes from:
//  · Intensity distribution: roughly 80 % of running easy (Z1–Z2), the rest
//    at threshold and above (Seiler & Kjerland 2006; Stöggl & Sperlich 2014;
//    Muñoz et al. 2014 for recreational 10 km runners).
//  · Session types and what each trains: Daniels' Running Formula (E/M/T/I/R),
//    mapped onto five %HRR zones: Z1 recovery, Z2 easy/long, Z3 marathon pace,
//    Z4 threshold, Z5 VO2max intervals. Strides and hill sprints are too short
//    for heart rate to follow, so they carry no HR target.
//  · Distance emphasis: 5 km leans on VO2max intervals, 10 km on threshold plus
//    VO2max, half marathon on threshold and long runs, marathon on long runs and
//    marathon-pace blocks (Daniels; Pfitzinger & Douglas).
//  · Periodisation: base → build → peak → taper, an easier week every fourth
//    week, taper length by distance (Bosquet et al. 2007 meta-analysis: 8–14
//    days, volume down 40–60 %, intensity kept).
//
// ponytail: durations are fixed templates scaled by level and phase, not fitted
// to the user's response. The upgrade is shifting volume by how recovery
// answered the last hard week.

import 'dart:convert';
import 'dart:math' as math;

import '../../state/prefs.dart';

enum RunGoal { k5, k10, half, marathon, base }

enum RunLevel { beginner, intermediate, advanced }

/// What a workout trains, which decides its zones and its structure.
enum RunKind {
  recovery,
  easy,
  strides,
  long,
  longFinish,
  tempo,
  threshold,
  vo2,
  hills,
  fartlek,
  race,
}

/// One timed part of a workout. [zLo]..[zHi] is the target zone band (1..5);
/// both null when heart rate cannot follow the effort (strides, hill sprints)
/// or for a jog break where any zone is fine.
class RunStep {
  final String kind; // warm · work · rest · cool · steady
  final int sec;
  final int? zLo, zHi;

  /// Short label shown on the live screen.
  final String de, en;

  const RunStep(this.kind, this.sec, this.zLo, this.zHi, this.de, this.en);

  bool get guided => zLo != null && zHi != null;

  Map<String, Object?> toJson() =>
      {'k': kind, 's': sec, 'lo': zLo, 'hi': zHi, 'de': de, 'en': en};

  static RunStep? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = (j['s'] as num?)?.toInt();
    if (s == null || s <= 0) return null;
    return RunStep(
      j['k'] as String? ?? 'steady',
      s,
      (j['lo'] as num?)?.toInt(),
      (j['hi'] as num?)?.toInt(),
      j['de'] as String? ?? '',
      j['en'] as String? ?? '',
    );
  }
}

class RunWorkout {
  final RunKind kind;
  final List<RunStep> steps;

  /// "6 × 3 min Z5 · 2 min Trabpause" — the structure in one line.
  final String structDe, structEn;

  const RunWorkout(this.kind, this.steps, this.structDe, this.structEn);

  int get totalSec => steps.fold(0, (a, s) => a + s.sec);

  bool get quality => const {
        RunKind.tempo,
        RunKind.threshold,
        RunKind.vo2,
        RunKind.hills,
        RunKind.fartlek,
        RunKind.longFinish,
        RunKind.race,
      }.contains(kind);

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'de': structDe,
        'en': structEn,
        'steps': [for (final s in steps) s.toJson()],
      };

  static RunWorkout? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = RunKind.values
        .where((k) => k.name == j['kind'])
        .firstOrNull;
    final steps = [
      for (final s in (j['steps'] as List? ?? const [])) ?RunStep.fromJson(s)
    ];
    if (kind == null || steps.isEmpty) return null;
    return RunWorkout(
        kind, steps, j['de'] as String? ?? '', j['en'] as String? ?? '');
  }
}

/// Name and purpose of each kind — what the user reads under the workout.
({String de, String en, String whyDe, String whyEn}) kindInfo(RunKind k) =>
    switch (k) {
      RunKind.recovery => (
          de: 'Regenerationslauf',
          en: 'Recovery run',
          whyDe: 'Durchblutung und lockere Beine, ohne neue Ermüdung. '
              'So langsam, dass es sich fast zu leicht anfühlt.',
          whyEn: 'Blood flow and loose legs without adding fatigue. So easy '
              'it feels almost too easy.',
        ),
      RunKind.easy => (
          de: 'Lockerer Dauerlauf',
          en: 'Easy run',
          whyDe: 'Grundlagenausdauer: mehr Kapillaren und Mitochondrien, '
              'besserer Fettstoffwechsel. Du kannst dabei ganze Sätze sprechen.',
          whyEn: 'Aerobic base: more capillaries and mitochondria, better fat '
              'use. You can speak in full sentences.',
        ),
      RunKind.strides => (
          de: 'Locker + Steigerungen',
          en: 'Easy + strides',
          whyDe: 'Lockerer Lauf mit kurzen, schnellen Steigerungen am Ende: '
              'Laufökonomie und Schrittfrequenz, ohne müde zu machen.',
          whyEn: 'Easy run with short fast strides at the end: running economy '
              'and cadence without tiring you.',
        ),
      RunKind.long => (
          de: 'Langer Lauf',
          en: 'Long run',
          whyDe: 'Ausdauer und Ermüdungsresistenz, Glykogenspeicher, '
              'Sehnen und Bänder gewöhnen sich an die Dauer.',
          whyEn: 'Endurance and fatigue resistance, glycogen stores; tendons '
              'and ligaments get used to the time on feet.',
        ),
      RunKind.longFinish => (
          de: 'Langer Lauf mit Endbeschleunigung',
          en: 'Long run, fast finish',
          whyDe: 'Langer Lauf, der im Renntempo endet: lernt den Körper, auf '
              'müden Beinen das Tempo zu halten.',
          whyEn: 'A long run that finishes at race pace: teaches holding pace '
              'on tired legs.',
        ),
      RunKind.tempo => (
          de: 'Tempodauerlauf (Renntempo)',
          en: 'Tempo run (race pace)',
          whyDe: 'Zügig, aber kontrolliert in Zone 3: Ökonomie im '
              'Marathon-/Halbmarathon-Tempo und Gefühl für das Renntempo.',
          whyEn: 'Brisk but controlled in zone 3: economy at marathon/half '
              'pace and a feel for race pace.',
        ),
      RunKind.threshold => (
          de: 'Schwellenlauf',
          en: 'Threshold run',
          whyDe: 'An der Laktatschwelle (Zone 4): hebt das Tempo, das du lange '
              'halten kannst. Der wichtigste Reiz für 10 km und Halbmarathon.',
          whyEn: 'At lactate threshold (zone 4): raises the pace you can hold '
              'for long. The key session for 10 km and the half.',
        ),
      RunKind.vo2 => (
          de: 'VO2max-Intervalle',
          en: 'VO2max intervals',
          whyDe: 'Harte Intervalle von 2–5 min in Zone 5: steigern die maximale '
              'Sauerstoffaufnahme. Der Kernreiz für 5 km.',
          whyEn: 'Hard 2–5 min reps in zone 5: raise maximal oxygen uptake. '
              'The key session for 5 km.',
        ),
      RunKind.hills => (
          de: 'Bergsprints',
          en: 'Hill repeats',
          whyDe: 'Kurze, kräftige Anstiege: Kraft, Laufökonomie und Schritt, '
              'mit wenig Belastung für die Gelenke. Puls hinkt hier hinterher, '
              'darum nach Gefühl: hart, aber nicht maximal.',
          whyEn: 'Short powerful climbs: strength, economy and stride with '
              'little joint load. Heart rate lags here, so go by feel: hard, '
              'not all-out.',
        ),
      RunKind.fartlek => (
          de: 'Fahrtspiel',
          en: 'Fartlek',
          whyDe: 'Spielerische Tempowechsel zwischen Zone 2 und 4: Abwechslung '
              'und ein erster Reiz über der Grundlage.',
          whyEn: 'Playful changes of pace between zones 2 and 4: variety and a '
              'first stimulus above easy.',
        ),
      RunKind.race => (
          de: 'Wettkampf',
          en: 'Race day',
          whyDe: 'Dein Ziel. Locker anlaufen, gleichmäßig einteilen, die '
              'zweite Hälfte darf schneller sein.',
          whyEn: 'Your goal. Start easy, pace evenly, the second half may be '
              'faster.',
        ),
    };

String goalLabel(RunGoal g, bool de) => switch (g) {
      RunGoal.k5 => '5 km',
      RunGoal.k10 => '10 km',
      RunGoal.half => de ? 'Halbmarathon' : 'Half marathon',
      RunGoal.marathon => 'Marathon',
      RunGoal.base => de ? 'Grundlage / fit bleiben' : 'Base / stay fit',
    };

double? goalMeters(RunGoal g) => switch (g) {
      RunGoal.k5 => 5000,
      RunGoal.k10 => 10000,
      RunGoal.half => 21097.5,
      RunGoal.marathon => 42195,
      RunGoal.base => null,
    };

/// The settings a plan is built from.
class RunPlanConfig {
  final RunGoal goal;
  final RunLevel level;
  final int weeks; // 4..20
  final int perWeek; // 3..6
  final DateTime start; // the Monday of week 1 (local date)
  final Set<String> done; // "week-day" keys, e.g. "3-6"

  RunPlanConfig({
    required this.goal,
    required this.level,
    required this.weeks,
    required this.perWeek,
    required DateTime start,
    this.done = const {},
  }) : start = DateTime(start.year, start.month, start.day);

  RunPlanConfig copyWith({Set<String>? done}) => RunPlanConfig(
      goal: goal,
      level: level,
      weeks: weeks,
      perWeek: perWeek,
      start: start,
      done: done ?? this.done);

  Map<String, Object?> toJson() => {
        'goal': goal.name,
        'level': level.name,
        'weeks': weeks,
        'per_week': perWeek,
        'start':
            '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
        'done': done.toList()..sort(),
      };

  static RunPlanConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    final goal = RunGoal.values.where((g) => g.name == j['goal']).firstOrNull;
    final level =
        RunLevel.values.where((g) => g.name == j['level']).firstOrNull;
    final start = DateTime.tryParse(j['start'] as String? ?? '');
    if (goal == null || level == null || start == null) return null;
    return RunPlanConfig(
      goal: goal,
      level: level,
      weeks: ((j['weeks'] as num?)?.toInt() ?? 8).clamp(4, 20),
      perWeek: ((j['per_week'] as num?)?.toInt() ?? 3).clamp(3, 6),
      start: start,
      done: {for (final d in (j['done'] as List? ?? const [])) '$d'},
    );
  }
}

/// Recommended plan length for a goal and level, in weeks.
int suggestedWeeks(RunGoal g, RunLevel l) {
  final base = switch (g) {
    RunGoal.k5 => 8,
    RunGoal.k10 => 10,
    RunGoal.half => 12,
    RunGoal.marathon => 16,
    RunGoal.base => 8,
  };
  return l == RunLevel.beginner ? base + 2 : base;
}

/// The Monday on or before [d].
DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

enum RunPhase { base, build, peak, taper }

String phaseLabel(RunPhase p, bool de) => switch (p) {
      RunPhase.base => de ? 'Grundlage' : 'Base',
      RunPhase.build => de ? 'Aufbau' : 'Build',
      RunPhase.peak => de ? 'Spitze' : 'Peak',
      RunPhase.taper => 'Taper',
    };

int taperWeeks(RunGoal g) => switch (g) {
      RunGoal.k5 || RunGoal.k10 => 1,
      RunGoal.half => 2,
      RunGoal.marathon => 2,
      RunGoal.base => 0,
    };

/// Phase of 0-based [week] in a plan of [weeks].
RunPhase phaseOf(RunGoal g, int week, int weeks) {
  final taper = taperWeeks(g);
  if (week >= weeks - taper) return RunPhase.taper;
  final body = weeks - taper;
  final f = week / body;
  if (g == RunGoal.base) return f < .5 ? RunPhase.base : RunPhase.build;
  if (f < .35) return RunPhase.base;
  if (f < .75) return RunPhase.build;
  return RunPhase.peak;
}

/// Every fourth week is easier, except in the taper (already easy) and the
/// week before it (that is where the peak sits).
bool isDeload(RunGoal g, int week, int weeks) =>
    (week + 1) % 4 == 0 &&
    phaseOf(g, week, weeks) != RunPhase.taper &&
    week < weeks - taperWeeks(g) - 1;

class PlannedRun {
  final int week; // 0-based
  final int weekday; // 1 = Monday … 7 = Sunday
  final RunWorkout workout;
  const PlannedRun(this.week, this.weekday, this.workout);

  String get key => '$week-$weekday';
}

class RunWeek {
  final int index;
  final RunPhase phase;
  final bool deload;
  final List<PlannedRun> runs;
  const RunWeek(this.index, this.phase, this.deload, this.runs);

  int get totalSec => runs.fold(0, (a, r) => a + r.workout.totalSec);
}

// ─────────────── building blocks ───────────────

const _min = 60;

RunStep _warm(int m) =>
    RunStep('warm', m * _min, 1, 2, 'Einlaufen', 'Warm up');
RunStep _cool(int m) =>
    RunStep('cool', m * _min, 1, 2, 'Auslaufen', 'Cool down');
RunStep _easyStep(int m, {int lo = 2, int hi = 2}) =>
    RunStep('steady', m * _min, lo, hi, 'Locker Zone $lo${hi != lo ? '–$hi' : ''}',
        'Easy zone $lo${hi != lo ? '–$hi' : ''}');

List<RunStep> _reps(int n, RunStep work, RunStep rest) => [
      for (var i = 0; i < n; i++) ...[
        work,
        if (i < n - 1) rest,
      ]
    ];

/// The steps for [kind] at a given scale. [scale] is 0..1 through the
/// plan's progression; [lvl] 0 beginner, 1 intermediate, 2 advanced.
RunWorkout buildWorkout(RunKind kind, RunGoal goal,
    {double scale = .5, int lvl = 1, bool deload = false}) {
  // Easy-run length by level, grows a little through the plan.
  final easyBase = [30, 40, 50][lvl];
  final easyMin = (easyBase + scale * [10, 15, 20][lvl]).round();
  double d(double v) => deload ? v * .75 : v;
  int r5(double v) => math.max(5, (v / 5).round() * 5);

  switch (kind) {
    case RunKind.recovery:
      final m = r5(d(easyBase * .75));
      return RunWorkout(kind, [_easyStep(m, lo: 1, hi: 1)],
          '$m min Zone 1', '$m min zone 1');
    case RunKind.easy:
      final m = r5(d(easyMin.toDouble()));
      return RunWorkout(kind, [_easyStep(m, lo: 1, hi: 2)],
          '$m min Zone 1–2', '$m min zone 1–2');
    case RunKind.strides:
      final m = r5(d(easyMin * .85));
      final n = lvl == 0 ? 4 : 6;
      return RunWorkout(
        kind,
        [
          _easyStep(m, lo: 1, hi: 2),
          ..._reps(
            n,
            const RunStep('work', 20, null, null, 'Steigerung: zügig, locker',
                'Stride: fast, relaxed'),
            const RunStep('rest', 60, null, null, 'Gehen/Traben', 'Walk/jog'),
          ),
        ],
        '$m min locker + $n × 20 s Steigerung',
        '$m min easy + $n × 20 s strides',
      );
    case RunKind.long:
      final (lo, hi) = switch (goal) {
        RunGoal.marathon => (90, [120, 150, 170][lvl]),
        RunGoal.half => (70, [95, 110, 125][lvl]),
        RunGoal.k10 => (55, [70, 85, 95][lvl]),
        RunGoal.k5 => (45, [60, 70, 80][lvl]),
        RunGoal.base => (45, [60, 75, 90][lvl]),
      };
      final m = r5(d(lo + (hi - lo) * scale));
      return RunWorkout(kind, [_easyStep(m, lo: 1, hi: 2)],
          '$m min Zone 2', '$m min zone 2');
    case RunKind.longFinish:
      final total = buildWorkout(RunKind.long, goal,
              scale: scale, lvl: lvl, deload: deload)
          .totalSec ~/
          _min;
      final fast = goal == RunGoal.marathon
          ? r5(20 + 25 * scale)
          : r5(10 + 10 * scale);
      final zone = goal == RunGoal.marathon ? 3 : 4;
      return RunWorkout(
        kind,
        [
          _easyStep(total - fast, lo: 1, hi: 2),
          RunStep('work', fast * _min, 3, zone,
              'Renntempo Zone $zone', 'Race pace zone $zone'),
        ],
        '${total - fast} min Zone 2 + $fast min Zone $zone',
        '${total - fast} min zone 2 + $fast min zone $zone',
      );
    case RunKind.tempo:
      // Marathon/half pace, zone 3. Blocks grow through the plan.
      final block = goal == RunGoal.marathon
          ? r5(d(15 + 15 * scale))
          : r5(d(10 + 10 * scale));
      final n = scale < .3 ? 2 : (goal == RunGoal.marathon ? 3 : 2);
      return RunWorkout(
        kind,
        [
          _warm(15),
          ..._reps(
            n,
            RunStep('work', block * _min, 3, 3, 'Zone 3 – Renntempo',
                'Zone 3 – race pace'),
            const RunStep('rest', 3 * _min, 1, 2, 'Locker traben', 'Easy jog'),
          ),
          _cool(10),
        ],
        '$n × $block min Zone 3 · 3 min locker',
        '$n × $block min zone 3 · 3 min easy',
      );
    case RunKind.threshold:
      // Cruise intervals early, longer continuous blocks later (Daniels T).
      final (n, m) = scale < .35
          ? (lvl == 0 ? 3 : 4, 5)
          : scale < .7
              ? (3, lvl == 0 ? 8 : 10)
              : (2, lvl == 0 ? 12 : (lvl == 1 ? 15 : 20));
      final reps = deload ? math.max(2, n - 1) : n;
      return RunWorkout(
        kind,
        [
          _warm(15),
          ..._reps(
            reps,
            RunStep('work', m * _min, 4, 4, 'Schwelle Zone 4',
                'Threshold zone 4'),
            RunStep('rest', (m >= 10 ? 3 : 2) * _min, 1, 2, 'Trabpause',
                'Jog recovery'),
          ),
          _cool(10),
        ],
        '$reps × $m min Zone 4 · ${m >= 10 ? 3 : 2} min Trabpause',
        '$reps × $m min zone 4 · ${m >= 10 ? 3 : 2} min jog',
      );
    case RunKind.vo2:
      // Reps of 2–5 min at zone 5, rest about equal to the rep (Daniels I).
      // HR needs a minute or two to climb, so zone 4 counts in the rep.
      final (n, m) = switch (goal) {
        RunGoal.k5 => scale < .4 ? (5, 2) : scale < .75 ? (5, 3) : (5, 4),
        RunGoal.k10 => scale < .4 ? (5, 3) : (5, 4),
        _ => scale < .5 ? (5, 3) : (4, 4),
      };
      final reps = lvl == 0 ? n - 1 : (lvl == 2 ? n + 1 : n);
      final r = deload ? math.max(3, reps - 2) : reps;
      final rest = m <= 2 ? 2 : (m == 3 ? 2 : 3);
      return RunWorkout(
        kind,
        [
          _warm(15),
          ..._reps(
            r,
            RunStep('work', m * _min, 4, 5, 'Hart: Zone 5', 'Hard: zone 5'),
            RunStep('rest', rest * _min, null, null, 'Trabpause',
                'Jog recovery'),
          ),
          _cool(10),
        ],
        '$r × $m min Zone 5 · $rest min Trabpause',
        '$r × $m min zone 5 · $rest min jog',
      );
    case RunKind.hills:
      final n = [6, 8, 10][lvl];
      final r = deload ? n - 2 : n;
      return RunWorkout(
        kind,
        [
          _warm(15),
          ..._reps(
            r,
            const RunStep('work', 60, null, null, 'Bergauf: kräftig',
                'Uphill: strong'),
            const RunStep('rest', 90, null, null, 'Locker zurück',
                'Easy back down'),
          ),
          _cool(10),
        ],
        '$r × 60 s bergauf · locker zurück',
        '$r × 60 s uphill · easy back down',
      );
    case RunKind.fartlek:
      final n = [5, 6, 8][lvl];
      return RunWorkout(
        kind,
        [
          _warm(10),
          ..._reps(
            n,
            const RunStep('work', 2 * _min, 3, 4, 'Zügig Zone 3–4',
                'Brisk zone 3–4'),
            const RunStep('rest', 2 * _min, 1, 2, 'Locker', 'Easy'),
          ),
          _cool(10),
        ],
        '$n × 2 min zügig · 2 min locker',
        '$n × 2 min brisk · 2 min easy',
      );
    case RunKind.race:
      final m = goalMeters(goal);
      return RunWorkout(
        kind,
        [
          _warm(goal == RunGoal.marathon ? 5 : 15),
          RunStep(
              'work',
              switch (goal) {
                RunGoal.k5 => 25,
                RunGoal.k10 => 55,
                RunGoal.half => 120,
                _ => 240,
              } *
                  _min,
              null,
              null,
              'Wettkampf ${m == null ? '' : '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km'}',
              'Race'),
        ],
        'Wettkampf: ${goalLabel(goal, true)}',
        'Race: ${goalLabel(goal, false)}',
      );
  }
}

/// The two quality sessions of a week for [goal] in [phase], first the main
/// one. A beginner's base phase gets strides and hills instead of intervals.
List<RunKind> qualityFor(RunGoal goal, RunPhase phase, RunLevel level,
    int week) {
  final alt = week.isOdd;
  if (level == RunLevel.beginner && phase == RunPhase.base) {
    return [alt ? RunKind.hills : RunKind.fartlek, RunKind.strides];
  }
  return switch ((goal, phase)) {
    (RunGoal.k5, RunPhase.base) => [RunKind.hills, RunKind.threshold],
    (RunGoal.k5, RunPhase.build) => [RunKind.vo2, RunKind.threshold],
    (RunGoal.k5, RunPhase.peak) => [RunKind.vo2, alt ? RunKind.hills : RunKind.threshold],
    (RunGoal.k5, RunPhase.taper) => [RunKind.vo2, RunKind.strides],
    (RunGoal.k10, RunPhase.base) => [RunKind.threshold, RunKind.hills],
    (RunGoal.k10, RunPhase.build) => [RunKind.threshold, RunKind.vo2],
    (RunGoal.k10, RunPhase.peak) => [alt ? RunKind.vo2 : RunKind.threshold, alt ? RunKind.threshold : RunKind.vo2],
    (RunGoal.k10, RunPhase.taper) => [RunKind.threshold, RunKind.strides],
    (RunGoal.half, RunPhase.base) => [RunKind.tempo, RunKind.hills],
    (RunGoal.half, RunPhase.build) => [RunKind.threshold, RunKind.tempo],
    (RunGoal.half, RunPhase.peak) => [RunKind.threshold, alt ? RunKind.vo2 : RunKind.tempo],
    (RunGoal.half, RunPhase.taper) => [RunKind.threshold, RunKind.strides],
    (RunGoal.marathon, RunPhase.base) => [RunKind.tempo, RunKind.hills],
    (RunGoal.marathon, RunPhase.build) => [RunKind.tempo, RunKind.threshold],
    (RunGoal.marathon, RunPhase.peak) => [RunKind.tempo, RunKind.threshold],
    (RunGoal.marathon, RunPhase.taper) => [RunKind.tempo, RunKind.strides],
    (RunGoal.base, _) => [alt ? RunKind.fartlek : RunKind.hills, RunKind.strides],
  };
}

/// Which weekdays carry which slot. Hard days never follow each other.
/// Slots: q1, q2, long, easy, strides, recovery.
List<(int, String)> weekLayout(int perWeek) => switch (perWeek) {
      3 => [(2, 'q1'), (4, 'easy'), (7, 'long')],
      4 => [(2, 'q1'), (3, 'easy'), (5, 'strides'), (7, 'long')],
      5 => [(2, 'q1'), (3, 'easy'), (4, 'q2'), (6, 'easy'), (7, 'long')],
      _ => [
          (1, 'recovery'),
          (2, 'q1'),
          (3, 'easy'),
          (4, 'q2'),
          (5, 'strides'),
          (7, 'long'),
        ],
    };

/// The whole plan.
List<RunWeek> buildPlan(RunPlanConfig cfg) {
  final lvl = cfg.level.index;
  final out = <RunWeek>[];
  final body = math.max(1, cfg.weeks - taperWeeks(cfg.goal) - 1);
  for (var w = 0; w < cfg.weeks; w++) {
    final phase = phaseOf(cfg.goal, w, cfg.weeks);
    final deload = isDeload(cfg.goal, w, cfg.weeks);
    final last = w == cfg.weeks - 1;
    // Progress 0..1 up to the peak week; the taper steps back down.
    var scale = (w / body).clamp(0.0, 1.0);
    if (phase == RunPhase.taper) {
      scale = last ? .2 : .5;
    }
    final q = qualityFor(cfg.goal, phase, cfg.level, w);
    final runs = <PlannedRun>[];
    // Only intermediate+ get a second hard day; a beginner's q2 is easy.
    // A fast-finish long run is the week's second hard day already.
    final fastLong = phase == RunPhase.peak &&
        (cfg.goal == RunGoal.marathon || cfg.goal == RunGoal.half) &&
        w.isEven;
    final hardQ2 = cfg.level != RunLevel.beginner && !deload && !fastLong;
    for (final (day, slot) in weekLayout(cfg.perWeek)) {
      RunKind kind = switch (slot) {
        'q1' => q[0],
        'q2' => hardQ2 ? q[1] : RunKind.easy,
        'long' => fastLong ? RunKind.longFinish : RunKind.long,
        'strides' => RunKind.strides,
        'recovery' => RunKind.recovery,
        _ => RunKind.easy,
      };
      // Race week: the long-run day is the race itself.
      if (last && slot == 'long' && cfg.goal != RunGoal.base) {
        kind = RunKind.race;
      }
      runs.add(PlannedRun(
          w,
          day,
          buildWorkout(kind, cfg.goal,
              scale: scale, lvl: lvl, deload: deload || phase == RunPhase.taper)));
    }
    out.add(RunWeek(w, phase, deload, runs));
  }
  return out;
}

/// 0-based week index of [day] in the plan, or null outside it.
int? weekIndexOf(RunPlanConfig cfg, DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  // Count calendar days, not hours: DST weeks are 167 or 169 hours long.
  final days = DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(cfg.start.year, cfg.start.month, cfg.start.day))
      .inDays;
  if (days < 0) return null;
  final w = days ~/ 7;
  return w < cfg.weeks ? w : null;
}

DateTime dateOf(RunPlanConfig cfg, PlannedRun r) => DateTime(
    cfg.start.year, cfg.start.month, cfg.start.day + r.week * 7 + r.weekday - 1);

/// Today's run, if the plan has one today.
PlannedRun? runOn(List<RunWeek> plan, RunPlanConfig cfg, DateTime day) {
  final w = weekIndexOf(cfg, day);
  if (w == null) return null;
  return plan[w].runs.where((r) => r.weekday == day.weekday).firstOrNull;
}

/// The next run not yet done, today or later.
PlannedRun? nextRun(List<RunWeek> plan, RunPlanConfig cfg, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (final w in plan) {
    for (final r in w.runs) {
      if (cfg.done.contains(r.key)) continue;
      if (!dateOf(cfg, r).isBefore(today)) return r;
    }
  }
  return null;
}

/// What the coach says about today given recovery (0..100, null unknown) and
/// hours still needed from recent training.
({bool swap, String de, String en})? adviseToday(
    RunWorkout w, double? recovery, int? recoveryLeftH) {
  if (!w.quality) return null;
  if (recovery != null && recovery < 34) {
    return (
      swap: true,
      de: 'Deine Erholung ist niedrig (${recovery.round()} %). Heute lieber '
          '30 min locker in Zone 1–2 und das harte Training auf morgen schieben.',
      en: 'Your recovery is low (${recovery.round()} %). Go 30 min easy in '
          'zones 1–2 today and move the hard session to tomorrow.',
    );
  }
  if (recoveryLeftH != null && recoveryLeftH >= 24) {
    return (
      swap: true,
      de: 'Dein letztes Training braucht noch etwa $recoveryLeftH h Erholung. '
          'Locker laufen oder einen Tag tauschen.',
      en: 'Your last session still needs about $recoveryLeftH h of recovery. '
          'Run easy or swap a day.',
    );
  }
  if (recovery != null && recovery < 67) {
    return (
      swap: false,
      de: 'Erholung mittel (${recovery.round()} %). Das Training geht, halte '
          'dich aber an das untere Ende der Zielzone.',
      en: 'Recovery is moderate (${recovery.round()} %). Go ahead, but stay '
          'at the low end of the target zone.',
    );
  }
  return null;
}

/// The easy alternative offered when the coach advises against a hard day.
RunWorkout easySwap(RunGoal goal) =>
    buildWorkout(RunKind.easy, goal, scale: 0, lvl: 0);

// ─────────────── pace from VO2max (Daniels) ───────────────

/// Velocity (m/min) at which running costs [vo2] ml/kg/min — the inverse of
/// Daniels' oxygen-cost equation (VO2 = −4.60 + 0.182258 v + 0.000104 v²).
double velocityForVo2(double vo2) {
  const a = .000104, b = .182258, c = -4.60;
  return (-b + math.sqrt(b * b - 4 * a * (c - vo2))) / (2 * a);
}

/// Seconds per km at fraction [f] of [vo2max].
double paceAt(double vo2max, double f) => 60000 / velocityForVo2(vo2max * f);

/// A pace band for a zone band, from Daniels' intensity fractions: E 59–74 %,
/// M 75–84 %, T 83–88 %, I 95–100 % of VDOT. Null below VO2max 25 or when
/// the step has no zone (strides, hills).
({double fast, double slow})? paceBand(double? vo2max, int? zLo, int? zHi) {
  if (vo2max == null || vo2max < 25 || zLo == null || zHi == null) return null;
  (double, double) frac(int z) => switch (z) {
        1 => (.59, .65),
        2 => (.65, .74),
        3 => (.75, .84),
        4 => (.84, .88),
        _ => (.95, 1.0),
      };
  final lo = frac(zLo).$1, hi = frac(zHi).$2;
  return (fast: paceAt(vo2max, hi), slow: paceAt(vo2max, lo));
}

String paceText(double secPerKm) {
  final s = secPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// ─────────────── store ───────────────

class RunCoachStore {
  RunCoachStore._();
  static const kRunCoachPref = 'edgeplus.run_coach.v1';

  static RunPlanConfig? load() {
    final raw = Prefs.getString(kRunCoachPref, '');
    if (raw.isEmpty) return null;
    try {
      return RunPlanConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static void save(RunPlanConfig? c) =>
      Prefs.setString(kRunCoachPref, c == null ? '' : jsonEncode(c.toJson()));

  static void toggleDone(String runKey) {
    final c = load();
    if (c == null) return;
    final d = {...c.done};
    if (!d.remove(runKey)) d.add(runKey);
    save(c.copyWith(done: d));
  }

  static void markDone(String runKey) {
    final c = load();
    if (c == null || c.done.contains(runKey)) return;
    save(c.copyWith(done: {...c.done, runKey}));
  }
}
