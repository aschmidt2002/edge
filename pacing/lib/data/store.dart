// Everything stays on the phone, in one JSON file in the app's documents
// folder. Health data never leaves the device unless the person exports it.
// ponytail: one file rewritten on every save. Fine for years of daily rows
// (a few hundred KB); move to sqlite once per-minute HR history is kept.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/models.dart';

class PacingData {
  PacingData({
    PacingSettings? settings,
    List<CheckIn>? checkIns,
    List<ActivityLog>? logs,
    List<Medication>? meds,
    List<MedIntake>? intakes,
    List<DaySummary>? days,
    Map<String, MorningVitals>? vitals,
    Set<String>? hiddenIdeas,
    List<String>? envelopeLog,
  })  : settings = settings ?? PacingSettings(),
        checkIns = checkIns ?? [],
        logs = logs ?? [],
        meds = meds ?? [],
        intakes = intakes ?? [],
        days = days ?? [],
        vitals = vitals ?? {},
        hiddenIdeas = hiddenIdeas ?? {},
        envelopeLog = envelopeLog ?? [];

  PacingSettings settings;
  final List<CheckIn> checkIns;
  final List<ActivityLog> logs;
  final List<Medication> meds;
  final List<MedIntake> intakes;
  final List<DaySummary> days;
  final Map<String, MorningVitals> vitals;
  final Set<String> hiddenIdeas;

  /// "yyyy-mm-dd: text" lines, newest last, so the person can see why the
  /// envelope moved.
  final List<String> envelopeLog;

  Map<String, Object?> toJson() => {
        'version': 1,
        'settings': settings.toJson(),
        'checkIns': checkIns.map((e) => e.toJson()).toList(),
        'logs': logs.map((e) => e.toJson()).toList(),
        'meds': meds.map((e) => e.toJson()).toList(),
        'intakes': intakes.map((e) => e.toJson()).toList(),
        'days': days.map((e) => e.toJson()).toList(),
        'vitals': vitals.map((k, v) => MapEntry(k, v.toJson())),
        'hiddenIdeas': hiddenIdeas.toList(),
        'envelopeLog': envelopeLog,
      };

  factory PacingData.fromJson(Map<String, Object?> j) {
    List<T> list<T>(String k, T Function(Map<String, Object?>) f) =>
        ((j[k] as List?) ?? const [])
            .map((e) => f((e as Map).cast<String, Object?>()))
            .toList();
    return PacingData(
      settings: j['settings'] == null
          ? null
          : PacingSettings.fromJson(
              (j['settings'] as Map).cast<String, Object?>()),
      checkIns: list('checkIns', CheckIn.fromJson),
      logs: list('logs', ActivityLog.fromJson),
      meds: list('meds', Medication.fromJson),
      intakes: list('intakes', MedIntake.fromJson),
      days: list('days', DaySummary.fromJson),
      vitals: ((j['vitals'] as Map?) ?? const {}).map((k, v) => MapEntry(
          k as String,
          MorningVitals.fromJson((v as Map).cast<String, Object?>()))),
      hiddenIdeas: ((j['hiddenIdeas'] as List?) ?? const []).cast<String>().toSet(),
      envelopeLog: ((j['envelopeLog'] as List?) ?? const []).cast<String>(),
    );
  }
}

class PacingStore {
  PacingStore([this._fileOverride]);
  final File? _fileOverride;

  Future<File> _file() async {
    if (_fileOverride != null) return _fileOverride;
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pacing.json');
  }

  Future<PacingData> load() async {
    final f = await _file();
    if (!await f.exists()) return PacingData();
    try {
      return PacingData.fromJson(
          (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>());
    } catch (_) {
      // Keep the broken file for a manual rescue instead of overwriting it.
      await f.copy('${f.path}.broken');
      return PacingData();
    }
  }

  Future<void> save(PacingData d) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(d.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  /// Pretty JSON for the export / doctor's appointment.
  String export(PacingData d) =>
      const JsonEncoder.withIndent('  ').convert(d.toJson());
}
