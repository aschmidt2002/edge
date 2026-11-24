import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/experimental/health_level.dart';

void main() {
  // Thirty calm nights, then one with resting HR up and HRV down.
  Map<String, Map<String, double>> series({bool sickLast = true}) {
    final rhr = <String, double>{}, hrv = <String, double>{};
    for (var i = 1; i <= 31; i++) {
      final d = '2026-10-${i.toString().padLeft(2, '0')}';
      rhr[d] = 55 + (i % 3);
      hrv[d] = 70 + (i % 5);
    }
    if (sickLast) {
      rhr['2026-10-31'] = 64;
      hrv['2026-10-31'] = 48;
    }
    return {'resting_hr': rhr, 'hrv': hrv};
  }

  test('a normal night reads healthy, a raised one reads at risk', () {
    final f = healthFeatures(series());
    expect(healthLevelOf(healthRisk(f['2026-10-30']!)), greaterThan(75));
    expect(healthLevelOf(healthRisk(f['2026-10-31']!)), lessThan(25));
    // Too little history: no z at all.
    expect(f['2026-10-02']!.every((v) => v == null), isTrue);
  });

  test('answers move the weights', () {
    final f = healthFeatures(series());
    final calm = f['2026-10-30']!;
    // You were ill on a calm-looking night, more than once: risk on calm
    // nights goes up.
    final w = learnHealthWeights([(calm, true), (f['2026-10-29']!, true)]);
    expect(healthRisk(calm, w), greaterThan(healthRisk(calm)));
    // You were fine on the raised night: its risk comes down.
    final raised = f['2026-10-31']!;
    final w2 = learnHealthWeights([(raised, false)]);
    expect(healthRisk(raised, w2), lessThan(healthRisk(raised)));
    expect(learnHealthWeights(const []), kHealthPrior);
  });
}
