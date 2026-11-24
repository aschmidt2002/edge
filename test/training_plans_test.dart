// Edge+: training plans — storage, per-exercise progress math, and the
// screens that create and show them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/training_plans.dart';
import 'package:openstrap_edge/ui2/screens/training_plans_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Map<String, Object?> _row(String session, int at, int reps, double? kg) => {
  'session_id': session,
  'at_ts': at,
  'reps': reps,
  'load_kg': kg,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    // Prefs keeps its first instance across tests; start every test empty.
    for (final p in TrainingPlanStore.load()) {
      TrainingPlanStore.remove(p.id);
    }
  });

  test('plans round-trip through Prefs, replace by id, and delete', () {
    expect(TrainingPlanStore.load(), isEmpty);
    TrainingPlanStore.put(const TrainingPlan('a', 'Push', ['bench_press']));
    TrainingPlanStore.put(const TrainingPlan('b', 'Pull', ['pull_up']));
    TrainingPlanStore.put(
      const TrainingPlan('a', 'Push A', ['bench_press', 'overhead_press']),
    );
    final plans = TrainingPlanStore.load();
    expect(plans.map((p) => p.name), ['Push A', 'Pull']);
    expect(plans.first.exercises, ['bench_press', 'overhead_press']);
    TrainingPlanStore.remove('a');
    expect(TrainingPlanStore.load().map((p) => p.id), ['b']);
  });

  test('rows become one entry per session, oldest first', () {
    final s = sessionsFromRows([
      _row('s2', 2000, 8, 82.5),
      _row('s1', 1000, 8, 80),
      _row('s1', 1100, 10, 80),
      _row('s1', 1200, 6, 70),
      _row('s2', 2100, 6, 82.5),
    ]);
    expect(s.map((e) => e.sessionId), ['s1', 's2']);
    expect(s.first.topKg, 80);
    expect(s.first.topReps, 10);
    expect(s.first.sets, 3);
    expect(s.first.volumeKg, 80 * 8 + 80 * 10 + 70 * 6);
    expect(s.first.score, closeTo(epley(80, 10), 1e-9));

    final d = lastDelta(s)!;
    expect(d.kg, 2.5);
    expect(d.reps, -2);
  });

  test('a bodyweight lift is scored by reps, with no load delta', () {
    final s = sessionsFromRows([_row('a', 1, 8, null), _row('b', 2, 11, null)]);
    expect(s.every((e) => e.bodyweight), isTrue);
    expect([for (final e in s) e.score], [8, 11]);
    final d = lastDelta(s)!;
    expect(d.kg, isNull);
    expect(d.reps, 3);
  });

  test('trend: rising, falling, steady, and not enough data', () {
    expect(trendPct([100]), isNull);
    expect(tendencyOf(trendPct([100, 102, 104, 106])), Tendency.up);
    expect(tendencyOf(trendPct([106, 104, 102, 100])), Tendency.down);
    expect(tendencyOf(trendPct([100, 100.5, 99.8, 100.2])), Tendency.flat);
    // Only the recent window counts: an old slump does not drag a new climb.
    expect(
      tendencyOf(
        trendPct([200, 50, 50, 100, 102, 104, 106, 108, 110, 112, 114]),
      ),
      Tendency.up,
    );
  });

  test('the plan index starts every exercise at 100', () {
    final idx = planIndex({
      'bench_press': sessionsFromRows([
        _row('s1', 1000, 5, 100),
        _row('s2', 2000, 5, 110),
      ]),
      'pull_up': sessionsFromRows([
        _row('s1', 1000, 10, null),
        _row('s2', 2000, 10, null),
      ]),
    });
    expect(idx.length, 2);
    expect(idx.first.$2, closeTo(100, 1e-9));
    expect(idx.last.$2, closeTo((110 + 100) / 2, 1e-9));
  });

  testWidgets('templates create Push, Pull and Legs; a plan opens its editor', (
    t,
  ) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final app = AppState();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const TrainingPlansScreen(),
        ),
      ),
    );
    await t.pump();
    expect(find.text('No plan yet'), findsOneWidget);
    await t.tap(find.text('Add Push / Pull / Legs'));
    await t.pump();
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Pull'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
    expect(find.text('Start plan'), findsNWidgets(3));
    expect(TrainingPlanStore.load(), hasLength(3));

    await t.tap(find.bySemanticsLabel('Edit plan').first);
    await t.pumpAndSettle();
    expect(find.text('Edit plan'), findsWidgets);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('a started plan walks to the next exercise after a set', (
    t,
  ) async {
    t.view.physicalSize = const Size(700 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    addTearDown(LiveDraft.clear);
    final a = activityByName('weight_training')!;
    LiveDraft.begin(a)
      ..put('exercise_plan', ['bench_press', 'overhead_press'])
      ..put('exercise_index', 0);
    await t.pumpWidget(
      MaterialApp(theme: buildTheme(Brightness.light), home: liveFor(a)),
    );
    await t.pump();
    expect(find.text('EXERCISE 1 OF 2'), findsOneWidget);
    expect(find.textContaining('Next: '), findsNothing);
    await t.tap(find.text('Log set'));
    await t.pump();
    final next = find.textContaining('Next: ');
    expect(next, findsOneWidget);
    await t.ensureVisible(next);
    await t.tap(next);
    await t.pump();
    expect(find.text('EXERCISE 2 OF 2'), findsOneWidget);
    expect(find.textContaining('Next: '), findsNothing);
    expect(t.takeException(), isNull);
  });
}
