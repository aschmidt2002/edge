// Edge+: the running coach screen — set a goal distance, get a periodised plan
// in the user's own heart rate zones, start a workout and be guided through it
// by the band.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../activity/live.dart';
import '../activity/run_coach.dart';
import '../activity/run_insights.dart' show recentVo2max, recoveryLeft;
import '../activity/run_live_panel.dart';
import '../activity/summary.dart' show clock;
import '../activity/zones.dart';
import '../ui2.dart';
import 'home_screen.dart' show repoOf;
import 'workout_screen.dart' show activityHost;

/// Open a running session with [workout] as its guide (and/or a planned
/// route), then the live screen. Returns false when another session is
/// already running.
Future<bool> startGuidedRun(
  BuildContext c, {
  RunWorkout? workout,
  String? planKey,
  ({String name, double m})? plannedRoute,
  double? weightKg,
  String activity = 'running',
}) async {
  final a = activityByName(activity);
  if (a == null) return false;
  final app = c.read<AppState>();
  final nav = Navigator.of(c);
  final messenger = ScaffoldMessenger.maybeOf(c);
  final busy = tr(c, 'Es läuft schon eine Einheit. Beende sie zuerst.',
      'A session is already running. Finish it first.');
  final host = activityHost(app);
  final ok = await host.onStart?.call(a) ?? false;
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text(busy)));
    return false;
  }
  final d = LiveDraft.begin(a, weightKg: weightKg);
  if (workout != null) d.put(kRunGuideKey, workout.toJson());
  if (planKey != null) {
    d.put(kRunGuidePlanKey, planKey);
    RunCoachStore.markDone(planKey);
  }
  if (plannedRoute != null) {
    d.put(kRunPlannedRouteKey, {'name': plannedRoute.name, 'm': plannedRoute.m});
  }
  await nav.push(MaterialPageRoute<void>(
      builder: (_) => liveFor(a, weightKg: weightKg, host: host)));
  return true;
}

bool _de(BuildContext c) => Localizations.localeOf(c).languageCode == 'de';

String _dur(int sec) {
  final m = (sec / 60).round();
  return m >= 60 ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}' : '$m min';
}

String _weekday(BuildContext c, int wd) {
  const de = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return (_de(c) ? de : en)[wd - 1];
}

Color _kindColor(RunKind k) => switch (k) {
      RunKind.recovery || RunKind.easy || RunKind.strides => C.green,
      RunKind.long || RunKind.longFinish => C.blue,
      RunKind.tempo || RunKind.fartlek => C.yellow,
      RunKind.threshold || RunKind.hills => C.orange,
      RunKind.vo2 || RunKind.race => C.red,
    };

/// What the coach screens read once on open.
class CoachContext {
  final ZonesData? zones;
  final double? vo2max;
  final double? recovery;
  final int? recoveryLeftH;

  /// Minutes in zones 1–2 and 3–5 over the last 28 days of runs.
  final int easyMin, hardMin;

  const CoachContext(
      {this.zones,
      this.vo2max,
      this.recovery,
      this.recoveryLeftH,
      this.easyMin = 0,
      this.hardMin = 0});

  static Future<CoachContext> load(BuildContext c) async {
    final repo = repoOf(c);
    if (repo == null) return const CoachContext();
    ZonesData? zones;
    double? vo2, rec;
    int? left;
    var easy = 0, hard = 0;
    try {
      zones = await ZonesData.load(repo);
    } catch (_) {}
    try {
      final now = DateTime.now();
      final nowS = now.millisecondsSinceEpoch ~/ 1000;
      final sessions =
          await repo.getSessions(from: nowS - 180 * 86400, includeDetected: false);
      vo2 = recentVo2max(sessions);
      left = recoveryLeft([
        for (final s in sessions)
          if (((s['end_ts'] as num?) ?? 0) > nowS - 4 * 86400) s
      ], now);
      for (final s in sessions) {
        final t = (s['type'] as String? ?? '').toLowerCase();
        if (!t.contains('run')) continue;
        if (((s['start_ts'] as num?) ?? 0) < nowS - 28 * 86400) continue;
        final z = s['zone_min'];
        if (z is List && z.length >= 5) {
          for (var i = 0; i < 5; i++) {
            final v = ((z[i] as num?) ?? 0).round();
            if (i < 2) {
              easy += v;
            } else {
              hard += v;
            }
          }
        }
      }
    } catch (_) {}
    try {
      final o = await repo.getDayOverview(todayLabel());
      rec = (o['readiness'] as num?)?.toDouble();
    } catch (_) {}
    return CoachContext(
        zones: zones,
        vo2max: vo2,
        recovery: rec,
        recoveryLeftH: left,
        easyMin: easy,
        hardMin: hard);
  }

  String? bpm(int? lo, int? hi) {
    final z = zones?.zones;
    if (lo == null || hi == null || z == null || z.isEmpty) return null;
    final a = z.where((r) => r.zone == lo).firstOrNull;
    final b = z.where((r) => r.zone == hi).firstOrNull;
    if (a == null || b == null) return null;
    return '${a.lo}–${b.hi} bpm';
  }
}

class RunCoachScreen extends StatefulWidget {
  final double? weightKg;
  const RunCoachScreen({super.key, this.weightKg});

  @override
  State<RunCoachScreen> createState() => _RunCoachScreenState();
}

class _RunCoachScreenState extends State<RunCoachScreen> {
  RunPlanConfig? cfg = RunCoachStore.load();
  CoachContext ctx = const CoachContext();
  int? _openWeek;

  @override
  void initState() {
    super.initState();
    CoachContext.load(context).then((v) {
      if (mounted) setState(() => ctx = v);
    });
  }

  void _reload() => setState(() => cfg = RunCoachStore.load());

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final cfg = this.cfg;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(
              tr(c, 'Lauf-Coach', 'Run coach'),
              trailing: cfg == null
                  ? null
                  : Pressable(
                      semanticLabel: tr(c, 'Plan ändern', 'Change plan'),
                      onTap: () => _setup(c),
                      child: Icon(LucideIcons.settings2, size: 22, color: p.ink),
                    ),
            ),
          ),
          Expanded(
            child: cfg == null
                ? _empty(c, p)
                : _plan(c, p, cfg),
          ),
        ]),
      ),
    );
  }

  Future<void> _setup(BuildContext c) async {
    await Navigator.of(c).push(MaterialPageRoute<void>(
        builder: (_) => RunPlanSetup(current: cfg)));
    _reload();
  }

  Widget _empty(BuildContext c, P p) => ListView(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
        children: [
          StatusCard(
            tr(c, 'Noch kein Laufplan', 'No running plan yet'),
            tr(
                c,
                'Wähle deine Zieldistanz. Der Coach baut dir einen Plan in '
                    'deinen eigenen Herzfrequenzzonen: viel locker in Zone 2, '
                    'gezielt hart, je nach Distanz andere Schwerpunkte. Beim '
                    'Laufen sagt dir das Band per Vibration, ob du in der '
                    'Zielzone bist.',
                'Pick your goal distance. The coach builds a plan in your own '
                    'heart rate zones: mostly easy in zone 2, hard on purpose, '
                    'with a different focus per distance. While running the '
                    'band buzzes when you leave the target zone.'),
            icon: LucideIcons.target,
          ),
          const SizedBox(height: S.x4),
          BigButton(tr(c, 'Plan erstellen', 'Create plan'),
              icon: LucideIcons.sparkles, onTap: () => _setup(c)),
          const SizedBox(height: S.x5),
          _zonesCard(c, p),
          const SizedBox(height: S.x3),
          _distributionCard(c, p),
          const SizedBox(height: S.x3),
          _quickWorkouts(c, p),
        ],
      );

  Widget _plan(BuildContext c, P p, RunPlanConfig cfg) {
    final plan = buildPlan(cfg);
    final now = DateTime.now();
    final wi = weekIndexOf(cfg, now);
    final next = nextRun(plan, cfg, now);
    final de = _de(c);
    final doneCount = cfg.done.length;
    final total = plan.fold<int>(0, (a, w) => a + w.runs.length);
    _openWeek ??= wi ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
      children: [
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(LucideIcons.flag, size: 20, color: p.on(C.green)),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(goalLabel(cfg.goal, de),
                    style: F.head.copyWith(color: p.ink)),
              ),
            ]),
            if (wi != null) ...[
              const SizedBox(height: S.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: Pill(
                    '${tr(c, 'Woche', 'Week')} ${wi + 1}/${cfg.weeks} · '
                    '${phaseLabel(plan[wi].phase, de)}',
                    C.green,
                    wrap: true),
              ),
            ],
            const SizedBox(height: S.x3),
            ClipRRect(
              borderRadius: R.rPill,
              child: LinearProgressIndicator(
                  value: total == 0 ? 0 : doneCount / total,
                  minHeight: 8,
                  backgroundColor: p.card2,
                  color: p.on(C.green)),
            ),
            const SizedBox(height: S.x2),
            Text(
                tr(c, '$doneCount von $total Einheiten erledigt',
                    '$doneCount of $total sessions done'),
                style: F.cap.copyWith(color: p.ink3)),
            if (wi == null && now.isBefore(cfg.start))
              Text(
                  tr(c, 'Der Plan beginnt am ${cfg.start.day}.${cfg.start.month}.',
                      'The plan starts on ${cfg.start.month}/${cfg.start.day}.'),
                  style: F.cap.copyWith(color: p.ink2)),
          ]),
        ),
        const SizedBox(height: S.x3),
        if (next != null) _nextCard(c, p, cfg, next) else
          StatusCard(
              tr(c, 'Plan abgeschlossen', 'Plan complete'),
              tr(c, 'Stark! Erstelle einen neuen Plan für dein nächstes Ziel.',
                  'Well done! Create a new plan for your next goal.'),
              icon: LucideIcons.trophy,
              fix: tr(c, 'Neuer Plan', 'New plan'),
              onFix: () => _setup(c)),
        Section(
          tr(c, 'Wochen', 'Weeks'),
          Column(children: [
            for (final w in plan) ...[
              _weekCard(c, p, cfg, w, wi),
              const SizedBox(height: S.x2),
            ],
          ]),
        ),
        _zonesCard(c, p),
        const SizedBox(height: S.x3),
        _distributionCard(c, p),
        const SizedBox(height: S.x3),
        _quickWorkouts(c, p),
      ],
    );
  }

  Widget _nextCard(BuildContext c, P p, RunPlanConfig cfg, PlannedRun r) {
    final de = _de(c);
    final date = dateOf(cfg, r);
    final now = DateTime.now();
    final today = date.year == now.year && date.month == now.month && date.day == now.day;
    final info = kindInfo(r.workout.kind);
    final advice = today
        ? adviseToday(r.workout, ctx.recovery, ctx.recoveryLeftH)
        : null;
    final col = _kindColor(r.workout.kind);
    return Surface(
      onTap: () => _openWorkout(c, r.workout, r.key),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            today
                ? tr(c, 'HEUTE', 'TODAY')
                : '${tr(c, 'NÄCHSTES TRAINING', 'NEXT SESSION')} · '
                    '${_weekday(c, r.weekday)} ${date.day}.${date.month}.',
            style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x2),
        Row(children: [
          Container(
            width: 10,
            height: 36,
            decoration: BoxDecoration(color: p.on(col), borderRadius: R.rSm),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(de ? info.de : info.en, style: F.head.copyWith(color: p.ink)),
              Text(de ? r.workout.structDe : r.workout.structEn,
                  style: F.cap.copyWith(color: p.ink2)),
            ]),
          ),
          Text(_dur(r.workout.totalSec), style: F.body.copyWith(color: p.ink)),
        ]),
        const SizedBox(height: S.x2),
        Text(de ? info.whyDe : info.whyEn, style: F.cap.copyWith(color: p.ink3)),
        if (advice != null) ...[
          const SizedBox(height: S.x3),
          Container(
            padding: const EdgeInsets.all(S.x3),
            decoration: BoxDecoration(
                color: p.wash(advice.swap ? C.orange : C.yellow),
                borderRadius: R.rMd),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(LucideIcons.batteryLow, size: 16,
                  color: p.on(advice.swap ? C.orange : C.yellow)),
              const SizedBox(width: S.x2),
              Expanded(
                  child: Text(de ? advice.de : advice.en,
                      style: F.cap.copyWith(color: p.ink))),
            ]),
          ),
        ],
        const SizedBox(height: S.x3),
        BigButton(tr(c, 'Workout starten', 'Start workout'),
            icon: LucideIcons.play,
            onTap: () => startGuidedRun(c,
                    workout: r.workout,
                    planKey: r.key,
                    weightKg: widget.weightKg)
                .then((_) => _reload())),
        if (advice != null && advice.swap) ...[
          const SizedBox(height: S.x2),
          BigButton(tr(c, 'Stattdessen locker laufen', 'Run easy instead'),
              icon: LucideIcons.leaf,
              soft: true,
              onTap: () => startGuidedRun(c,
                      workout: easySwap(cfg.goal), weightKg: widget.weightKg)
                  .then((_) => _reload())),
        ],
      ]),
    );
  }

  Widget _weekCard(
      BuildContext c, P p, RunPlanConfig cfg, RunWeek w, int? current) {
    final de = _de(c);
    final open = _openWeek == w.index;
    final done = w.runs.where((r) => cfg.done.contains(r.key)).length;
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      onTap: () => setState(() => _openWeek = open ? -1 : w.index),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${tr(c, 'Woche', 'Week')} ${w.index + 1} · '
                  '${phaseLabel(w.phase, de)}'
                  '${w.deload ? tr(c, ' · Entlastung', ' · easier week') : ''}',
                  style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: current == w.index
                          ? FontWeight.w800
                          : FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text('$done/${w.runs.length} · ${_dur(w.totalSec)}',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 16, color: p.ink3),
        ]),
        if (open) ...[
          const SizedBox(height: S.x2),
          for (final r in w.runs) _runRow(c, p, cfg, r),
        ],
      ]),
    );
  }

  Widget _runRow(BuildContext c, P p, RunPlanConfig cfg, PlannedRun r) {
    final de = _de(c);
    final info = kindInfo(r.workout.kind);
    final done = cfg.done.contains(r.key);
    final date = dateOf(cfg, r);
    return Pressable(
      onTap: () => _openWorkout(c, r.workout, r.key),
      semanticLabel: de ? info.de : info.en,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(children: [
          SizedBox(
            width: 52,
            child: Text('${_weekday(c, r.weekday)} ${date.day}.${date.month}.',
                style: F.cap.copyWith(color: p.ink3)),
          ),
          Container(
              width: 6,
              height: 28,
              decoration: BoxDecoration(
                  color: p.on(_kindColor(r.workout.kind)),
                  borderRadius: R.rSm)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(de ? info.de : info.en,
                  style: F.body.copyWith(
                      color: done ? p.ink3 : p.ink,
                      decoration: done ? TextDecoration.lineThrough : null)),
              Text(de ? r.workout.structDe : r.workout.structEn,
                  style: F.cap.copyWith(color: p.ink3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          Pressable(
            semanticLabel: tr(c, 'Erledigt', 'Done'),
            onTap: () {
              RunCoachStore.toggleDone(r.key);
              _reload();
            },
            child: Padding(
              padding: const EdgeInsets.all(S.x2),
              child: Icon(done ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 22, color: done ? p.on(C.green) : p.ink3),
            ),
          ),
        ]),
      ),
    );
  }

  void _openWorkout(BuildContext c, RunWorkout w, String? key) =>
      Navigator.of(c)
          .push(MaterialPageRoute<void>(
              builder: (_) => RunWorkoutDetail(
                  workout: w, planKey: key, ctx: ctx, weightKg: widget.weightKg)))
          .then((_) => _reload());

  Widget _zonesCard(BuildContext c, P p) {
    final z = ctx.zones?.zones ?? const [];
    const names = [
      ('Regeneration', 'Recovery'),
      ('Grundlage', 'Easy / base'),
      ('Renntempo M/HM', 'Marathon pace'),
      ('Schwelle', 'Threshold'),
      ('VO2max', 'VO2max'),
    ];
    const cols = [C.blueSoft, C.green, C.yellow, C.orange, C.red];
    final de = _de(c);
    return Section(
      tr(c, 'Deine Zonen', 'Your zones'),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 1; i <= 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: p.on(cols[i - 1]), shape: BoxShape.circle)),
                const SizedBox(width: S.x2),
                SizedBox(width: 28, child: Text('Z$i', style: F.body.copyWith(color: p.ink))),
                Expanded(
                    child: Text(de ? names[i - 1].$1 : names[i - 1].$2,
                        style: F.cap.copyWith(color: p.ink2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Text(
                    [
                      ?ctx.bpm(i, i),
                      if (paceBand(ctx.vo2max, i, i) case final b?)
                        '${paceText(b.fast)}–${paceText(b.slow)}/km',
                    ].join(' · '),
                    style: F.cap.copyWith(color: p.ink)),
              ]),
            ),
          if (z.isEmpty) ...[
            const SizedBox(height: S.x2),
            Text(
                tr(c, 'Noch keine Zonen: trag dein Alter im Profil ein oder '
                        'trage das Band bei ein paar harten Einheiten.',
                    'No zones yet: add your age in Profile or wear the band '
                        'for a few hard sessions.'),
                style: F.cap.copyWith(color: p.ink3)),
          ],
          if (ctx.vo2max != null) ...[
            const SizedBox(height: S.x2),
            Text(
                tr(c, 'Pace-Richtwerte aus deiner geschätzten VO2max '
                        '(${ctx.vo2max!.toStringAsFixed(0)}) nach Daniels. Der '
                        'Puls entscheidet, die Pace ist nur Orientierung.',
                    'Pace guides from your estimated VO2max '
                        '(${ctx.vo2max!.toStringAsFixed(0)}) after Daniels. '
                        'Heart rate decides, pace is a guide.'),
                style: F.cap.copyWith(color: p.ink3)),
          ],
        ]),
      ),
    );
  }

  Widget _distributionCard(BuildContext c, P p) {
    final total = ctx.easyMin + ctx.hardMin;
    if (total < 30) return const SizedBox.shrink();
    final easy = ctx.easyMin / total;
    final pct = (easy * 100).round();
    final verdict = easy >= .75
        ? tr(c, 'Passt: der Großteil ist locker.', 'Good: most of it is easy.')
        : tr(c, 'Viel im mittleren/harten Bereich. Mehr Zone 2 bringt oft mehr '
                'als jeder Lauf „ein bisschen schnell“.',
            'A lot of moderate/hard running. More zone 2 often brings more '
                'than every run being "a bit fast".');
    return Section(
      tr(c, 'Verteilung letzte 4 Wochen', 'Last 4 weeks'),
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              flex: (easy * 1000).round().clamp(1, 1000),
              child: Container(height: 12, color: p.on(C.green)),
            ),
            Expanded(
              flex: ((1 - easy) * 1000).round().clamp(1, 1000),
              child: Container(height: 12, color: p.on(C.orange)),
            ),
          ]),
          const SizedBox(height: S.x2),
          Text(
              tr(c, '$pct % locker (Z1–2) · ${100 - pct} % zügig/hart (Z3–5) · '
                      'Ziel etwa 80/20',
                  '$pct % easy (Z1–2) · ${100 - pct} % moderate/hard (Z3–5) · '
                      'aim for about 80/20'),
              style: F.cap.copyWith(color: p.ink2)),
          const SizedBox(height: S.x1),
          Text(verdict, style: F.cap.copyWith(color: p.ink3)),
        ]),
      ),
    );
  }

  Widget _quickWorkouts(BuildContext c, P p) {
    final goal = cfg?.goal ?? RunGoal.base;
    final de = _de(c);
    final kinds = [
      RunKind.easy,
      RunKind.long,
      RunKind.tempo,
      RunKind.threshold,
      RunKind.vo2,
      RunKind.hills,
      RunKind.fartlek,
      RunKind.recovery,
    ];
    return Section(
      tr(c, 'Einzelnes Workout', 'Single workout'),
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
        child: Column(children: [
          for (final k in kinds)
            Builder(builder: (c) {
              final w = buildWorkout(k, goal, scale: .5, lvl: (cfg?.level ?? RunLevel.intermediate).index);
              final info = kindInfo(k);
              return Pressable(
                onTap: () => _openWorkout(c, w, null),
                semanticLabel: de ? info.de : info.en,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  child: Row(children: [
                    Container(
                        width: 6,
                        height: 28,
                        decoration: BoxDecoration(
                            color: p.on(_kindColor(k)), borderRadius: R.rSm)),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(de ? info.de : info.en,
                                style: F.body.copyWith(color: p.ink)),
                            Text(de ? w.structDe : w.structEn,
                                style: F.cap.copyWith(color: p.ink3)),
                          ]),
                    ),
                    Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

// ═════════════════ WORKOUT DETAIL ═════════════════

class RunWorkoutDetail extends StatelessWidget {
  final RunWorkout workout;
  final String? planKey;
  final CoachContext ctx;
  final double? weightKg;
  const RunWorkoutDetail(
      {super.key,
      required this.workout,
      this.planKey,
      this.ctx = const CoachContext(),
      this.weightKg});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final de = _de(c);
    final info = kindInfo(workout.kind);
    // Collapse repeated work/rest pairs back into "n ×" rows for reading.
    final rows = <(RunStep, int)>[];
    for (final s in workout.steps) {
      final n = rows.length;
      if (n >= 2 &&
          rows[n - 2].$1.kind == 'work' &&
          s.kind == 'work' &&
          rows[n - 2].$1.sec == s.sec &&
          rows[n - 1].$1.kind == 'rest') {
        rows[n - 2] = (rows[n - 2].$1, rows[n - 2].$2 + 1);
        continue;
      }
      if (n >= 1 && s.kind == 'rest' && rows[n - 1].$1.kind == 'rest') continue;
      rows.add((s, 1));
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(de ? info.de : info.en),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
              children: [
                Surface(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(de ? workout.structDe : workout.structEn,
                            style: F.head.copyWith(color: p.ink)),
                        const SizedBox(height: S.x1),
                        Text(
                            '${tr(c, 'Dauer', 'Duration')} ${_dur(workout.totalSec)}',
                            style: F.cap.copyWith(color: p.ink2)),
                        const SizedBox(height: S.x3),
                        Text(de ? info.whyDe : info.whyEn,
                            style: F.body.copyWith(color: p.ink2)),
                      ]),
                ),
                Section(
                  tr(c, 'Ablauf', 'Steps'),
                  Surface(
                    pad: const EdgeInsets.symmetric(
                        horizontal: S.x4, vertical: S.x2),
                    child: Column(children: [
                      for (final (s, n) in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: S.x2),
                          child: Row(children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                  n > 1 ? '$n × ${clock(s.sec)}' : clock(s.sec),
                                  style: F.body.copyWith(color: p.ink)),
                            ),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(de ? s.de : s.en,
                                        style: F.body.copyWith(color: p.ink)),
                                    Text(
                                        [
                                          if (s.guided)
                                            'Zone ${s.zLo}${s.zHi != s.zLo ? '–${s.zHi}' : ''}'
                                          else
                                            tr(c, 'nach Gefühl', 'by feel'),
                                          ?ctx.bpm(s.zLo, s.zHi),
                                          if (paceBand(ctx.vo2max, s.zLo, s.zHi)
                                              case final b?)
                                            '${paceText(b.fast)}–${paceText(b.slow)}/km',
                                        ].join(' · '),
                                        style:
                                            F.cap.copyWith(color: p.ink3)),
                                  ]),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: S.x3),
                Text(
                    tr(c,
                        'Beim Laufen zeigt der Live-Screen den aktuellen Schritt. '
                            'Das Band vibriert 2× bei jedem Schrittwechsel, 3× wenn '
                            'du zu lange über der Zone bist, 1× wenn du darunter '
                            'bist.',
                        'While running, the live screen shows the current step. '
                            'The band buzzes twice at each step change, three '
                            'times when you stay above the zone, once when '
                            'below.'),
                    style: F.cap.copyWith(color: p.ink3)),
                const SizedBox(height: S.x4),
                BigButton(tr(c, 'Workout starten', 'Start workout'),
                    icon: LucideIcons.play, onTap: () async {
                  final nav = Navigator.of(c);
                  final ok = await startGuidedRun(c,
                      workout: workout, planKey: planKey, weightKg: weightKg);
                  if (ok && nav.mounted) nav.maybePop();
                }),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════ SETUP ═════════════════

class RunPlanSetup extends StatefulWidget {
  final RunPlanConfig? current;
  const RunPlanSetup({super.key, this.current});

  @override
  State<RunPlanSetup> createState() => _RunPlanSetupState();
}

class _RunPlanSetupState extends State<RunPlanSetup> {
  late RunGoal goal = widget.current?.goal ?? RunGoal.k10;
  late RunLevel level = widget.current?.level ?? RunLevel.intermediate;
  late int perWeek = widget.current?.perWeek ?? 4;
  late int weeks = widget.current?.weeks ?? suggestedWeeks(goal, level);
  bool nextWeek = false;

  Widget _chips<T>(BuildContext c, List<(T, String)> items, T value,
      ValueChanged<T> on) {
    final p = P.of(c);
    return Wrap(spacing: S.x2, runSpacing: S.x2, children: [
      for (final (v, label) in items)
        Pressable(
          semanticLabel: label,
          onTap: () => setState(() => on(v)),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
            decoration: BoxDecoration(
              color: v == value ? p.wash(C.green, strength: 1.5) : p.card2,
              borderRadius: R.rPill,
            ),
            child: Text(label,
                style: F.body.copyWith(
                    color: v == value ? p.on(C.green) : p.ink)),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final de = _de(c);
    final now = DateTime.now();
    final race = DateTime(now.year, now.month, now.day + (nextWeek ? 7 : 0) + weeks * 7);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(tr(c, 'Laufplan', 'Running plan')),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
              children: [
                Section(
                    tr(c, 'Ziel', 'Goal'),
                    _chips(c, [for (final g in RunGoal.values) (g, goalLabel(g, de))],
                        goal, (v) {
                      goal = v;
                      weeks = suggestedWeeks(goal, level);
                    })),
                Section(
                    tr(c, 'Erfahrung', 'Experience'),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _chips(
                          c,
                          [
                            (RunLevel.beginner, tr(c, 'Einsteiger', 'Beginner')),
                            (RunLevel.intermediate, tr(c, 'Fortgeschritten', 'Intermediate')),
                            (RunLevel.advanced, tr(c, 'Ambitioniert', 'Advanced')),
                          ],
                          level, (v) {
                        level = v;
                        weeks = suggestedWeeks(goal, level);
                      }),
                      const SizedBox(height: S.x2),
                      Text(
                          tr(c, 'Einsteiger: bis ~15 km pro Woche. Ambitioniert: '
                                  '40 km+ und schon Intervalle gelaufen.',
                              'Beginner: up to ~15 km a week. Advanced: 40 km+ '
                                  'and used to intervals.'),
                          style: F.cap.copyWith(color: p.ink3)),
                    ])),
                Section(
                    tr(c, 'Läufe pro Woche', 'Runs per week'),
                    _chips(c, [for (final n in [3, 4, 5, 6]) (n, '$n')], perWeek,
                        (v) => perWeek = v)),
                Section(
                  tr(c, 'Dauer', 'Length'),
                  Surface(
                    child: Row(children: [
                      Pressable(
                        semanticLabel: '−',
                        onTap: () => setState(() => weeks = (weeks - 1).clamp(4, 20)),
                        child: Icon(LucideIcons.minus, color: p.ink),
                      ),
                      Expanded(
                        child: Column(children: [
                          Text('$weeks ${tr(c, 'Wochen', 'weeks')}',
                              style: F.head.copyWith(color: p.ink)),
                          Text(
                              tr(c, 'Ziel etwa am ${race.day}.${race.month}.${race.year}',
                                  'Goal around ${race.month}/${race.day}/${race.year}'),
                              style: F.cap.copyWith(color: p.ink3)),
                        ]),
                      ),
                      Pressable(
                        semanticLabel: '+',
                        onTap: () => setState(() => weeks = (weeks + 1).clamp(4, 20)),
                        child: Icon(LucideIcons.plus, color: p.ink),
                      ),
                    ]),
                  ),
                ),
                Section(
                    tr(c, 'Start', 'Start'),
                    _chips(
                        c,
                        [
                          (false, tr(c, 'Diese Woche', 'This week')),
                          (true, tr(c, 'Nächste Woche', 'Next week')),
                        ],
                        nextWeek,
                        (v) => nextWeek = v)),
                const SizedBox(height: S.x4),
                BigButton(
                    widget.current == null
                        ? tr(c, 'Plan erstellen', 'Create plan')
                        : tr(c, 'Plan neu erstellen', 'Rebuild plan'),
                    icon: LucideIcons.sparkles, onTap: () {
                  final mon = mondayOf(DateTime.now());
                  RunCoachStore.save(RunPlanConfig(
                    goal: goal,
                    level: level,
                    weeks: weeks,
                    perWeek: perWeek,
                    start: nextWeek
                        ? DateTime(mon.year, mon.month, mon.day + 7)
                        : mon,
                    // Same plan rebuilt keeps its ticks; a new one starts clean.
                    done: widget.current != null &&
                            widget.current!.goal == goal &&
                            widget.current!.weeks == weeks &&
                            widget.current!.perWeek == perWeek
                        ? widget.current!.done
                        : const {},
                  ));
                  Navigator.of(c).maybePop();
                }),
                if (widget.current != null) ...[
                  const SizedBox(height: S.x3),
                  BigButton(tr(c, 'Plan löschen', 'Delete plan'),
                      icon: LucideIcons.trash2, color: C.red, soft: true,
                      onTap: () {
                    RunCoachStore.save(null);
                    Navigator.of(c).maybePop();
                  }),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
