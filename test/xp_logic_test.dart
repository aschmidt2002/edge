import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/experimental/xp_core.dart';
import 'package:openstrap_edge/ui2/experimental/xp_features.dart';

void main() {
  test('stress is 0 at the reference and rises with lower HRV and higher HR', () {
    expect(stressScore(hr: 55, rmssd: 60, refHr: 55, refRmssd: 60), 0);
    final mid = stressScore(hr: 70, rmssd: 40, refHr: 55, refRmssd: 60);
    final high = stressScore(hr: 90, rmssd: 15, refHr: 55, refRmssd: 60);
    expect(mid, greaterThan(0));
    expect(high, greaterThan(mid));
    expect(high, lessThanOrEqualTo(3));
  });

  test('bio age is younger for a fit profile and older for an unfit one', () {
    final fit = bioAge(age: 30, female: false, vo2: 55, rhr: 48, hrv: 80, sleepH: 7.5, steps: 12000)!;
    final unfit = bioAge(age: 30, female: false, vo2: 32, rhr: 75, hrv: 25, sleepH: 5.5, steps: 3000)!;
    expect(fit.age, lessThan(30));
    expect(unfit.age, greaterThan(30));
    expect(bioAge(age: 30, female: false), isNull);
  });

  test('recovery time grows with strain and with a low recovery', () {
    expect(recoveryHours(0), 0);
    expect(recoveryHours(21, recovery: 50), closeTo(72, 1e-9));
    expect(recoveryHours(14), lessThan(recoveryHours(18)));
    expect(recoveryHours(14, recovery: 30), greaterThan(recoveryHours(14, recovery: 90)));
  });

  test('race prediction follows Riegel from the fastest qualifying run', () {
    // 5 km in 25:00 predicts 10 km at 25 min × 2^1.06.
    final p = bestPrediction([(5000, 1500), (3000, 1200), (1000, 200)], 10000)!;
    expect(p, closeTo(1500 * 2.0849, 1));
    expect(bestPrediction([(1500, 400)], 5000), isNull);
    expect(raceTime(3725), '1:02:05');
    expect(raceTime(1500), '25:00');
  });
}
