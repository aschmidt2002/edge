// Edge+: recovery time after training and race-time prediction.
//
// Both compute on read from stored sessions: the strain each session banked
// and the submax VO2max estimate a GPS run leaves behind.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../ui2.dart';

/// Hours until recovered after one session of [strain] (0–21).
// ponytail: one curve for everyone (about 16 h at strain 10, 72 h at 21);
// the upgrade is scaling by the user's own recovery the mornings after.
int recoveryHours(double strain) {
  if (strain <= 0) return 0;
  final s = strain.clamp(0.0, 21.0) / 21;
  return (72 * s * s).round();
}

/// Hours still left from [sessions] at [now]: the latest moment any one of
/// them is recovered from, never below zero.
int recoveryLeft(List<Map<String, dynamic>> sessions, DateTime now) {
  var until = now;
  for (final s in sessions) {
    final end = (s['end_ts'] as num?)?.toInt();
    final strain = (s['strain'] as num?)?.toDouble();
    if (end == null || strain == null) continue;
    final t = DateTime.fromMillisecondsSinceEpoch(
        (end + recoveryHours(strain) * 3600) * 1000);
    if (t.isAfter(until)) until = t;
  }
  return (until.difference(now).inMinutes / 60).ceil();
}

/// Race time in seconds for [metres] at [vo2max], from Daniels' VDOT
/// equations: oxygen cost of a pace over the fraction of VO2max sustainable
/// for that long.
double? predictRaceSeconds(double vo2max, double metres) {
  if (vo2max < 20 || vo2max > 90) return null;
  double need(double minutes) {
    final v = metres / minutes; // m/min
    final cost = -4.60 + .182258 * v + .000104 * v * v;
    final frac = .8 +
        .1894393 * math.exp(-.012778 * minutes) +
        .2989558 * math.exp(-.1932605 * minutes);
    return cost / frac;
  }

  // need() falls as time grows: bisect for need(t) == vo2max.
  var lo = metres / 500, hi = metres / 50;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (need(mid) > vo2max) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2 * 60;
}

String raceClock(double seconds) {
  final s = seconds.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// The VO2max the prediction runs on: median of the newest five estimates.
double? recentVo2max(List<Map<String, dynamic>> sessions) {
  final rows = [
    for (final s in sessions)
      if (s['vo2max_estimate'] is num && s['start_ts'] is num) s
  ]..sort((a, b) => (b['start_ts'] as num).compareTo(a['start_ts'] as num));
  final v = [for (final s in rows.take(5)) (s['vo2max_estimate'] as num).toDouble()]
    ..sort();
  if (v.isEmpty) return null;
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}

/// One card on the Activity tab: recovery left and three race predictions.
class RunInsightsCard extends StatefulWidget {
  const RunInsightsCard({super.key});

  @override
  State<RunInsightsCard> createState() => _RunInsightsCardState();
}

class _RunInsightsCardState extends State<RunInsightsCard> {
  int? _left;
  double? _vo2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<AppState>().repo;
      if (repo == null) return;
      final now = DateTime.now();
      final nowS = now.millisecondsSinceEpoch ~/ 1000;
      const day = 86400;
      final sessions = await repo.getSessions(from: nowS - 180 * day);
      final recent = [
        for (final s in sessions)
          if (((s['end_ts'] as num?) ?? 0) > nowS - 4 * day) s
      ];
      if (!mounted) return;
      setState(() {
        _left = recoveryLeft(recent, now);
        _vo2 = recentVo2max(sessions);
      });
    } catch (_) {/* goldens / no repository: the card stays empty */}
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final left = _left;
    final vo2 = _vo2;
    Widget race(String label, double metres) {
      final t = vo2 == null ? null : predictRaceSeconds(vo2, metres);
      return Expanded(
        child: Column(children: [
          Text(t == null ? '–' : raceClock(t),
              style: F.head.copyWith(color: p.ink)),
          Text(label, style: F.cap.copyWith(color: p.ink2)),
        ]),
      );
    }

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.batteryCharging, size: 20, color: p.on(C.green)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(tr(c, 'Erholungszeit', 'Recovery time'),
                style: F.body.copyWith(color: p.ink)),
          ),
          Text(
              left == null
                  ? '–'
                  : left == 0
                      ? tr(c, 'Erholt', 'Recovered')
                      : '$left h',
              style: F.head.copyWith(
                  color: left != null && left > 0 ? p.ink : p.on(C.green))),
        ]),
        Divider(color: p.line, height: S.x6),
        Row(children: [
          race('5 km', 5000),
          race('10 km', 10000),
          race(tr(c, 'Halbmarathon', 'Half marathon'), 21097.5),
        ]),
      ]),
    );
  }
}
