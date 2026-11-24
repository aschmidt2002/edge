// EXPERIMENTELL — shared bits for the Edge+ experiments.
//
// Every experiment reads what the app already stores (day results, metric
// series, decoded beats, strength sets) and computes on read. Nothing here
// writes to the analytics tables; settings live in Prefs under `xp.`.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';

/// German or English, by the app's current locale.
String tr(BuildContext c, String de, String en) =>
    Localizations.localeOf(c).languageCode == 'de' ? de : en;

LocalRepository? xpRepo(BuildContext c) {
  try {
    return c.read<AppState>().repo;
  } catch (_) {
    return null;
  }
}

/// A Metric-shaped map (`{value: …}`), a bare number, or nothing.
double? mv(Object? m) {
  final v = m is Map ? m['value'] : m;
  return v is num ? v.toDouble() : null;
}

/// One stored daily series, oldest first. `getChart` stamps each day at noon.
Future<List<(DateTime, double)>> xpSeries(LocalRepository repo, String key,
    {int days = 30}) async {
  final from = DateTime.now().subtract(Duration(days: days));
  try {
    final chart = await repo.getChart(key);
    final pts = chart['points'];
    if (pts is! List) return const [];
    final out = <(DateTime, double)>[];
    for (final p in pts) {
      if (p is! Map) continue;
      final t = p['t'], v = p['v'];
      if (t is! num || v is! num) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(t.toInt() * 1000);
      if (d.isAfter(from)) out.add((d, v.toDouble()));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  } catch (_) {
    return const [];
  }
}

double? avgOf(Iterable<double> xs) =>
    xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

double? medianOf(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

// ── beats → stress ───────────────────────────────────────────────────────────

/// One window of beats: mean heart rate and RMSSD.
class BeatWindow {
  final DateTime start;
  final double hr, rmssd;
  const BeatWindow(this.start, this.hr, this.rmssd);
}

/// Stored beats between two instants, cut into [window] slices. Beats outside
/// 300–2000 ms or more than 20 % off their neighbour are dropped; a slice with
/// fewer than 60 clean beats is skipped rather than guessed.
Future<List<BeatWindow>> beatWindows(DateTime from, DateTime to,
    {Duration window = const Duration(minutes: 10)}) async {
  final rows = await LocalDb.decodedRrByRecTsRange(
    fromRecTs: from.millisecondsSinceEpoch ~/ 1000,
    toRecTs: to.millisecondsSinceEpoch ~/ 1000,
  );
  final out = <BeatWindow>[];
  final winMs = window.inMilliseconds;
  int? slot;
  var rr = <double>[];
  void flush() {
    if (slot == null || rr.length < 60) return;
    final clean = <double>[];
    for (final v in rr) {
      if (v < 300 || v > 2000) continue;
      if (clean.isNotEmpty && (v - clean.last).abs() > clean.last * .2) continue;
      clean.add(v);
    }
    if (clean.length < 60) return;
    var ss = 0.0;
    for (var i = 1; i < clean.length; i++) {
      final d = clean[i] - clean[i - 1];
      ss += d * d;
    }
    final rmssd = math.sqrt(ss / (clean.length - 1));
    final hr = 60000 / avgOf(clean)!;
    out.add(BeatWindow(
        DateTime.fromMillisecondsSinceEpoch(slot * winMs), hr, rmssd));
  }

  for (final r in rows) {
    final t = (r['beat_ts_ms'] as num?) ?? (r['rr_ts_ms'] as num?);
    final v = r['rr_ms'] as num?;
    if (t == null || v == null) continue;
    final s = t.toInt() ~/ winMs;
    if (s != slot) {
      flush();
      slot = s;
      rr = [];
    }
    rr.add(v.toDouble());
  }
  flush();
  return out;
}

/// Stress on WHOOP's 0–3 scale from one window against a calm reference:
/// lower HRV and higher pulse than the reference both push it up.
// ponytail: a linear blend of two ratios, not a validated model. Movement is
// not removed, so a walk reads as stress; the upgrade is gating on the IMU.
double stressScore(
    {required double hr,
    required double rmssd,
    required double refHr,
    required double refRmssd}) {
  final hrv = (1 - rmssd / refRmssd).clamp(0.0, 1.0);
  final pulse = ((hr - refHr) / refHr / .4).clamp(0.0, 1.0);
  return (3 * (.6 * hrv + .4 * pulse)).clamp(0.0, 3.0);
}

String stressWord(BuildContext c, double s) => s < 1
    ? tr(c, 'Niedrig', 'Low')
    : s < 2
        ? tr(c, 'Mittel', 'Medium')
        : tr(c, 'Hoch', 'High');

Color stressColor(double s) => s < 1
    ? const Color(0xFF22C55E)
    : s < 2
        ? const Color(0xFFEAB308)
        : const Color(0xFFEF4444);

// ── settings ────────────────────────────────────────────────────────────────

Map<String, dynamic> xpGet(String key) {
  try {
    final v = jsonDecode(Prefs.getString('xp.$key', '{}'));
    return v is Map ? v.cast<String, dynamic>() : {};
  } catch (_) {
    return {};
  }
}

void xpSet(String key, Map<String, dynamic> value) =>
    Prefs.setString('xp.$key', jsonEncode(value));

String two(int n) => n.toString().padLeft(2, '0');
String clock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
String hmText(num minutes) {
  final m = minutes.round();
  return '${m ~/ 60}h ${two(m % 60)}m';
}
