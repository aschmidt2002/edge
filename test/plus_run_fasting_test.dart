import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/run_insights.dart';
import 'package:openstrap_edge/ui2/screens/fasting.dart';

void main() {
  test('recovery hours grow with strain', () {
    expect(recoveryHours(0), 0);
    expect(recoveryHours(10), 16);
    expect(recoveryHours(21), 72);
    expect(recoveryHours(30), 72);
  });

  test('recovery left takes the latest session and never goes negative', () {
    final now = DateTime(2026, 11, 24, 12);
    final nowS = now.millisecondsSinceEpoch ~/ 1000;
    expect(recoveryLeft(const [], now), 0);
    expect(
        recoveryLeft([
          {'end_ts': nowS - 3600 * 10, 'strain': 10.0}, // 16 h → 6 h left
          {'end_ts': nowS - 3600 * 100, 'strain': 21.0}, // long done
        ], now),
        6);
  });

  test('race predictions match Daniels tables for VDOT 50', () {
    // Daniels: VDOT 50 → 5 km 19:57, 10 km 41:21, half 1:31:35.
    expect(predictRaceSeconds(50, 5000)!, closeTo(19 * 60 + 57, 10));
    expect(predictRaceSeconds(50, 10000)!, closeTo(41 * 60 + 21, 15));
    expect(predictRaceSeconds(50, 21097.5)!, closeTo(91 * 60 + 35, 30));
    expect(predictRaceSeconds(10, 5000), isNull);
    expect(raceClock(5495), '1:31:35');
    expect(raceClock(1197), '19:57');
  });

  test('recent VO2max is the median of the newest five', () {
    final rows = [
      for (var i = 0; i < 7; i++)
        {'start_ts': i, 'vo2max_estimate': 40.0 + i},
    ];
    expect(recentVo2max(rows), 44); // newest five: 42..46
    expect(recentVo2max(const []), isNull);
  });

  test('fasting goal cycles and clock formats', () {
    expect(nextFastGoal(16), 18);
    expect(nextFastGoal(20), 12);
    expect(fastClock(14 * 3600 + 5 * 60), '14:05');
    expect(fastClock(-3), '0:00');
  });
}
