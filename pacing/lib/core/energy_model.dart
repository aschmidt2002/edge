// The energy battery. A MODEL, not a measurement: nobody can measure an
// "energy envelope" directly. What the app can do is combine
//   * heart rate against a personal ceiling (physical effort, live),
//   * hand-logged cognitive / emotional / orthostatic effort (which heart rate
//     barely shows),
//   * how the night and the morning check-in went,
// into one number that behaves the way people with ME/CFS describe their
// budget: it starts lower after a bad night or during a crash, it drains
// faster the harder you go, and rest does not refill it much on the same day.
//
// Every constant here is a starting guess meant to be tuned with the person
// who uses it. They are collected in [EnergyTuning] for that reason.

import 'dart:math' as math;

import 'models.dart';

class EnergyTuning {
  const EnergyTuning({
    this.restBand = 0.25,
    this.pointsPerMinuteAtCeiling = 0.5,
    this.overCeilingSlope = 2.5,
    this.overCeilingFloor = 1.0,
    this.restRechargePerMinute = 0.05,
    this.maxRechargeShare = 0.15,
    this.logPointsPerMinute = const {
      EffortKind.physical: 0.30,
      EffortKind.cognitive: 0.25,
      EffortKind.emotional: 0.30,
      EffortKind.orthostatic: 0.30,
    },
  });

  /// Below this share of the way from resting HR to the ceiling a minute
  /// counts as rest and costs nothing beyond the day's baseline.
  final double restBand;

  /// Points one minute costs right at the ceiling, on a 100-point envelope.
  final double pointsPerMinuteAtCeiling;

  /// Extra cost per minute for every "ceiling distance" above it. Going over
  /// the ceiling is meant to hurt the battery a lot more than going near it,
  /// because that is where the anaerobic work and the PEM risk sit.
  final double overCeilingSlope;

  /// A minute above the ceiling costs at least this many points on top.
  final double overCeilingFloor;

  /// Lying still near resting HR gives a little back.
  final double restRechargePerMinute;

  /// Rest recharges at most this share of the envelope per day.
  final double maxRechargeShare;

  /// Hand-logged effort per minute at intensity 1. Intensity 2 doubles it,
  /// 3 triples it.
  final Map<EffortKind, double> logPointsPerMinute;
}

class EnergyModel {
  const EnergyModel({this.tuning = const EnergyTuning()});
  final EnergyTuning tuning;

  /// Cost of ONE minute at [hr] (bpm), given [resting] and [ceiling] bpm, for
  /// an envelope of [envelope] points. Returns 0 for rest. The cost scales
  /// with the envelope so the battery percentage behaves the same however big
  /// the envelope has grown.
  double minuteCost({
    required double hr,
    required double resting,
    required double ceiling,
    required double envelope,
  }) {
    final span = math.max(ceiling - resting, 5.0);
    final x = (hr - resting) / span; // 0 at rest, 1 at the ceiling
    final scale = envelope / 100;
    if (x <= tuning.restBand) return 0;
    if (x <= 1) {
      final t = (x - tuning.restBand) / (1 - tuning.restBand);
      // Convex: gentle near rest, steep close to the ceiling.
      return tuning.pointsPerMinuteAtCeiling * t * t * scale;
    }
    final over = x - 1;
    return (tuning.pointsPerMinuteAtCeiling +
            tuning.overCeilingFloor +
            tuning.overCeilingSlope * over) *
        scale;
  }

  /// Points a minute of rest gives back, or 0 when the minute is not rest.
  double minuteRecharge({
    required double hr,
    required double resting,
    required double ceiling,
    required double envelope,
  }) {
    final span = math.max(ceiling - resting, 5.0);
    final x = (hr - resting) / span;
    if (x > tuning.restBand * 0.5) return 0;
    return tuning.restRechargePerMinute * envelope / 100;
  }

  double maxRecharge(double envelope) => envelope * tuning.maxRechargeShare;

  /// Cost of a hand-logged activity.
  double logCost(ActivityLog a, {required double envelope}) =>
      (tuning.logPointsPerMinute[a.kind] ?? 0.3) *
      a.intensity *
      a.minutes *
      envelope /
      100;

  /// How full the battery is when the day starts, as a share of the envelope.
  ///
  /// Starts at 1 and only ever goes DOWN from the evidence available:
  ///  * check-in wellness (strongest, it is what the person feels),
  ///  * resting HR above the person's baseline,
  ///  * HRV below the person's baseline,
  ///  * yesterday overspent (debt carries over, PEM comes late),
  ///  * an ongoing crash.
  /// Missing evidence leaves the factor alone: nothing is guessed.
  double morningCharge({
    CheckIn? checkIn,
    MorningVitals? today,
    List<MorningVitals> baseline = const [],
    List<DaySummary> recentDays = const [],
  }) {
    var f = 1.0;

    if (checkIn != null) {
      // wellness 1 → ×1.0, wellness 0 → ×0.35
      f *= 0.35 + 0.65 * checkIn.wellness;
    }

    double? mean(Iterable<double?> xs) {
      final v = xs.whereType<double>().toList();
      if (v.length < 3) return null; // too little history to call a baseline
      return v.reduce((a, b) => a + b) / v.length;
    }

    double? sd(Iterable<double?> xs, double m) {
      final v = xs.whereType<double>().toList();
      if (v.length < 3) return null;
      final s = v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) /
          (v.length - 1);
      return math.sqrt(s);
    }

    final rhrBase = mean(baseline.map((v) => v.restingHr));
    if (rhrBase != null && today?.restingHr != null) {
      final d = today!.restingHr! - rhrBase;
      // Every bpm above baseline costs 3 %, up to 30 %.
      if (d > 1) f *= 1 - math.min(0.3, 0.03 * (d - 1));
    }

    final hrvBase = mean(baseline.map((v) => v.hrv));
    if (hrvBase != null && today?.hrv != null) {
      final s = sd(baseline.map((v) => v.hrv), hrvBase);
      if (s != null && s > 0) {
        final z = (today!.hrv! - hrvBase) / s;
        // Below −0.5 SD costs up to 25 %.
        if (z < -0.5) f *= 1 - math.min(0.25, 0.12 * (-z - 0.5));
      }
    }

    if (recentDays.isNotEmpty) {
      // PEM typically lands 12–72 h after the trigger, so look at the last
      // three days and weigh the most recent most.
      final sorted = [...recentDays]..sort((a, b) => b.day.compareTo(a.day));
      const weights = [0.5, 0.3, 0.2];
      var debt = 0.0;
      for (var i = 0; i < math.min(3, sorted.length); i++) {
        final over = sorted[i].usedShare - 1;
        if (over > 0) debt += weights[i] * over;
      }
      f *= 1 - math.min(0.4, debt);
    }

    if (checkIn?.crash == true) {
      // In a crash the plan is rest, so keep the budget small on purpose.
      f = math.min(f, 0.5 - 0.1 * ((checkIn!.crashSeverity ?? 2) - 1));
    }

    return f.clamp(0.15, 1.0).toDouble();
  }
}
