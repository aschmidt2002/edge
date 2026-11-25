// Edge+: what an exercise did to the body, before against after.
//
// The quiet windows either side of a breathing session (MIND-06) already
// measure the band's beats while nothing paces you. Upstream stores only the
// two RMSSDs and never shows them, on purpose: a delta at the end of a session
// is a score to chase. This fork wants exactly that comparison, so it can be
// seen which exercise settles the body best before sleep. Each finished
// session with windows writes one entry here; the screen shows the last one
// and a per-exercise average.
//
// ponytail: a JSON list in SharedPreferences, capped. It is a personal log of
// a few sessions a week, not a series anything derives from.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One session's before and after. Any reading can be missing: two minutes of
/// beats are often not enough for a breathing rate.
class WinddownEntry {
  const WinddownEntry({
    required this.at,
    required this.key,
    required this.label,
    this.preHr,
    this.postHr,
    this.preRmssd,
    this.postRmssd,
    this.preResp,
    this.postResp,
  });

  final DateTime at;

  /// The breathing pattern's key (resonance, box, cyclic_sigh …).
  final String key;
  final String label;
  final double? preHr, postHr;
  final double? preRmssd, postRmssd;
  final double? preResp, postResp;

  static double? _d(double? a, double? b) => a == null || b == null ? null : b - a;

  /// After minus before. Negative heart rate and breathing = calmer; positive
  /// RMSSD = calmer.
  double? get hrDelta => _d(preHr, postHr);
  double? get rmssdDelta => _d(preRmssd, postRmssd);
  double? get respDelta => _d(preResp, postResp);

  bool get hasAny => hrDelta != null || rmssdDelta != null || respDelta != null;

  Map<String, Object?> toJson() => {
    't': at.millisecondsSinceEpoch,
    'k': key,
    'l': label,
    'h0': preHr,
    'h1': postHr,
    'r0': preRmssd,
    'r1': postRmssd,
    'b0': preResp,
    'b1': postResp,
  };

  static double? _n(Object? v) => v is num ? v.toDouble() : null;

  static WinddownEntry? fromJson(Object? j) {
    if (j is! Map || j['t'] is! num || j['k'] is! String) return null;
    return WinddownEntry(
      at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
      key: j['k'] as String,
      label: j['l'] is String ? j['l'] as String : j['k'] as String,
      preHr: _n(j['h0']),
      postHr: _n(j['h1']),
      preRmssd: _n(j['r0']),
      postRmssd: _n(j['r1']),
      preResp: _n(j['b0']),
      postResp: _n(j['b1']),
    );
  }
}

/// The average change one exercise brought, over [count] sessions.
class WinddownRank {
  const WinddownRank(this.key, this.label, this.count, this.hr, this.rmssd, this.resp);
  final String key;
  final String label;
  final int count;
  final double? hr, rmssd, resp;
}

/// Exercises ranked by how far they brought the heart rate down, the biggest
/// drop first. An exercise with no heart-rate pair sorts last. Resonance at a
/// personal pace (resonance_5_0 …) counts as resonance.
List<WinddownRank> rankWinddown(List<WinddownEntry> entries) {
  String family(String k) => k.startsWith('resonance') ? 'resonance' : k;
  final by = <String, List<WinddownEntry>>{};
  for (final e in entries) {
    if (e.hasAny) (by[family(e.key)] ??= []).add(e);
  }
  double? mean(Iterable<double?> xs) {
    final v = [for (final x in xs) ?x];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  final out = [
    for (final MapEntry(:key, :value) in by.entries)
      WinddownRank(
        key,
        value.last.label,
        value.length,
        mean(value.map((e) => e.hrDelta)),
        mean(value.map((e) => e.rmssdDelta)),
        mean(value.map((e) => e.respDelta)),
      ),
  ];
  out.sort((a, b) {
    if (a.hr == null || b.hr == null) {
      return a.hr == null ? (b.hr == null ? 0 : 1) : -1;
    }
    return a.hr!.compareTo(b.hr!);
  });
  return out;
}

class WinddownLog {
  static const logKey = 'edge_plus_winddown_log';
  static const _cap = 120;

  /// Bumped on every write so open screens re-read.
  static final changed = ValueNotifier<int>(0);

  /// Oldest first.
  static Future<List<WinddownEntry>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(logKey);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final j in list) ?WinddownEntry.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(WinddownEntry e) async {
    if (!e.hasAny) return;
    try {
      final all = [...await load(), e];
      final kept = all.length > _cap ? all.sublist(all.length - _cap) : all;
      await (await SharedPreferences.getInstance()).setString(
        logKey,
        jsonEncode([for (final x in kept) x.toJson()]),
      );
      changed.value++;
    } catch (_) {
      /* best-effort; a lost entry is one session less in the average */
    }
  }
}
