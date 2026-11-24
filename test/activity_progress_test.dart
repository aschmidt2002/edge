import 'package:openstrap_edge/ui2/activity/progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('muscles map onto the six areas', () {
    expect(areaOf('chest'), 'chest');
    expect(areaOf('Lats'), 'back');
    expect(areaOf('Triceps'), 'arms');
    expect(areaOf('Glutes'), 'legs');
    expect(areaOf('Obliquus externus abdominis'), 'core');
    expect(areaOf('Serratus anterior'), isNull);
  });

  test('sets land in their calendar week, e1RM keeps the best', () {
    final now = DateTime(2026, 11, 26, 18); // Thursday
    int ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    final d = progressFrom([
      {'exercise_key': 'bench_press', 'reps': 5, 'load_kg': 80.0, 'at_ts': ts(DateTime(2026, 11, 24, 9))},
      {'exercise_key': 'bench_press', 'reps': 10, 'load_kg': 60.0, 'at_ts': ts(DateTime(2026, 11, 22, 9))},
      {'exercise_key': 'bench_press', 'reps': 1, 'load_kg': 50.0, 'at_ts': ts(DateTime(2026, 9, 1, 9))},
    ], now);
    expect(d.areaSets['chest']!.last, 1); // this week
    expect(d.areaSets['chest']![kProgressWeeks - 2], 1); // Sunday = last week
    expect(d.areaSets['chest']!.reduce((a, b) => a + b), 2); // September is out
    expect(d.bestE1rm['bench_press'], closeTo(93.33, .01));
  });

  test('goal progress runs from start to target', () {
    const g = ActivityGoal(GoalKind.lift, 'bench_press', 100, start: 80);
    expect(g.frac(90), .5);
    expect(g.frac(120), 1);
    expect(g.frac(null), 0);
    expect(ActivityGoal.fromJson(g.toJson())!.start, 80);
    expect(ActivityGoal.fromJson({'kind': 'nope', 'target': 1}), isNull);
  });
}
