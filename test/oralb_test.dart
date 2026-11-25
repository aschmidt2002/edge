// Edge+: the Oral-B advert decode, the session tracker and the page stats.
// Vectors are real adverts from oralb-ble's own tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/oralb/oralb.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/dental_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

OralBAdvert _ad(int state, int seconds, {bool red = false}) => OralBAdvert(
  modelId: 49,
  state: state,
  highPressure: red,
  seconds: seconds,
  mode: 0,
  sector: 1,
);

void main() {
  test('decodes an iO Series 9 advert', () {
    final a = parseOralB([0x06, 0x31, 0x16, 0x08, 0x72, 0, 0, 3, 2, 0, 4])!;
    expect(oralBModelName(a.modelId), 'Oral-B iO');
    expect(a.state, 8);
    expect(a.brushing, isFalse);
    expect(a.highPressure, isFalse);
    expect((a.mode, a.sector, a.sectors), (3, 2, 4));
  });

  test('decodes a running advert with high pressure and the last sector', () {
    final a = parseOralB([0x03, 0x22, 0x0c, 0x03, 0xc0, 0x01, 0x30, 0x07, 0x04, 0x3c, 0x04])!;
    expect(a.brushing, isTrue);
    expect(a.highPressure, isTrue);
    expect(a.seconds, 108);
    expect(a.sector, 4);
    // A button press outranks the pressure bit.
    expect(parseOralB([2, 1, 8, 3, 0x86, 0, 0, 1, 1])!.highPressure, isFalse);
    expect(parseOralB([1, 2, 3]), isNull);
  });

  test('tracker: pauses stay one session, idle closes it, warnings count edges', () {
    final t = BrushTracker();
    const t0 = 1700000000000;
    expect(t.feed(_ad(3, 5), t0), isNull);
    t.feed(_ad(3, 30, red: true), t0 + 25000);
    t.feed(_ad(3, 32, red: true), t0 + 27000);
    t.feed(_ad(3, 40), t0 + 35000);
    t.feed(_ad(2, 40), t0 + 40000); // paused
    t.feed(_ad(3, 60, red: true), t0 + 60000); // resumed
    t.feed(_ad(3, 128), t0 + 128000);
    t.feed(_ad(10, 130), t0 + 135000); // stopped, final time shown
    expect(t.open, isTrue);
    final s = t.flush(t0 + 170000)!;
    expect(s.seconds, 130);
    expect(s.pressureWarnings, 2);
    expect(s.startSec, t0 ~/ 1000 - 5);
    expect(t.open, isFalse);
  });

  test('tracker: timer seconds land on the zone they ran in, and survive json', () {
    final t = BrushTracker();
    OralBAdvert z(int sec, int zone) => OralBAdvert(
        modelId: 49, state: 3, highPressure: false, seconds: sec, mode: 0, sector: zone);
    t.feed(z(0, 1), 0);
    for (var s = 1; s <= 40; s++) {
      t.feed(z(s, s <= 30 ? 1 : 2), s * 1000);
    }
    t.feed(z(55, 2), 55000); // a 15 s gap is not guessed onto a zone
    final s = t.flush(120000)!;
    expect(s.zones, {1: 30, 2: 10});
    expect(BrushSession.fromJson(s.toJson())!.zones, {1: 30, 2: 10});
    final tr = zoneTrend([
      s,
      BrushSession(startSec: s.startSec + 3600, seconds: 120, zones: const {1: 30, 2: 30, 3: 30, 4: 30}),
    ], s.start)!;
    expect(tr.zones, 4);
    expect(tr.avg, {1: 30.0, 2: 20.0, 3: 15.0, 4: 15.0});
  });

  test('tracker: a timer that restarts is a new session; taps are dropped', () {
    final t = BrushTracker();
    t.feed(_ad(3, 90), 0);
    final first = t.feed(_ad(3, 3), 10000);
    expect(first!.seconds, 90);
    expect(t.flush(60000), isNull); // 3 s is a tap, not a clean
  });

  test('stats: twice a day, streak, average', () {
    final now = DateTime(2026, 11, 24, 12);
    BrushSession at(int daysBack, int hour, int sec, {int p = 0}) => BrushSession(
      startSec: DateTime(2026, 11, 24 - daysBack, hour).millisecondsSinceEpoch ~/ 1000,
      seconds: sec,
      pressureWarnings: p,
    );
    final st = BrushStats([
      at(0, 7, 120),
      at(1, 7, 130), at(1, 22, 110, p: 1),
      at(2, 7, 120), at(2, 22, 120),
      at(4, 7, 120), at(4, 22, 120),
    ], now);
    expect(st.todayCount, 1);
    expect(st.streak, 2); // yesterday and the day before; day 3 is missing
    expect(st.twiceDays, 3);
    expect(st.weekSessions, 7);
    expect(st.pressureSessions, 1);
    expect(st.avgSeconds, 120);
    expect(brushClock(125), '2:05');
  });

  testWidgets('the page draws the stats and stays on screen at large text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.reload();
    final now = DateTime.now();
    OralBStore.pair('AA:BB', 'Oral-B iO');
    for (final (h, sec, p) in [(7, 125, 0), (8, 95, 2)]) {
      OralBStore.add(BrushSession(
        startSec: DateTime(now.year, now.month, now.day - 1, h).millisecondsSinceEpoch ~/ 1000,
        seconds: sec,
        pressureWarnings: p,
      ));
    }
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: DentalScreen(),
      ),
    ));
    expect(find.text('Oral care'), findsOneWidget);
    expect(find.text('1/7'), findsOneWidget); // twice a day
    expect(find.text('Too hard in 1 of 2'), findsOneWidget);
    expect(find.text('2:05'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
