import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/screentime/screen_time.dart';

void main() {
  String day(int i) {
    final d = DateTime(2026, 1, 1 + i);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  test('mann-whitney: separated groups are significant, identical are not', () {
    expect(mannWhitneyP([1, 2, 1, 2, 1, 2, 1, 2], [4, 5, 4, 5, 4, 5, 4, 5]), lessThan(0.01));
    expect(mannWhitneyP([3, 3, 3, 3, 3], [3, 3, 3, 3, 3]), 1);
  });

  test('heavy Instagram days with low mood produce one hint, worse', () {
    final screen = <String, ScreenDay>{};
    final mood = <String, double>{};
    for (var i = 0; i < 30; i++) {
      final heavy = i.isEven;
      screen[day(i)] = ScreenDay(
        apps: {'com.instagram.android': heavy ? 150 : 20, 'org.wiki': 30 + i % 3},
        unlocks: 60,
      );
      mood[day(i)] = heavy ? 2.0 + (i % 3) * 0.5 : 4.0 - (i % 3) * 0.5;
    }
    final hints = moodHints(screen, mood);
    expect(hints, isNotEmpty);
    final h = hints.first;
    expect(h.what, anyOf('com.instagram.android', ''));
    expect(h.delta, lessThan(-kMinMoodDelta));
    expect(hints.where((x) => x.what == 'org.wiki'), isEmpty);
  });

  test('noise and too few days stay silent', () {
    final screen = <String, ScreenDay>{};
    final mood = <String, double>{};
    for (var i = 0; i < 30; i++) {
      screen[day(i)] = ScreenDay(apps: {'a.b': (i * 37) % 200}, unlocks: (i * 53) % 160);
      mood[day(i)] = 1.0 + (i * 7) % 5;
    }
    expect(moodHints(screen, mood), isEmpty);
    final few = {for (final k in screen.keys.take(kMinMoodDays - 1)) k: screen[k]!};
    expect(moodHints(few, mood), isEmpty);
  });

  test('daily mood blends the evening and the next morning', () {
    final m = dailyMood({
      day(0): {'mood': const JournalMetricValue(2)},
      day(1): {'mood_morning': const JournalMetricValue(4)},
      day(3): {'mood_morning': const JournalMetricValue(5)},
    });
    expect(m[day(0)], 3);
    expect(m[day(2)], 5);
    expect(m.containsKey(day(1)), isFalse);
  });
}
