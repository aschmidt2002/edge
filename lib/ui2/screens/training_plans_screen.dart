// Edge+: training plans under Krafttraining — create, start, and see progress.
//
// Fork-only. Starting a plan opens the existing strength logger with the
// plan's exercises already lined up (it seeds each one from last time, so the
// user only corrects reps and weight). Progress is read from strength_set.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../activity/exercise_picker.dart';
import '../activity/live.dart';
import '../activity/training_plans.dart';
import '../ui2.dart';
import 'home_screen.dart' show unitsOf;
import 'journal_compose.dart' show OsTextField;
import 'workout_screen.dart' show activityHost, loadSetHistory;

String _exLabel(BuildContext c, String key) =>
    exerciseByKey(key)?.labelFor(Localizations.localeOf(c).languageCode) ??
    key.replaceAll('_', ' ');

String _num(BuildContext c, double v, {bool sign = false}) {
  final r = (v * 10).round() / 10;
  var s = r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
  if (Localizations.localeOf(c).languageCode == 'de') {
    s = s.replaceAll('.', ',');
  }
  return sign && r > 0 ? '+$s' : s;
}

String _kg(BuildContext c, double kg, {bool sign = false}) {
  final u = unitsOf(c);
  return '${_num(c, u?.weightValue(kg) ?? kg, sign: sign)} ${u?.weightUnit ?? 'kg'}';
}

/// Every session of every exercise in [plans], oldest first per exercise.
Future<Map<String, List<ExerciseSession>>> loadPlanProgress(
  Iterable<TrainingPlan> plans,
) async {
  final out = <String, List<ExerciseSession>>{};
  for (final key in {for (final p in plans) ...p.exercises}) {
    try {
      out[key] = sessionsFromRows(await LocalDb.recentSetsFor(key, limit: 400));
    } catch (_) {
      out[key] = const [];
    }
  }
  return out;
}

/// Open a weight-training session with [plan]'s exercises lined up.
Future<void> startTrainingPlan(
  BuildContext c,
  TrainingPlan plan,
  double? weightKg,
) async {
  final a = activityByName('weight_training');
  if (a == null || plan.exercises.isEmpty) return;
  final app = c.read<AppState>();
  final nav = Navigator.of(c);
  final messenger = ScaffoldMessenger.maybeOf(c);
  final busy = tr(
    c,
    'Es läuft schon eine Einheit. Beende sie zuerst.',
    'A session is already running. Finish it first.',
  );
  final history = await loadSetHistory();
  final host = activityHost(app, history: history);
  final ok = await host.onStart?.call(a) ?? false;
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text(busy)));
    return;
  }
  // The logger restores its exercise list from the draft, the same way it
  // does after being minimised.
  LiveDraft.begin(a, weightKg: weightKg)
    ..put('exercise_plan', List<String>.of(plan.exercises))
    ..put('exercise_index', 0)
    ..put('plan_id', plan.id);
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => liveFor(a, weightKg: weightKg, host: host),
    ),
  );
}

// ══════════════════ THE LIST ══════════════════

class TrainingPlansScreen extends StatefulWidget {
  final double? weightKg;
  const TrainingPlansScreen({super.key, this.weightKg});

  @override
  State<TrainingPlansScreen> createState() => _TrainingPlansScreenState();
}

class _TrainingPlansScreenState extends State<TrainingPlansScreen> {
  List<TrainingPlan> plans = TrainingPlanStore.load();
  Map<String, List<ExerciseSession>> progress = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ps = TrainingPlanStore.load();
    setState(() => plans = ps);
    final pr = await loadPlanProgress(ps);
    if (mounted) setState(() => progress = pr);
  }

  Future<void> _edit([TrainingPlan? plan]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TrainingPlanEditor(plan: plan)),
    );
    _reload();
  }

  Future<void> _start(TrainingPlan plan) async {
    await startTrainingPlan(context, plan, widget.weightKg);
    if (mounted) _reload();
  }

  void _addTemplates() {
    for (final (name, ex) in kPlanTemplates) {
      TrainingPlanStore.put(
        TrainingPlan('${TrainingPlanStore.newId()}_$name', name, ex),
      );
    }
    _reload();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                tr(c, 'Trainingspläne', 'Training plans'),
                trailing: Pressable(
                  semanticLabel: tr(c, 'Neuer Plan', 'New plan'),
                  onTap: () => _edit(),
                  child: Icon(LucideIcons.plus, size: 22, color: p.ink),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
                children: [
                  if (plans.isEmpty) ...[
                    StatusCard(
                      tr(c, 'Noch kein Plan', 'No plan yet'),
                      tr(
                        c,
                        'Lege einen Plan mit deinen Übungen an. Beim Start '
                            'gehst du sie der Reihe nach durch und trägst nur '
                            'Wiederholungen und Gewicht ein.',
                        'Create a plan with your exercises. When you start '
                            'it you go through them in order and only enter '
                            'reps and weight.',
                      ),
                      icon: LucideIcons.clipboardList,
                    ),
                    const SizedBox(height: S.x4),
                    BigButton(
                      tr(
                        c,
                        'Push / Pull / Legs anlegen',
                        'Add Push / Pull / Legs',
                      ),
                      icon: LucideIcons.sparkles,
                      color: C.purple,
                      soft: true,
                      onTap: _addTemplates,
                    ),
                    const SizedBox(height: S.x3),
                  ],
                  for (final plan in plans) ...[
                    _PlanCard(
                      plan: plan,
                      progress: progress,
                      onStart: () => _start(plan),
                      onEdit: () => _edit(plan),
                      onOpen: () => Navigator.of(c)
                          .push(
                            MaterialPageRoute<void>(
                              builder: (_) => TrainingPlanProgress(
                                plan: plan,
                                progress: progress,
                              ),
                            ),
                          )
                          .then((_) => _reload()),
                    ),
                    const SizedBox(height: S.x3),
                  ],
                  BigButton(
                    tr(c, 'Neuer Plan', 'New plan'),
                    icon: LucideIcons.plus,
                    color: C.purple,
                    soft: plans.isNotEmpty,
                    onTap: () => _edit(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final TrainingPlan plan;
  final Map<String, List<ExerciseSession>> progress;
  final VoidCallback onStart, onEdit, onOpen;

  const _PlanCard({
    required this.plan,
    required this.progress,
    required this.onStart,
    required this.onEdit,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final idx = planIndex({
      for (final k in plan.exercises) k: progress[k] ?? const [],
    });
    final pct = trendPct([for (final e in idx) e.$2]);
    return Surface(
      onTap: onOpen,
      semanticLabel: plan.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name, style: F.head.copyWith(color: p.ink)),
              ),
              Pressable(
                semanticLabel: tr(c, 'Plan bearbeiten', 'Edit plan'),
                onTap: onEdit,
                child: Icon(LucideIcons.pencil, size: 18, color: p.ink3),
              ),
            ],
          ),
          const SizedBox(height: S.x1),
          Text(
            [for (final k in plan.exercises) _exLabel(c, k)].join(' · '),
            style: F.cap.copyWith(color: p.ink3),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (idx.length >= 2) ...[
            const SizedBox(height: S.x3),
            SizedBox(
              height: 44,
              child: CustomPaint(
                size: Size.infinite,
                painter: LineChart(
                  [for (final e in idx) e.$2],
                  p.on(C.purple),
                  dots: true,
                  dotInk: p.card,
                ),
              ),
            ),
          ],
          if (pct != null) ...[const SizedBox(height: S.x2), _TrendLabel(pct)],
          const SizedBox(height: S.x3),
          BigButton(
            tr(c, 'Plan starten', 'Start plan'),
            icon: LucideIcons.play,
            color: C.purple,
            onTap: onStart,
          ),
        ],
      ),
    );
  }
}

/// "Rising +2.1 % per session", coloured by direction.
class _TrendLabel extends StatelessWidget {
  final double pct;
  const _TrendLabel(this.pct);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final (icon, color, word) = switch (tendencyOf(pct)!) {
      Tendency.up => (
        LucideIcons.trendingUp,
        C.green,
        tr(c, 'Steigend', 'Rising'),
      ),
      Tendency.down => (
        LucideIcons.trendingDown,
        C.red,
        tr(c, 'Fallend', 'Falling'),
      ),
      Tendency.flat => (
        LucideIcons.moveRight,
        C.blue,
        tr(c, 'Stabil', 'Steady'),
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: p.on(color)),
        const SizedBox(width: S.x1),
        Flexible(
          child: Text(
            '$word ${_num(c, pct, sign: true)} % ${tr(c, 'pro Einheit', 'per session')}',
            style: F.cap.copyWith(
              color: p.on(color),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════ THE EDITOR ══════════════════

class TrainingPlanEditor extends StatefulWidget {
  final TrainingPlan? plan;
  const TrainingPlanEditor({super.key, this.plan});

  @override
  State<TrainingPlanEditor> createState() => _TrainingPlanEditorState();
}

class _TrainingPlanEditorState extends State<TrainingPlanEditor> {
  late final name = TextEditingController(text: widget.plan?.name ?? '');
  late final exercises = List<String>.of(widget.plan?.exercises ?? const []);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final picked = await showExercisePicker(
      context,
      mode: ExercisePickMode.add,
      selectedKeys: exercises.toSet(),
    );
    if (picked == null || !mounted || exercises.contains(picked)) return;
    setState(() => exercises.add(picked));
  }

  void _move(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= exercises.length) return;
    setState(() => exercises.insert(j, exercises.removeAt(i)));
  }

  bool get _valid => name.text.trim().isNotEmpty && exercises.isNotEmpty;

  void _save() {
    if (!_valid) return;
    TrainingPlanStore.put(
      (widget.plan ?? TrainingPlan(TrainingPlanStore.newId(), '', const []))
          .copyWith(name: name.text.trim(), exercises: exercises),
    );
    Navigator.of(context).pop();
  }

  void _delete() {
    final id = widget.plan?.id;
    if (id != null) TrainingPlanStore.remove(id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                widget.plan == null
                    ? tr(c, 'Neuer Plan', 'New plan')
                    : tr(c, 'Plan bearbeiten', 'Edit plan'),
                trailing: widget.plan == null
                    ? null
                    : Pressable(
                        semanticLabel: tr(c, 'Plan löschen', 'Delete plan'),
                        onTap: _delete,
                        child: Icon(
                          LucideIcons.trash2,
                          size: 20,
                          color: p.on(C.red),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
                children: [
                  OsTextField(
                    controller: name,
                    label: tr(c, 'Name', 'Name'),
                    hint: tr(c, 'z. B. Push', 'e.g. Push'),
                  ),
                  const SizedBox(height: S.x5),
                  Text(
                    tr(c, 'ÜBUNGEN', 'EXERCISES'),
                    style: F.over.copyWith(color: p.ink3),
                  ),
                  const SizedBox(height: S.x2),
                  if (exercises.isNotEmpty)
                    Surface(
                      pad: const EdgeInsets.symmetric(horizontal: S.x3),
                      child: Column(
                        children: [
                          for (var i = 0; i < exercises.length; i++) ...[
                            Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${i + 1}',
                                    style: F.cap.copyWith(color: p.ink3),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _exLabel(c, exercises[i]),
                                    style: F.body.copyWith(color: p.ink),
                                  ),
                                ),
                                Pressable(
                                  semanticLabel: tr(c, 'Nach oben', 'Move up'),
                                  onTap: i == 0 ? null : () => _move(i, -1),
                                  child: Icon(
                                    LucideIcons.chevronUp,
                                    size: 18,
                                    color: i == 0 ? p.line : p.ink3,
                                  ),
                                ),
                                Pressable(
                                  semanticLabel: tr(
                                    c,
                                    'Nach unten',
                                    'Move down',
                                  ),
                                  onTap: i == exercises.length - 1
                                      ? null
                                      : () => _move(i, 1),
                                  child: Icon(
                                    LucideIcons.chevronDown,
                                    size: 18,
                                    color: i == exercises.length - 1
                                        ? p.line
                                        : p.ink3,
                                  ),
                                ),
                                Pressable(
                                  semanticLabel: tr(c, 'Entfernen', 'Remove'),
                                  onTap: () =>
                                      setState(() => exercises.removeAt(i)),
                                  child: Icon(
                                    LucideIcons.x,
                                    size: 18,
                                    color: p.ink3,
                                  ),
                                ),
                              ],
                            ),
                            if (i < exercises.length - 1)
                              Divider(color: p.line, height: 1),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: S.x3),
                  BigButton(
                    tr(c, 'Übung hinzufügen', 'Add exercise'),
                    icon: LucideIcons.plus,
                    color: C.purple,
                    soft: true,
                    onTap: _add,
                  ),
                  const SizedBox(height: S.x5),
                  ListenableBuilder(
                    listenable: name,
                    builder: (_, _) => BigButton(
                      tr(c, 'Speichern', 'Save'),
                      icon: LucideIcons.check,
                      color: C.purple,
                      onTap: _valid ? _save : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════ PROGRESS ══════════════════

class TrainingPlanProgress extends StatelessWidget {
  final TrainingPlan plan;
  final Map<String, List<ExerciseSession>> progress;

  const TrainingPlanProgress({
    super.key,
    required this.plan,
    required this.progress,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final idx = planIndex({
      for (final k in plan.exercises) k: progress[k] ?? const [],
    });
    final pct = trendPct([for (final e in idx) e.$2]);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(plan.name, sub: tr(c, 'Fortschritt', 'Progress')),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
                children: [
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(c, 'GESAMTER PLAN', 'WHOLE PLAN'),
                          style: F.over.copyWith(color: p.ink3),
                        ),
                        const SizedBox(height: S.x1),
                        Text(
                          tr(
                            c,
                            'Kraft im Schnitt aller Übungen, 100 = erste Einheit',
                            'Strength averaged over all exercises, 100 = first session',
                          ),
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                        const SizedBox(height: S.x3),
                        _Spark([for (final e in idx) e.$2], height: 90),
                        if (pct != null) ...[
                          const SizedBox(height: S.x2),
                          _TrendLabel(pct),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x5),
                  Text(
                    tr(c, 'ÜBUNGEN', 'EXERCISES'),
                    style: F.over.copyWith(color: p.ink3),
                  ),
                  const SizedBox(height: S.x2),
                  for (final k in plan.exercises) ...[
                    _ExerciseCard(k, progress[k] ?? const []),
                    const SizedBox(height: S.x3),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  final List<double> values;
  final double height;
  const _Spark(this.values, {this.height = 56});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    if (values.length < 2) {
      return Text(
        tr(
          c,
          'Der Verlauf erscheint ab der zweiten Einheit.',
          'The trend appears after the second session.',
        ),
        style: F.cap.copyWith(color: p.ink3),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(values, p.on(C.purple), dots: true, dotInk: p.card),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final String exKey;
  final List<ExerciseSession> sessions;
  const _ExerciseCard(this.exKey, this.sessions);

  String _set(BuildContext c, ExerciseSession s) => s.topKg == null
      ? '${s.topReps} ${tr(c, 'Wdh.', 'reps')} · ${tr(c, 'Körpergewicht', 'bodyweight')}'
      : '${_kg(c, s.topKg!)} × ${s.topReps}';

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final last = sessions.isEmpty ? null : sessions.last;
    final d = lastDelta(sessions);
    final pct = trendPct([for (final s in sessions) s.score]);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_exLabel(c, exKey), style: F.head.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          if (last == null)
            Text(
              tr(c, 'Noch nicht trainiert.', 'Not trained yet.'),
              style: F.cap.copyWith(color: p.ink3),
            )
          else ...[
            Text(
              '${tr(c, 'Zuletzt', 'Last')}: ${_set(c, last)} · '
              '${last.sets} ${tr(c, 'Sätze', 'sets')}',
              style: F.body.copyWith(color: p.ink2),
            ),
            if (d != null) ...[
              const SizedBox(height: S.x2),
              Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                children: [
                  if (d.kg != null)
                    _DeltaChip(d.kg!, _kg(c, d.kg!, sign: true)),
                  _DeltaChip(
                    d.reps.toDouble(),
                    '${d.reps > 0 ? '+' : ''}${d.reps} ${tr(c, 'Wdh.', 'reps')}',
                  ),
                  if (d.volumeKg != null)
                    _DeltaChip(
                      d.volumeKg!,
                      '${_kg(c, d.volumeKg!, sign: true)} ${tr(c, 'Volumen', 'volume')}',
                    ),
                ],
              ),
              const SizedBox(height: S.x1),
              Text(
                tr(c, 'gegenüber der Einheit davor', 'vs the session before'),
                style: F.over.copyWith(color: p.ink3),
              ),
            ],
            const SizedBox(height: S.x3),
            _Spark([for (final s in sessions) s.score]),
            if (pct != null) ...[
              const SizedBox(height: S.x2),
              _TrendLabel(pct),
            ],
          ],
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final double v;
  final String text;
  const _DeltaChip(this.v, this.text);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final color = v > 0 ? C.green : (v < 0 ? C.red : C.blue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
      decoration: BoxDecoration(color: p.wash(color), borderRadius: R.rSm),
      child: Text(
        text,
        style: F.cap.copyWith(color: p.on(color), fontWeight: FontWeight.w600),
      ),
    );
  }
}
