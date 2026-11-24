// Edge+: the four-part sleep score (lib/compute/sleep_score.dart). Pure.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/sleep_score.dart';

void main() {
  Map<String, dynamic> v(Map<String, dynamic> m) =>
      (m['value'] as Map).cast<String, dynamic>();

  test('no TST or no learned need is no score, never a guess', () {
    expect(computeSleepScore(tstMin: null, needMin: 480)['value'], '—');
    expect(computeSleepScore(tstMin: 400, needMin: null)['value'], '—');
  });

  test('sufficiency alone is the score, capped at 100', () {
    expect(v(computeSleepScore(tstMin: 360, needMin: 480))['score'], 75);
    expect(v(computeSleepScore(tstMin: 600, needMin: 480))['score'], 100);
  });

  test('consistency: 40 min mean deviation is 80, needs two prior nights', () {
    const prior = [
      (onsetMin: 23 * 60.0, wakeMin: 7 * 60.0),
      (onsetMin: 23 * 60.0, wakeMin: 7 * 60.0),
    ];
    // Bed 40 min late across midnight, wake 40 min late: 40 min → 80.
    final s = v(computeSleepScore(
      tstMin: 480,
      needMin: 480,
      onsetMin: 23 * 60.0 + 40,
      wakeMin: 7 * 60.0 + 40,
      priorNights: prior,
    ));
    expect(s['consistency_pct'], 80);
    final exact = consistencyDeviationMin(
      onsetMin: 20, // 00:20 vs 23:00 = 80 min across midnight
      wakeMin: 7 * 60.0,
      priorNights: prior,
    );
    expect(exact, 40); // (80 + 0) / 2
    expect(
        consistencyDeviationMin(
            onsetMin: 20, wakeMin: 420, priorNights: prior.sublist(1)),
        isNull);
  });

  test('stress is scored against the user median, not an absolute', () {
    final base = List<double>.filled(10, 40);
    final calm = v(computeSleepScore(
        tstMin: 480, needMin: 480, stress: 38, priorStress: base));
    expect(calm['stress_pct'], 100);
    expect(calm['stress_level'], 'low');
    final tense = v(computeSleepScore(
        tstMin: 480, needMin: 480, stress: 60, priorStress: base));
    expect(tense['stress_pct'], 50);
    expect(tense['stress_level'], 'high');
    // Too little history: no stress component at all.
    expect(
        v(computeSleepScore(
            tstMin: 480, needMin: 480, stress: 60, priorStress: [40]))['stress_pct'],
        isNull);
  });

  test('weights 50/20/20/10 over the components present', () {
    final s = v(computeSleepScore(
      tstMin: 432, // 90 %
      needMin: 480,
      onsetMin: 23 * 60.0,
      wakeMin: 7 * 60.0,
      priorNights: const [
        (onsetMin: 23 * 60.0, wakeMin: 7 * 60.0),
        (onsetMin: 23 * 60.0, wakeMin: 7 * 60.0),
      ], // 100
      efficiencyPct: 80,
      stress: 40,
      priorStress: List<double>.filled(5, 40), // 100
    ));
    // 0.5*90 + 0.2*100 + 0.2*80 + 0.1*100 = 91
    expect(s['score'], 91);
  });
}
