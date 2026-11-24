// sleep_score.dart — Edge+: one 0–100 sleep score out of four components.
//
// PURE, isolate-safe, no imports: crossday_pipeline hands it numbers it
// already has (TST, the learned need, onset/wake clock minutes, efficiency,
// the nightly sleep stress score) and stores the result next to the original
// `sleep_coach.performance`, which stays untouched. Nothing else reads this
// score: recovery/readiness never took sleep performance as an input.
//
// Components (each 0–100, higher is better):
//   sufficiency  TST ÷ learned need (need already folds in debt, strain, naps)
//   consistency  bed + wake clock times vs the prior four nights;
//                100 − (mean deviation in minutes ÷ 2), so 40 min ≈ 80,
//                60 min ≈ 70 — the 80 % / 70 % bands line up with real minutes
//   efficiency   time asleep ÷ time in bed, as the night pipeline measured it
//   stress       nightly stress score above the user's own median;
//                100 − 2.5 × excess points, so a typical night scores 100
//
// Score = weighted mean of the components present (sufficiency 50, consistency
// 20, efficiency 20, stress 10). Sufficiency is required: without TST and a
// learned need there is no score, never a guessed one.

const kSleepScoreWeights = <String, double>{
  'sufficiency': 0.5,
  'consistency': 0.2,
  'efficiency': 0.2,
  'stress': 0.1,
};

/// Prior nights that must have both a bedtime and a wake time for consistency.
const kConsistencyMinPriorNights = 2;

/// Prior nights' stress needed before tonight's can be called elevated.
const kSleepStressMinBaseline = 5;

/// One prior night's local bed and wake clock, minutes of day [0, 1440).
typedef NightClock = ({double onsetMin, double wakeMin});

/// The score as a Metric-shaped envelope (`value` map, or `'—'` + `note`).
Map<String, dynamic> computeSleepScore({
  required double? tstMin,
  required double? needMin,
  double? onsetMin,
  double? wakeMin,
  List<NightClock> priorNights = const [],
  double? efficiencyPct,
  double? stress,
  List<double> priorStress = const [],
}) {
  if (tstMin == null || needMin == null || needMin <= 0) {
    return {
      'value': '—',
      'confidence': 0,
      'inputs_used': const ['tst', 'sleep_need'],
      'note': tstMin == null ? 'need_input:name=tst_min' : 'need_input:name=sleep_need',
    };
  }
  final parts = <String, double>{
    'sufficiency': _pct(tstMin / needMin * 100),
  };

  final dev = consistencyDeviationMin(
      onsetMin: onsetMin, wakeMin: wakeMin, priorNights: priorNights);
  if (dev != null) parts['consistency'] = _pct(100 - dev / 2);

  if (efficiencyPct != null && efficiencyPct.isFinite) {
    parts['efficiency'] = _pct(efficiencyPct);
  }

  double? excess;
  if (stress != null && stress.isFinite &&
      priorStress.length >= kSleepStressMinBaseline) {
    excess = stress - _median(priorStress);
    parts['stress'] = _pct(100 - 2.5 * (excess < 0 ? 0 : excess));
  }

  var sum = 0.0, w = 0.0;
  parts.forEach((k, v) {
    sum += v * kSleepScoreWeights[k]!;
    w += kSleepScoreWeights[k]!;
  });

  return {
    'value': {
      'score': (sum / w).round(),
      'sufficiency_pct': parts['sufficiency']!.round(),
      'consistency_pct': parts['consistency']?.round(),
      'efficiency_pct': parts['efficiency']?.round(),
      'stress_pct': parts['stress']?.round(),
      // Raw nightly stress (0–100) and how it sat against the user's median.
      'stress': stress == null ? null : _r1(stress),
      'stress_level': excess == null
          ? null
          : excess <= 5
              ? 'low'
              : excess <= 15
                  ? 'moderate'
                  : 'high',
      'consistency_dev_min': dev?.round(),
      'need_min': needMin.round(),
    },
    'confidence': _r1(w * 0.7),
    'inputs_used': parts.keys.toList(),
  };
}

/// Mean absolute clock deviation (minutes) of tonight's bed and wake time from
/// each prior night's, or null with fewer than [kConsistencyMinPriorNights].
double? consistencyDeviationMin({
  required double? onsetMin,
  required double? wakeMin,
  required List<NightClock> priorNights,
}) {
  if (onsetMin == null || wakeMin == null) return null;
  if (priorNights.length < kConsistencyMinPriorNights) return null;
  var s = 0.0;
  for (final p in priorNights) {
    s += (_clockDiff(onsetMin, p.onsetMin) + _clockDiff(wakeMin, p.wakeMin)) / 2;
  }
  return s / priorNights.length;
}

/// Shortest distance between two clock minutes, across midnight.
double _clockDiff(double a, double b) {
  final d = (a - b).abs() % 1440;
  return d > 720 ? 1440 - d : d;
}

double _pct(double v) => v.isFinite ? v.clamp(0.0, 100.0) : 0.0;
double _r1(double v) => (v * 10).round() / 10;

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}
