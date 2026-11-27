// Plain data the pacing app stores. No Flutter import: everything under
// lib/core is pure Dart so the model can be unit-tested and later moved into a
// package of its own.

/// Severity as the NICE guideline NG206 (2021, Box 1) describes it. The app
/// uses it only to choose wording, defaults and the kind of ideas it shows; it
/// is the person's own pick, never something the app diagnoses.
enum Severity { mild, moderate, severe, verySevere }

/// What kind of effort an activity costs. Heart rate only sees the physical
/// part, so the other three have to come from the person's own log.
enum EffortKind { physical, cognitive, emotional, orthostatic }

/// How the heart-rate ceiling is set.
enum ThresholdMode {
  /// Resting heart rate + 15 bpm (rule of thumb from the Workwell Foundation).
  restingPlus15,

  /// 55 % of (220 − age) (a more conservative age-based rule of thumb).
  agePercent,

  /// A number the person enters, e.g. from a two-day CPET or their doctor.
  manual,
}

String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

DateTime dayOf(String key) => DateTime.parse(key);

/// The short daily check-in. Every scale is 0..4 so one row of five buttons
/// fits on a phone, and everything except [feeling] may be left out: on a bad
/// day one tap has to be enough.
class CheckIn {
  CheckIn({
    required this.day,
    required this.feeling,
    this.fatigue,
    this.brainFog,
    this.pain,
    this.sleepRefreshing,
    this.orthostatic,
    this.crash = false,
    this.crashSeverity,
    this.note,
    this.menstruating,
    this.infection,
  });

  final String day;

  /// 0 = very bad … 4 = very good.
  final int feeling;

  /// 0 = none … 4 = severe. Same direction for brainFog, pain, orthostatic.
  final int? fatigue;
  final int? brainFog;
  final int? pain;
  final int? orthostatic;

  /// 0 = not at all … 4 = fully refreshed.
  final int? sleepRefreshing;

  /// The person says they are in a crash / PEM today.
  final bool crash;

  /// 1 = mild … 3 = severe.
  final int? crashSeverity;
  final String? note;
  final bool? menstruating;
  final bool? infection;

  /// 0 (worst) .. 1 (best) from whatever was answered. Symptoms count against,
  /// a crash pulls it down hard.
  double get wellness {
    final parts = <double>[feeling / 4];
    for (final s in [fatigue, brainFog, pain, orthostatic]) {
      if (s != null) parts.add(1 - s / 4);
    }
    if (sleepRefreshing != null) parts.add(sleepRefreshing! / 4);
    var w = parts.reduce((a, b) => a + b) / parts.length;
    if (crash) w *= 1 - 0.2 * (crashSeverity ?? 2);
    return w.clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
        'day': day,
        'feeling': feeling,
        'fatigue': fatigue,
        'brainFog': brainFog,
        'pain': pain,
        'sleepRefreshing': sleepRefreshing,
        'orthostatic': orthostatic,
        'crash': crash,
        'crashSeverity': crashSeverity,
        'note': note,
        'menstruating': menstruating,
        'infection': infection,
      };

  factory CheckIn.fromJson(Map<String, Object?> j) => CheckIn(
        day: j['day'] as String,
        feeling: j['feeling'] as int,
        fatigue: j['fatigue'] as int?,
        brainFog: j['brainFog'] as int?,
        pain: j['pain'] as int?,
        sleepRefreshing: j['sleepRefreshing'] as int?,
        orthostatic: j['orthostatic'] as int?,
        crash: j['crash'] as bool? ?? false,
        crashSeverity: j['crashSeverity'] as int?,
        note: j['note'] as String?,
        menstruating: j['menstruating'] as bool?,
        infection: j['infection'] as bool?,
      );
}

/// Something the person did, logged by hand. Covers what a heart-rate sensor
/// cannot see: a phone call, a doctor's visit, standing in the shower.
class ActivityLog {
  ActivityLog({
    required this.id,
    required this.start,
    required this.minutes,
    required this.kind,
    required this.intensity,
    required this.label,
  });

  final String id;
  final DateTime start;
  final int minutes;
  final EffortKind kind;

  /// 1 = light, 2 = medium, 3 = hard (for this person, today).
  final int intensity;
  final String label;

  String get day => dayKey(start);

  Map<String, Object?> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'minutes': minutes,
        'kind': kind.name,
        'intensity': intensity,
        'label': label,
      };

  factory ActivityLog.fromJson(Map<String, Object?> j) => ActivityLog(
        id: j['id'] as String,
        start: DateTime.parse(j['start'] as String),
        minutes: j['minutes'] as int,
        kind: EffortKind.values.byName(j['kind'] as String),
        intensity: j['intensity'] as int,
        label: j['label'] as String,
      );
}

class Medication {
  Medication({
    required this.id,
    required this.name,
    this.dose = '',
    this.times = const [],
    this.affectsHeartRate = false,
    this.active = true,
  });

  final String id;
  final String name;
  final String dose;

  /// Planned times of day as "HH:MM".
  final List<String> times;

  /// Beta blockers, ivabradine and similar lower heart rate, which makes a
  /// heart-rate ceiling based on age or resting HR misleading.
  final bool affectsHeartRate;
  final bool active;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'times': times,
        'affectsHeartRate': affectsHeartRate,
        'active': active,
      };

  factory Medication.fromJson(Map<String, Object?> j) => Medication(
        id: j['id'] as String,
        name: j['name'] as String,
        dose: j['dose'] as String? ?? '',
        times: (j['times'] as List?)?.cast<String>() ?? const [],
        affectsHeartRate: j['affectsHeartRate'] as bool? ?? false,
        active: j['active'] as bool? ?? true,
      );
}

class MedIntake {
  MedIntake({required this.medId, required this.at, this.note});
  final String medId;
  final DateTime at;
  final String? note;

  Map<String, Object?> toJson() =>
      {'medId': medId, 'at': at.toIso8601String(), 'note': note};
  factory MedIntake.fromJson(Map<String, Object?> j) => MedIntake(
        medId: j['medId'] as String,
        at: DateTime.parse(j['at'] as String),
        note: j['note'] as String?,
      );
}

/// What one day cost and how it started. Written as the day runs and kept for
/// the history, the envelope adaptation and the crash look-back.
class DaySummary {
  DaySummary({
    required this.day,
    required this.envelope,
    required this.startCharge,
    this.used = 0,
    this.recharged = 0,
    this.minutesOverThreshold = 0,
    this.peakHr,
    this.steps,
  });

  final String day;

  /// The personal envelope (points) that applied that day.
  final double envelope;

  /// Points available at the start of the day.
  final double startCharge;
  double used;
  double recharged;
  int minutesOverThreshold;
  int? peakHr;
  int? steps;

  double get remaining =>
      (startCharge - used + recharged).clamp(0.0, envelope).toDouble();

  /// Share of the envelope that was spent, can exceed 1 (overspent).
  double get usedShare => envelope <= 0 ? 0 : used / envelope;

  Map<String, Object?> toJson() => {
        'day': day,
        'envelope': envelope,
        'startCharge': startCharge,
        'used': used,
        'recharged': recharged,
        'minutesOverThreshold': minutesOverThreshold,
        'peakHr': peakHr,
        'steps': steps,
      };

  factory DaySummary.fromJson(Map<String, Object?> j) => DaySummary(
        day: j['day'] as String,
        envelope: (j['envelope'] as num).toDouble(),
        startCharge: (j['startCharge'] as num).toDouble(),
        used: (j['used'] as num?)?.toDouble() ?? 0,
        recharged: (j['recharged'] as num?)?.toDouble() ?? 0,
        minutesOverThreshold: j['minutesOverThreshold'] as int? ?? 0,
        peakHr: j['peakHr'] as int?,
        steps: j['steps'] as int?,
      );
}

/// Overnight / morning numbers from a wearable or Apple Health / Health
/// Connect. Every field may be missing: a missing number is left out of the
/// estimate, never guessed.
class MorningVitals {
  const MorningVitals({this.restingHr, this.hrv, this.sleepHours});
  final double? restingHr;
  final double? hrv;
  final double? sleepHours;

  Map<String, Object?> toJson() =>
      {'restingHr': restingHr, 'hrv': hrv, 'sleepHours': sleepHours};
  factory MorningVitals.fromJson(Map<String, Object?> j) => MorningVitals(
        restingHr: (j['restingHr'] as num?)?.toDouble(),
        hrv: (j['hrv'] as num?)?.toDouble(),
        sleepHours: (j['sleepHours'] as num?)?.toDouble(),
      );
}

class PacingSettings {
  PacingSettings({
    this.onboarded = false,
    this.severity = Severity.moderate,
    this.age,
    this.restingHr,
    this.thresholdMode = ThresholdMode.restingPlus15,
    this.manualThreshold,
    this.envelope = 100,
    this.autoAdaptEnvelope = true,
    this.vibrationAlerts = true,
    this.alertAtBatteryPercent = 20,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 8,
    this.hrDeviceId,
    this.hrDeviceName,
    this.useHealthData = false,
    this.lastEnvelopeChange,
  });

  bool onboarded;
  Severity severity;
  int? age;

  /// Manual resting HR. Measured values from the wearable win when present.
  double? restingHr;
  ThresholdMode thresholdMode;
  int? manualThreshold;

  /// Daily energy envelope in points. 100 is just the starting scale.
  double envelope;
  bool autoAdaptEnvelope;
  bool vibrationAlerts;
  int alertAtBatteryPercent;
  int quietHoursStart;
  int quietHoursEnd;
  String? hrDeviceId;
  String? hrDeviceName;
  bool useHealthData;
  String? lastEnvelopeChange;

  Map<String, Object?> toJson() => {
        'onboarded': onboarded,
        'severity': severity.name,
        'age': age,
        'restingHr': restingHr,
        'thresholdMode': thresholdMode.name,
        'manualThreshold': manualThreshold,
        'envelope': envelope,
        'autoAdaptEnvelope': autoAdaptEnvelope,
        'vibrationAlerts': vibrationAlerts,
        'alertAtBatteryPercent': alertAtBatteryPercent,
        'quietHoursStart': quietHoursStart,
        'quietHoursEnd': quietHoursEnd,
        'hrDeviceId': hrDeviceId,
        'hrDeviceName': hrDeviceName,
        'useHealthData': useHealthData,
        'lastEnvelopeChange': lastEnvelopeChange,
      };

  factory PacingSettings.fromJson(Map<String, Object?> j) => PacingSettings(
        onboarded: j['onboarded'] as bool? ?? false,
        severity: Severity.values.byName(j['severity'] as String? ?? 'moderate'),
        age: j['age'] as int?,
        restingHr: (j['restingHr'] as num?)?.toDouble(),
        thresholdMode: ThresholdMode.values
            .byName(j['thresholdMode'] as String? ?? 'restingPlus15'),
        manualThreshold: j['manualThreshold'] as int?,
        envelope: (j['envelope'] as num?)?.toDouble() ?? 100,
        autoAdaptEnvelope: j['autoAdaptEnvelope'] as bool? ?? true,
        vibrationAlerts: j['vibrationAlerts'] as bool? ?? true,
        alertAtBatteryPercent: j['alertAtBatteryPercent'] as int? ?? 20,
        quietHoursStart: j['quietHoursStart'] as int? ?? 22,
        quietHoursEnd: j['quietHoursEnd'] as int? ?? 8,
        hrDeviceId: j['hrDeviceId'] as String?,
        hrDeviceName: j['hrDeviceName'] as String?,
        useHealthData: j['useHealthData'] as bool? ?? false,
        lastEnvelopeChange: j['lastEnvelopeChange'] as String?,
      );
}
