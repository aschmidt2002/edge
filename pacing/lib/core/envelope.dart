// How the envelope (the size of the battery) changes over weeks.
//
// Deliberately asymmetric. ME/CFS improvement, when it comes, is slow and
// uneven, and the classic trap is "boom and bust": a good stretch, more
// activity, a crash. So:
//  * growth needs 14 crash-free days in which the person actually used most
//    of the envelope without symptoms getting worse, and is capped at +5 %
//    per two weeks;
//  * a crash shrinks it by 10–20 % at once and blocks growth for 14 days.
// The envelope is never a goal to push. It follows what the body showed.

import 'dart:math' as math;

import 'models.dart';

class EnvelopeDecision {
  const EnvelopeDecision(this.newEnvelope, this.reason);
  final double newEnvelope;

  /// Short German text for the UI, or null when nothing changed.
  final String? reason;
  bool get changed => reason != null;
}

const double kMinEnvelope = 30;
const double kMaxEnvelope = 300;

EnvelopeDecision adaptEnvelope({
  required double envelope,
  required List<DaySummary> days,
  required List<CheckIn> checkIns,
  required DateTime today,
  String? lastChange,
}) {
  final todayKey = dayKey(today);
  String keyDaysAgo(int n) => dayKey(today.subtract(Duration(days: n)));

  // Crash reported in the last 2 days and not yet acted on → shrink.
  final recentCrash = checkIns
      .where((c) => c.crash && c.day.compareTo(keyDaysAgo(2)) >= 0)
      .toList();
  if (recentCrash.isNotEmpty &&
      (lastChange == null || lastChange.compareTo(recentCrash.first.day) < 0)) {
    final sev = recentCrash.map((c) => c.crashSeverity ?? 2).reduce(math.max);
    final cut = 0.05 + 0.05 * sev; // 10 / 15 / 20 %
    final next = math.max(kMinEnvelope, envelope * (1 - cut));
    return EnvelopeDecision(next,
        'Crash gemeldet: Rahmen um ${(cut * 100).round()} % verkleinert. Für 14 Tage wächst er nicht.');
  }

  // Growth: at most once per 14 days.
  if (lastChange != null &&
      today.difference(dayOf(lastChange)).inDays < 14) {
    return EnvelopeDecision(envelope, null);
  }
  final window = days
      .where((d) =>
          d.day.compareTo(keyDaysAgo(14)) >= 0 && d.day.compareTo(todayKey) < 0)
      .toList();
  final windowChecks = checkIns
      .where((c) =>
          c.day.compareTo(keyDaysAgo(14)) >= 0 && c.day.compareTo(todayKey) < 0)
      .toList()
    ..sort((a, b) => a.day.compareTo(b.day));
  if (window.length < 12 || windowChecks.length < 10) {
    return EnvelopeDecision(envelope, null); // not enough evidence
  }
  if (windowChecks.any((c) => c.crash)) return EnvelopeDecision(envelope, null);
  if (window.any((d) => d.usedShare > 1.05)) {
    return EnvelopeDecision(envelope, null);
  }
  final avgUse =
      window.map((d) => d.usedShare).reduce((a, b) => a + b) / window.length;
  if (avgUse < 0.7) return EnvelopeDecision(envelope, null);

  // Symptoms must not be trending worse: second week no worse than first.
  final half = windowChecks.length ~/ 2;
  double avg(Iterable<CheckIn> xs) =>
      xs.map((c) => c.wellness).reduce((a, b) => a + b) / xs.length;
  final first = avg(windowChecks.take(half));
  final second = avg(windowChecks.skip(half));
  if (second < first - 0.03) return EnvelopeDecision(envelope, null);

  final next = math.min(kMaxEnvelope, envelope * 1.05);
  return EnvelopeDecision(next,
      '14 stabile Tage ohne Crash: Rahmen vorsichtig um 5 % vergrößert.');
}
