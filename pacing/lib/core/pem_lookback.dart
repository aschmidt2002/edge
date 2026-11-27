// Crash look-back. PEM usually starts 12–72 hours after the trigger, which
// is why people so often cannot tell what caused it. When a crash is
// reported, show what the 1–3 days before it cost, biggest first. This is a
// memory aid, not a diagnosis: it lists candidates, it never says "this
// caused it".

import 'models.dart';

class LookbackItem {
  const LookbackItem(this.day, this.label, this.points, {this.overspent = false});
  final String day;
  final String label;
  final double points;
  final bool overspent;
}

List<LookbackItem> crashLookback({
  required String crashDay,
  required List<DaySummary> days,
  required List<ActivityLog> logs,
  required double Function(ActivityLog) costOf,
  int limit = 6,
}) {
  final crash = dayOf(crashDay);
  final window = {
    for (var n = 1; n <= 3; n++) dayKey(crash.subtract(Duration(days: n))),
  };
  final items = <LookbackItem>[];
  for (final d in days.where((d) => window.contains(d.day))) {
    if (d.usedShare > 1) {
      items.add(LookbackItem(
          d.day, 'Tag überzogen (${(d.usedShare * 100).round()} %)', d.used,
          overspent: true));
    }
    if (d.minutesOverThreshold >= 5) {
      items.add(LookbackItem(d.day,
          '${d.minutesOverThreshold} min über der Pulsgrenze', d.minutesOverThreshold * 1.0));
    }
  }
  for (final l in logs.where((l) => window.contains(l.day))) {
    items.add(LookbackItem(l.day, l.label, costOf(l)));
  }
  items.sort((a, b) => b.points.compareTo(a.points));
  return items.take(limit).toList();
}
