// Edge+: the running screens render and the live screen shows the coach step.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/live.dart';
import 'package:openstrap_edge/ui2/activity/run_coach.dart';
import 'package:openstrap_edge/ui2/activity/run_live_panel.dart';
import 'package:openstrap_edge/ui2/activity/run_stats.dart';
import 'package:openstrap_edge/ui2/screens/route_planner_screen.dart';
import 'package:openstrap_edge/ui2/screens/run_coach_screen.dart';
import 'package:openstrap_edge/ui2/screens/run_stats_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    RunCoachStore.save(null);
  });

  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ChangeNotifierProvider<AppState>.value(
          value: AppState(), child: child),
    ));
    await t.pump();
  }

  testWidgets('coach: empty state, setup creates a plan, week list shows', (t) async {
    await pump(t, const RunCoachScreen());
    expect(find.text('No running plan yet'), findsOneWidget);
    await t.tap(find.text('Create plan'));
    await t.pumpAndSettle();
    await t.tap(find.text('Half marathon'));
    await t.pump();
    final create = find.text('Create plan');
    await t.ensureVisible(create);
    await t.tap(create);
    await t.pumpAndSettle();
    expect(RunCoachStore.load()!.goal, RunGoal.half);
    expect(find.text('Half marathon'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('German at large text: plan, detail and live guide do not overflow',
      (t) async {
    RunCoachStore.save(RunPlanConfig(
        goal: RunGoal.marathon,
        level: RunLevel.advanced,
        weeks: 16,
        perWeek: 6,
        start: mondayOf(DateTime.now())));
    t.view.physicalSize = const Size(360 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    for (final child in <Widget>[
      const RunCoachScreen(),
      RunWorkoutDetail(workout: buildWorkout(RunKind.longFinish, RunGoal.marathon)),
      const RunPlanSetup(),
      RunStatsScreen(runs: [
        for (var i = 0; i < 5; i++)
          RunRecord(
              id: '$i',
              start: DateTime.now().subtract(Duration(days: 2 + i * 6)),
              meters: 10000,
              sec: 3300,
              vo2max: 50.0 + i,
              splits: [for (var k = 0; k < 10; k++) RunSplit(1000, 330, avgHr: 150.0 - i, elev: 4)]),
      ]),
      const RoutePlannerScreen(),
    ]) {
      await t.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ChangeNotifierProvider<AppState>.value(
              value: AppState(), child: child),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull, reason: '$child');
    }
  });

  testWidgets('workout detail lists the steps', (t) async {
    await pump(t, RunWorkoutDetail(workout: buildWorkout(RunKind.vo2, RunGoal.k5)));
    expect(find.text('VO2max intervals'), findsOneWidget);
    expect(find.text('Warm up'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('stats render from runs', (t) async {
    final now = DateTime.now();
    final runs = [
      for (var i = 0; i < 6; i++)
        RunRecord(
          id: '$i',
          start: now.subtract(Duration(days: 3 + i * 5)),
          meters: 5000,
          sec: 1650 - i * 10,
          splits: [for (var k = 0; k < 5; k++) RunSplit(1000, 330 - i * 2, avgHr: 150.0 + i)],
        ),
    ];
    await pump(t, RunStatsScreen(runs: runs));
    expect(find.text('Distance per week'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Best efforts'), 300,
        scrollable: find
            .ancestor(
                of: find.text('Distance per week'),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('Best efforts'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('planner asks before using the network', (t) async {
    await pump(t, const RoutePlannerScreen());
    expect(find.text('The map needs the internet'), findsOneWidget);
    expect(find.text('Turn on the map'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a guided run shows the current step on the live screen', (t) async {
    addTearDown(LiveDraft.clear);
    final a = activityByName('running')!;
    LiveDraft.begin(a).put(
        kRunGuideKey, buildWorkout(RunKind.threshold, RunGoal.k10).toJson());
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: liveFor(a,
            host: ActivityHost(
                feed: () => const LiveFeed(zone: 2, distanceKm: 0.4)))));
    await t.pump();
    expect(find.textContaining('Warm up'), findsWidgets);
    expect(find.textContaining('Target: Zone 1–2'), findsOneWidget);
    expect(find.text('Band buzzes every km'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
