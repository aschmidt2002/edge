import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_plus.dart';

void main() {
  final today = DateTime(2026, 11, 24);

  group('weightReachDate', () {
    test('a 550 kcal deficit loses 5 kg in 70 days', () {
      final d = weightReachDate(
          current: 85, target: 80, balance: -550, today: today);
      expect(d, DateTime(2027, 2, 2));
    });

    test('a surplus never reaches a lower target', () {
      expect(
          weightReachDate(current: 85, target: 80, balance: 200, today: today),
          isNull);
    });

    test('a zero balance has no date', () {
      expect(weightReachDate(current: 85, target: 80, balance: 0, today: today),
          isNull);
    });

    test('a surplus reaches a higher target', () {
      final d =
          weightReachDate(current: 70, target: 71, balance: 385, today: today);
      expect(d, DateTime(2026, 12, 14));
    });

    test('already there is today', () {
      expect(weightReachDate(current: 80, target: 80, balance: -500, today: today),
          today);
    });
  });

  test('balanceNeededBy spreads the energy over the days left', () {
    final b = balanceNeededBy(
        current: 85, target: 80, today: today, by: DateTime(2027, 2, 2));
    expect(b, closeTo(-550, 0.001));
    expect(
        balanceNeededBy(current: 85, target: 80, today: today, by: today),
        isNull);
  });
}
