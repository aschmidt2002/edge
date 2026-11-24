// FORTSCHRITT — training goals with a start and a target, and the six body
// areas as eight weeks of sets.
//
// Goals live in Prefs (`activity.goals`), progress is computed on read from
// `strength_set` plus the CTL and cardio minutes the Activity tab already has.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../state/prefs.dart';
import '../charts.dart';
import '../experimental/xp_features.dart' show XpScreen, loadMuscleLoad;
import '../grammar.dart';
import '../plus_text.dart';
import '../screens/journal_compose.dart' show OsTextField;
import '../theme.dart';
import 'catalogue.dart' show exerciseByKey;
import 'exercise_picker.dart';
import 'training_plans.dart' show epley;

// ── areas ────────────────────────────────────────────────────────────────────

const kAreas = ['chest', 'back', 'shoulders', 'arms', 'legs', 'core'];

/// Catalogue muscle (ours are lower-case, wger's are Latin-ish capitals) →
/// one of [kAreas], or null for muscles that fit none.
String? areaOf(String muscle) {
  final m = muscle.toLowerCase();
  if (m.contains('chest') || m.contains('pector')) return 'chest';
  if (m.contains('back') || m.contains('lat') || m.contains('trap') ||
      m.contains('rhomb')) {
    return 'back';
  }
  if (m.contains('shoulder') || m.contains('delt')) return 'shoulders';
  if (m.contains('bicep') || m.contains('tricep') || m.contains('brachi') ||
      m.contains('forearm')) {
    return 'arms';
  }
  if (m.contains('leg') || m.contains('quad') || m.contains('glute') ||
      m.contains('hamstring') || m.contains('calf') || m.contains('calves') ||
      m.contains('soleus') || m.contains('gastro')) {
    return 'legs';
  }
  if (m.contains('core') || m.contains('abs') || m.contains('abdomin') ||
      m.contains('oblique') || m.contains('obliquus')) {
    return 'core';
  }
  return null;
}

String areaLabel(BuildContext c, String a) => switch (a) {
      'chest' => tr(c, 'Brust', 'Chest'),
      'back' => tr(c, 'Rücken', 'Back'),
      'shoulders' => tr(c, 'Schultern', 'Shoulders'),
      'arms' => tr(c, 'Arme', 'Arms'),
      'legs' => tr(c, 'Beine', 'Legs'),
      _ => tr(c, 'Rumpf', 'Core'),
    };

// ── data ─────────────────────────────────────────────────────────────────────

const kProgressWeeks = 8;

class ProgressData {
  /// Sets per area per week, oldest first; the last slot is this week.
  final Map<String, List<int>> areaSets;

  /// Best estimated 1RM per exercise over everything read.
  final Map<String, double> bestE1rm;
  const ProgressData(this.areaSets, this.bestE1rm);
  static const empty = ProgressData({}, {});
}

/// strength_set rows → [ProgressData]. A set counts once for each area its
/// primary muscles reach; secondary muscles do not count.
ProgressData progressFrom(List<Map<String, Object?>> rows, DateTime now) {
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final sets = {for (final a in kAreas) a: List.filled(kProgressWeeks, 0)};
  final best = <String, double>{};
  for (final r in rows) {
    final key = '${r['exercise_key']}';
    final reps = (r['reps'] as num?)?.toInt() ?? 0;
    final kg = (r['load_kg'] as num?)?.toDouble();
    if (kg != null && kg > 0 && reps > 0) {
      final e = epley(kg, reps);
      if (e > (best[key] ?? 0)) best[key] = e;
    }
    final ts = (r['at_ts'] as num?)?.toInt();
    if (ts == null) continue;
    final at = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final day = DateTime(at.year, at.month, at.day);
    // Calendar days, not 7×24 h: a DST week is still one week.
    final weeksBack = (DateTime.utc(monday.year, monday.month, monday.day)
                    .difference(DateTime.utc(day.year, day.month, day.day))
                    .inDays +
                6) ~/
            7;
    final slot = kProgressWeeks - 1 - weeksBack;
    if (slot < 0 || slot >= kProgressWeeks) continue;
    final areas = {
      for (final m in exerciseByKey(key)?.primaryMuscles ?? const <String>[])
        ?areaOf(m),
    };
    for (final a in areas) {
      sets[a]![slot]++;
    }
  }
  return ProgressData(sets, best);
}

Future<ProgressData> loadProgress() async {
  try {
    final db = await LocalDb.instance;
    final since = DateTime.now().subtract(Motion.tick * 86400 * 365);
    final rows = await db.rawQuery(
        'SELECT exercise_key, reps, load_kg, at_ts FROM strength_set '
        'WHERE at_ts >= ?',
        [since.millisecondsSinceEpoch ~/ 1000]);
    return progressFrom(rows, DateTime.now());
  } catch (_) {
    return ProgressData.empty;
  }
}

// ── goals ────────────────────────────────────────────────────────────────────

enum GoalKind { lift, area, cardio, fitness }

class ActivityGoal {
  final GoalKind kind;

  /// Exercise key for [GoalKind.lift], area for [GoalKind.area], else ''.
  final String key;
  final double target;

  /// Where the goal started; progress is measured from here to [target].
  /// Weekly goals (area, cardio) start at 0 every week.
  final double start;
  const ActivityGoal(this.kind, this.key, this.target, {this.start = 0});

  Map<String, Object> toJson() =>
      {'kind': kind.name, 'key': key, 'target': target, 'start': start};

  static ActivityGoal? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind =
        GoalKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final target = (j['target'] as num?)?.toDouble();
    if (kind == null || target == null || target <= 0) return null;
    return ActivityGoal(kind, '${j['key'] ?? ''}', target,
        start: (j['start'] as num?)?.toDouble() ?? 0);
  }

  /// 0–1 from [start] to [target].
  double frac(double? current) {
    if (current == null) return 0;
    if (target <= start) return current >= target ? 1 : 0;
    return ((current - start) / (target - start)).clamp(0.0, 1.0);
  }
}

const _prefsKey = 'activity.goals';

List<ActivityGoal> readGoals() {
  try {
    final v = jsonDecode(Prefs.getString(_prefsKey, '[]'));
    return [
      if (v is List)
        for (final j in v) ?ActivityGoal.fromJson(j)
    ];
  } catch (_) {
    return const [];
  }
}

void writeGoals(List<ActivityGoal> goals) => Prefs.setString(
    _prefsKey, jsonEncode([for (final g in goals) g.toJson()]));

/// What the tab knows that the goals measure against.
class GoalInputs {
  final ProgressData data;
  final double? ctl;
  final int cardioMinWeek;
  const GoalInputs(this.data, {this.ctl, this.cardioMinWeek = 0});

  double? current(ActivityGoal g) => switch (g.kind) {
        GoalKind.lift => data.bestE1rm[g.key],
        GoalKind.area => (data.areaSets[g.key]?.last ?? 0).toDouble(),
        GoalKind.cardio => cardioMinWeek.toDouble(),
        GoalKind.fitness => ctl,
      };
}

String goalLabel(BuildContext c, ActivityGoal g) => switch (g.kind) {
      GoalKind.lift => exerciseByKey(g.key)
              ?.labelFor(Localizations.localeOf(c).languageCode) ??
          g.key,
      GoalKind.area => areaLabel(c, g.key),
      GoalKind.cardio => tr(c, 'Ausdauer', 'Cardio'),
      GoalKind.fitness => tr(c, 'Fitness', 'Fitness'),
    };

String _unit(BuildContext c, GoalKind k) => switch (k) {
      GoalKind.lift => 'kg',
      GoalKind.area => tr(c, 'Sätze/Woche', 'sets/week'),
      GoalKind.cardio => tr(c, 'min/Woche', 'min/week'),
      GoalKind.fitness => '',
    };

IconData _icon(GoalKind k) => switch (k) {
      GoalKind.lift => LucideIcons.dumbbell,
      GoalKind.area => LucideIcons.bicepsFlexed,
      GoalKind.cardio => LucideIcons.heartPulse,
      GoalKind.fitness => LucideIcons.trendingUp,
    };

String _n(double v) => v.round().toString();

// ── the section ──────────────────────────────────────────────────────────────

class ProgressSection extends StatefulWidget {
  final double? ctl;
  final int cardioMinWeek;
  const ProgressSection({super.key, this.ctl, this.cardioMinWeek = 0});

  @override
  State<ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<ProgressSection> {
  late Future<ProgressData> _data = loadProgress();
  List<ActivityGoal> _goals = readGoals();

  void _refresh() => setState(() {
        _goals = readGoals();
        _data = loadProgress();
      });

  Future<void> _edit(BuildContext c, GoalInputs inputs, [int? index]) async {
    await Navigator.of(c).push(MaterialPageRoute<void>(
        builder: (_) => GoalEditor(inputs: inputs, index: index)));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return FutureBuilder<ProgressData>(
      future: _data,
      builder: (c, snap) {
        final inputs = GoalInputs(snap.data ?? ProgressData.empty,
            ctl: widget.ctl, cardioMinWeek: widget.cardioMinWeek);
        return Section(
          tr(c, 'Fortschritt', 'Progress'),
          action: tr(c, '+ Ziel', '+ Goal'),
          onAction: () => _edit(c, inputs),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_goals.isNotEmpty) ...[
              Surface(
                child: Column(children: [
                  for (var i = 0; i < _goals.length; i++) ...[
                    if (i > 0) const SizedBox(height: S.x4),
                    Pressable(
                      onTap: () => _edit(c, inputs, i),
                      child: _goalRow(c, _goals[i], inputs),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: S.x3),
            ],
            Surface(
              onTap: () => Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => XpScreen(
                      tr(c, 'Muskuläre Belastung', 'Muscular load'),
                      loadMuscleLoad))),
              child: _areaGrid(c, p, inputs.data),
            ),
          ]),
        );
      },
    );
  }

  Widget _goalRow(BuildContext c, ActivityGoal g, GoalInputs inputs) {
    final cur = inputs.current(g);
    final unit = _unit(c, g.kind);
    return ProgressCard(
      goalLabel(c, g),
      cur == null ? '–' : _n(cur),
      '/ ${_n(g.target)} $unit'.trim(),
      g.frac(cur),
      g.frac(cur) >= 1 ? C.green : C.purple,
      icon: _icon(g.kind),
    );
  }

  /// Six areas, eight weekly bars each. The number is this week's sets.
  Widget _areaGrid(BuildContext c, P p, ProgressData d) {
    final top = [
      for (final a in kAreas) ...d.areaSets[a] ?? const <int>[]
    ].fold<int>(0, (m, v) => v > m ? v : m);
    final axis = AxisSpec(
        min: 0, max: top == 0 ? 1 : top.toDouble(), format: (v) => _n(v));
    Widget tile(String a) {
      final s = d.areaSets[a] ?? List.filled(kProgressWeeks, 0);
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(areaLabel(c, a),
                    style: F.cap.copyWith(color: p.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            Text('${s.last}',
                style: F.cap.copyWith(
                    color: p.ink, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: S.x1),
          SizedBox(
            height: 28,
            child: CustomPaint(
              size: Size.infinite,
              painter: Bars([for (final v in s) v.toDouble()], p.on(C.purple),
                  highlight: kProgressWeeks - 1, axis: axis),
            ),
          ),
        ]),
      );
    }

    return Column(children: [
      for (var row = 0; row < 2; row++) ...[
        if (row > 0) const SizedBox(height: S.x3),
        Row(children: [
          for (var i = row * 3; i < row * 3 + 3; i++) ...[
            if (i % 3 > 0) const SizedBox(width: S.x4),
            tile(kAreas[i]),
          ],
        ]),
      ],
    ]);
  }
}

// ── editor ───────────────────────────────────────────────────────────────────

class GoalEditor extends StatefulWidget {
  final GoalInputs inputs;

  /// Index into [readGoals] when editing; null adds a new goal.
  final int? index;
  const GoalEditor({super.key, required this.inputs, this.index});

  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  late final List<ActivityGoal> _all = [...readGoals()];
  late GoalKind _kind;
  late String _key;
  late final TextEditingController _target;

  ActivityGoal? get _existing =>
      widget.index == null || widget.index! >= _all.length
          ? null
          : _all[widget.index!];

  @override
  void initState() {
    super.initState();
    final g = _existing;
    _kind = g?.kind ?? GoalKind.lift;
    _key = g?.key ?? '';
    _target = TextEditingController(text: g == null ? '' : _n(g.target));
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _setKind(GoalKind k) => setState(() {
        _kind = k;
        _key = k == GoalKind.area ? 'chest' : '';
      });

  Future<void> _pickExercise() async {
    final k = await showExercisePicker(context, mode: ExercisePickMode.choose);
    if (k != null && mounted) setState(() => _key = k);
  }

  bool get _valid {
    final t = double.tryParse(_target.text.replaceAll(',', '.'));
    if (t == null || t <= 0) return false;
    return _kind != GoalKind.lift || _key.isNotEmpty;
  }

  void _save() {
    final t = double.parse(_target.text.replaceAll(',', '.'));
    final old = _existing;
    final weekly = _kind == GoalKind.area || _kind == GoalKind.cardio;
    final keepStart = old != null && old.kind == _kind && old.key == _key;
    final g = ActivityGoal(_kind, _key, t,
        start: weekly
            ? 0
            : keepStart
                ? old.start
                : (widget.inputs.current(ActivityGoal(_kind, _key, t)) ?? 0));
    if (old == null) {
      _all.add(g);
    } else {
      _all[widget.index!] = g;
    }
    writeGoals(_all);
    Navigator.of(context).pop();
  }

  void _delete() {
    _all.removeAt(widget.index!);
    writeGoals(_all);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final kinds = {
      GoalKind.lift: tr(c, 'Kraft', 'Strength'),
      GoalKind.area: tr(c, 'Muskelgruppe', 'Muscle group'),
      GoalKind.cardio: tr(c, 'Ausdauer', 'Cardio'),
      GoalKind.fitness: tr(c, 'Fitness', 'Fitness'),
    };
    Widget chip(String label, bool on, VoidCallback tap) => Pressable(
          onTap: tap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
            decoration: BoxDecoration(
                color: on ? p.fill(C.purple) : p.card2,
                borderRadius: R.rPill),
            child: Text(label,
                style: F.cap.copyWith(
                    color: on ? p.inkOnFill : p.ink,
                    fontWeight: FontWeight.w600)),
          ),
        );
    final cur = widget.inputs.current(ActivityGoal(_kind, _key, 1));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(
              _existing == null
                  ? tr(c, 'Neues Ziel', 'New goal')
                  : tr(c, 'Ziel bearbeiten', 'Edit goal'),
              trailing: _existing == null
                  ? null
                  : Pressable(
                      semanticLabel: tr(c, 'Ziel löschen', 'Delete goal'),
                      onTap: _delete,
                      child:
                          Icon(LucideIcons.trash2, size: 20, color: p.on(C.red)),
                    ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
              children: [
                Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                  for (final e in kinds.entries)
                    chip(e.value, _kind == e.key, () => _setKind(e.key)),
                ]),
                const SizedBox(height: S.x5),
                if (_kind == GoalKind.lift)
                  Surface(
                    onTap: _pickExercise,
                    child: Row(children: [
                      Icon(LucideIcons.dumbbell, size: 18, color: p.ink2),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: Text(
                            _key.isEmpty
                                ? tr(c, 'Übung wählen', 'Choose exercise')
                                : goalLabel(c, ActivityGoal(_kind, _key, 1)),
                            style: F.body.copyWith(color: p.ink)),
                      ),
                      Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
                    ]),
                  ),
                if (_kind == GoalKind.area)
                  Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                    for (final a in kAreas)
                      chip(areaLabel(c, a), _key == a,
                          () => setState(() => _key = a)),
                  ]),
                if (_kind == GoalKind.lift || _kind == GoalKind.area)
                  const SizedBox(height: S.x5),
                OsTextField(
                  controller: _target,
                  label: '${tr(c, 'Ziel', 'Target')} ${_unit(c, _kind)}'.trim(),
                  hint: cur == null ? '' : _n(cur),
                  keyboard:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                if (cur != null) ...[
                  const SizedBox(height: S.x2),
                  Text('${tr(c, 'Aktuell', 'Now')} ${_n(cur)} ${_unit(c, _kind)}'.trim(),
                      style: F.cap.copyWith(color: p.ink3)),
                ],
                const SizedBox(height: S.x6),
                ListenableBuilder(
                  listenable: _target,
                  builder: (c, _) => BigButton(
                    tr(c, 'Speichern', 'Save'),
                    icon: LucideIcons.check,
                    color: C.purple,
                    onTap: _valid ? _save : null,
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
