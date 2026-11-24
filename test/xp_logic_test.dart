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
}
