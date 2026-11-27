// The heart-rate ceiling ("anaerobic threshold" estimate).
//
// Two common rules of thumb exist, both rough:
//  * resting HR + 15 bpm (Workwell Foundation),
//  * roughly 50–60 % of the age-predicted maximum (220 − age).
// A two-day CPET measures the real threshold and always wins when it exists.
// Medicines that slow the heart (beta blockers, ivabradine) make both rules
// unreliable, so the app asks for a manual value then.

import 'models.dart';

class HrThreshold {
  const HrThreshold({required this.ceiling, required this.source, this.warning});

  /// bpm. Null when there is not enough input to set one.
  final int? ceiling;
  final ThresholdMode source;

  /// Text the UI should show next to the number, e.g. why it is unreliable.
  final String? warning;

  /// A gentle nudge fires this many bpm below the ceiling.
  static const int nudgeMargin = 5;
}

HrThreshold computeThreshold(
  PacingSettings s, {
  double? measuredRestingHr,
  bool hrAffectingMeds = false,
}) {
  final resting = measuredRestingHr ?? s.restingHr;
  final medWarning = hrAffectingMeds && s.thresholdMode != ThresholdMode.manual
      ? 'Auf deiner Liste steht ein Medikament, das den Puls senkt. Dann sind '
          'Faustregeln unzuverlässig – die Grenze besser mit Ärztin/Arzt festlegen.'
      : null;

  switch (s.thresholdMode) {
    case ThresholdMode.manual:
      return HrThreshold(ceiling: s.manualThreshold, source: s.thresholdMode);
    case ThresholdMode.restingPlus15:
      return HrThreshold(
        ceiling: resting == null ? null : (resting + 15).round(),
        source: s.thresholdMode,
        warning: medWarning,
      );
    case ThresholdMode.agePercent:
      final age = s.age;
      return HrThreshold(
        ceiling: age == null ? null : ((220 - age) * 0.55).round(),
        source: s.thresholdMode,
        warning: medWarning,
      );
  }
}
