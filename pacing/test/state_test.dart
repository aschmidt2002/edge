import 'package:akku/core/models.dart';
import 'package:akku/data/store.dart';
import 'package:akku/main.dart';
import 'package:akku/state/pacing_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSaveStore extends PacingStore {
  _NoSaveStore(this.d);
  final PacingData d;
  @override
  Future<PacingData> load() async => d;
  @override
  Future<void> save(PacingData d) async {}
}

void main() {
  test('heart rate over the ceiling drains the battery, rest does not', () async {
    var now = DateTime(2026, 3, 20, 10);
    final data = PacingData()..settings.restingHr = 60;
    final st = PacingState(store: _NoSaveStore(data), clock: () => now)
      // load() also wires BLE; skip it and drive the state directly.
      ..data = data;
    data.settings.vibrationAlerts = false;
    expect(st.batteryShare, 1.0);
    for (var i = 0; i < 120; i++) {
      st.onHeartRate(62);
      now = now.add(const Duration(seconds: 1));
    }
    expect(st.today.used, 0);
    for (var i = 0; i < 300; i++) {
      st.onHeartRate(90);
      now = now.add(const Duration(seconds: 1));
    }
    expect(st.today.used, greaterThan(5));
    expect(st.today.minutesOverThreshold, greaterThanOrEqualTo(4));
    expect(st.batteryShare, lessThan(1.0));
  });

  test('a bad check-in lowers today’s start but keeps what was used', () {
    final now = DateTime(2026, 3, 20, 10);
    final st = PacingState(store: _NoSaveStore(PacingData()), clock: () => now);
    st.logActivity(ActivityLog(
        id: 'x',
        start: now,
        minutes: 30,
        kind: EffortKind.cognitive,
        intensity: 2,
        label: 'Telefonat'));
    final used = st.today.used;
    st.saveCheckIn(CheckIn(day: st.todayKey, feeling: 0));
    expect(st.today.used, used);
    expect(st.today.startCharge, lessThan(50));
  });

  testWidgets('home screen renders after onboarding', (t) async {
    final data = PacingData()..settings.onboarded = true;
    final st = PacingState(store: _NoSaveStore(data))..data = data;
    await t.pumpWidget(AkkuApp(state: st));
    expect(find.text('Heute'), findsWidgets);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('Wie geht es dir heute?'), findsOneWidget);
  });

  testWidgets('onboarding shows first', (t) async {
    // iPhone-sized screen.
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final st = PacingState(store: _NoSaveStore(PacingData()));
    await t.pumpWidget(AkkuApp(state: st));
    expect(find.text('Akku'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Los geht’s'), 200);
    await t.tap(find.text('Verstanden'));
    await t.pump();
    await t.tap(find.text('Los geht’s'));
    await t.pumpAndSettle();
    expect(st.settings.onboarded, isTrue);
    expect(find.text('Wie geht es dir heute?'), findsOneWidget);
  });

  testWidgets('check-in with one tap', (t) async {
    final data = PacingData()..settings.onboarded = true;
    final st = PacingState(store: _NoSaveStore(data))..data = data;
    await t.pumpWidget(AkkuApp(state: st));
    await t.tap(find.text('Wie geht es dir heute?'));
    await t.pumpAndSettle();
    await t.tap(find.text('1').first);
    await t.pump();
    await t.tap(find.text('Fertig'));
    await t.pumpAndSettle();
    expect(st.todayCheckIn?.feeling, 1);
    expect(find.text('Check-in erledigt'), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('every tab lays out on a small phone without overflow', (t) async {
    t.view.physicalSize = const Size(720, 1280); // 360 x 640 logical
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final data = PacingData()
      ..settings.onboarded = true
      ..settings.restingHr = 60
      ..checkIns.add(CheckIn(day: dayKey(DateTime.now()), feeling: 1, crash: true));
    final st = PacingState(store: _NoSaveStore(data))..data = data;
    await t.pumpWidget(AkkuApp(state: st));
    for (final tab in ['Verlauf', 'Medis', 'Einstellungen', 'Heute']) {
      await t.tap(find.text(tab).last);
      await t.pumpAndSettle();
    }
    final onb = PacingState(store: _NoSaveStore(PacingData()));
    await t.pumpWidget(AkkuApp(state: onb));
    await t.pumpAndSettle();
  });
}
