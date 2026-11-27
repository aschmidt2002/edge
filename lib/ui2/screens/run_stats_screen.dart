// Edge+: running progress — totals, weekly distance, pace and efficiency
// trends, best efforts. Reads saved run sessions and their per-km splits.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../activity/run_coach.dart' show paceText;
import '../activity/run_stats.dart';
import '../ui2.dart';
import 'home_screen.dart' show repoOf;

const _runTypes = {'running', 'trail_running'};

/// Every saved run in the last [days] that has a distance, newest last.
Future<List<RunRecord>> loadRuns(BuildContext c, {int days = 400}) async {
  final repo = repoOf(c);
  if (repo == null) return const [];
  final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final sessions =
      await repo.getSessions(from: nowS - days * 86400, includeDetected: false);
  final out = <RunRecord>[];
  for (final s in sessions) {
    final type = (s['type'] as String? ?? '').toLowerCase();
    if (!_runTypes.contains(type)) continue;
    final id = s['id'] as String?;
    final startS = (s['start_ts'] as num?)?.toInt();
    if (id == null || startS == null) continue;
    var splits = <RunSplit>[];
    try {
      splits = [
        for (final r in await LocalDb.workoutSplits(id))
          RunSplit((r['meters'] as num).toDouble(),
              (r['duration_sec'] as num).toInt(),
              avgHr: (r['avg_hr'] as num?)?.toDouble(),
              elev: (r['net_elev_m'] as num?)?.toDouble()),
      ];
    } catch (_) {}
    double meters;
    int sec;
    if (splits.isNotEmpty) {
      meters = splits.fold(0.0, (a, b) => a + b.meters);
      sec = splits.fold(0, (a, b) => a + b.sec);
    } else {
      // No frozen splits yet: the route itself, when one was recorded.
      try {
        final route = await repo.getWorkoutRoute(id);
        if (route == null || route.distanceMeters < 200) continue;
        meters = route.distanceMeters;
        sec = route.movingSec;
        splits = [
          for (final sp in route.splitsKm)
            RunSplit(sp.meters, sp.durationSec, avgHr: sp.avgHr),
        ];
      } catch (_) {
        continue;
      }
    }
    final z = s['zone_min'];
    out.add(RunRecord(
      id: id,
      start: DateTime.fromMillisecondsSinceEpoch(startS * 1000),
      meters: meters,
      sec: sec,
      avgHr: (s['avg_hr'] as num?)?.toDouble(),
      vo2max: (s['vo2max_estimate'] as num?)?.toDouble(),
      zoneMin: z is List && z.length >= 5
          ? [for (final v in z.take(5)) ((v as num?) ?? 0).toDouble()]
          : const [],
      splits: splits,
    ));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

class RunStatsScreen extends StatefulWidget {
  /// Preloaded, for goldens.
  final List<RunRecord>? runs;
  const RunStatsScreen({super.key, this.runs});

  @override
  State<RunStatsScreen> createState() => _RunStatsScreenState();
}

class _RunStatsScreenState extends State<RunStatsScreen> {
  List<RunRecord>? runs;
  bool failed = false;
  int period = 1; // 0: 4 weeks · 1: 12 weeks · 2: year

  @override
  void initState() {
    super.initState();
    runs = widget.runs;
    if (runs == null) {
      loadRuns(context).then((r) {
        if (mounted) setState(() => runs = r);
      }, onError: (_) {
        if (mounted) setState(() => failed = true);
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(tr(c, 'Laufstatistik', 'Running stats')),
          ),
          Expanded(child: _body(c, p)),
        ]),
      ),
    );
  }

  Widget _body(BuildContext c, P p) {
    final all = runs;
    if (failed) {
      return Padding(
        padding: const EdgeInsets.all(S.x4),
        child: StatusCard(tr(c, 'Konnte Läufe nicht lesen', 'Could not read runs'),
            tr(c, 'Versuch es gleich noch einmal.', 'Try again in a moment.'),
            icon: LucideIcons.triangleAlert),
      );
    }
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(S.x4),
        child: StatusCard(
            tr(c, 'Noch keine Läufe mit GPS', 'No GPS runs yet'),
            tr(c, 'Starte einen Lauf mit Standort an. Danach siehst du hier '
                    'Kilometer, Pace, Bestzeiten und wie sich deine Ausdauer '
                    'entwickelt.',
                'Start a run with location on. Afterwards you will see '
                    'distance, pace, best efforts and how your endurance '
                    'develops.'),
            icon: LucideIcons.footprints),
      );
    }
    final now = DateTime.now();
    final days = [28, 84, 365][period];
    final from = DateTime(now.year, now.month, now.day - days);
    final inPeriod = [for (final r in all) if (r.start.isAfter(from)) r];
    final prevFrom = DateTime(from.year, from.month, from.day - days);
    final prev = [
      for (final r in all)
        if (r.start.isAfter(prevFrom) && !r.start.isAfter(from)) r
    ];
    final t = totals(inPeriod), tp = totals(prev);
    final weekly = weeklyKm(all, now, n: 12);
    final ratio = loadRatio(weekly);
    final best = bestEfforts(all);
    final recent = all.length > 30 ? all.sublist(all.length - 30) : all;
    final paces = [for (final r in recent) ?r.pace];
    final eff = [for (final r in recent) ?r.metersPerBeat];
    final vo2 = [for (final r in recent) ?r.vo2max];
    final streak = weekStreak(all, now);

    String delta(double a, double b, {bool lowerBetter = false}) {
      if (b <= 0) return '';
      final d = (a - b) / b * 100;
      if (d.abs() < 1) return '±0 %';
      return '${d > 0 ? '+' : '−'}${d.abs().round()} %';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x12),
      children: [
        SubTabs([
          tr(c, '4 Wochen', '4 weeks'),
          tr(c, '12 Wochen', '12 weeks'),
          tr(c, 'Jahr', 'Year'),
        ], period, (i) => setState(() => period = i)),
        const SizedBox(height: S.x3),
        Surface(
          child: Column(children: [
            Row(children: [
              _stat(c, p, t.km.toStringAsFixed(1), 'km',
                  delta(t.km, tp.km)),
              _stat(c, p, '${t.runs}', tr(c, 'Läufe', 'runs'),
                  delta(t.runs.toDouble(), tp.runs.toDouble())),
              _stat(c, p, fmtHours(t.sec), tr(c, 'Zeit', 'time'), ''),
            ]),
            Divider(color: p.line, height: S.x6),
            Row(children: [
              _stat(c, p, t.avgPace == null ? '–' : paceText(t.avgPace!),
                  tr(c, 'Ø Pace /km', 'avg pace /km'), ''),
              _stat(c, p, t.longestKm == null ? '–' : t.longestKm!.toStringAsFixed(1),
                  tr(c, 'längster km', 'longest km'), ''),
              _stat(c, p, t.climb == null ? '–' : '${t.climb!.round()}',
                  tr(c, 'Höhenmeter', 'climb m'), ''),
            ]),
          ]),
        ),
        const SizedBox(height: S.x3),
        Row(children: [
          Expanded(
            child: Surface(
              child: Row(children: [
                Icon(LucideIcons.flame, size: 18, color: p.on(C.orange)),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                      tr(c, '$streak Wochen in Folge gelaufen',
                          '$streak weeks in a row'),
                      style: F.cap.copyWith(color: p.ink)),
                ),
              ]),
            ),
          ),
        ]),
        if (ratio != null && ratio > 1.3) ...[
          const SizedBox(height: S.x3),
          StatusCard(
              tr(c, 'Großer Sprung im Umfang', 'Big jump in volume'),
              tr(c, 'Diese Woche ${((ratio - 1) * 100).round()} % mehr km als im '
                      'Schnitt der letzten 4 Wochen. Mehr als +30 % geht in '
                      'Studien mit mehr Verletzungen einher.',
                  'This week is ${((ratio - 1) * 100).round()} % above the last '
                      '4 weeks\' average. Jumps over 30 % come with more '
                      'injuries in studies.'),
              icon: LucideIcons.triangleAlert),
        ],
        Section(
          tr(c, 'Kilometer pro Woche', 'Distance per week'),
          _barsFrame(c, p, weekly),
        ),
        if (paces.length >= 3)
          Section(
            tr(c, 'Pace pro Lauf', 'Pace per run'),
            _lineFrame(c, p, [for (final v in paces) -v], C.blue,
                unit: '/km',
                fmt: (v) => paceText(-v),
                foot: _trendText(c, slope(paces), lowerBetter: true,
                    unit: tr(c, 's/km pro Lauf', 's/km per run'))),
          ),
        if (eff.length >= 3)
          Section(
            tr(c, 'Aerobe Effizienz', 'Aerobic efficiency'),
            _lineFrame(c, p, eff, C.green,
                unit: tr(c, 'm/Schlag', 'm/beat'),
                fmt: (v) => v.toStringAsFixed(2),
                foot: tr(
                    c,
                    'Meter pro Herzschlag. Steigt die Linie, läufst du bei '
                        'gleichem Puls schneller – deine Grundlage wird besser.',
                    'Metres per heartbeat. A rising line means faster at the '
                        'same heart rate – your base is improving.')),
          ),
        if (vo2.length >= 3)
          Section(
            tr(c, 'VO2max (Schätzung)', 'VO2max (estimate)'),
            _lineFrame(c, p, vo2, C.purple,
                unit: 'ml/kg/min',
                fmt: (v) => v.toStringAsFixed(0),
                foot: _trendText(c, slope(vo2),
                    unit: tr(c, 'pro Lauf', 'per run'))),
          ),
        if (best.isNotEmpty)
          Section(
            tr(c, 'Bestzeiten', 'Best efforts'),
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
              child: Column(children: [
                for (final b in best)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x2),
                    child: Row(children: [
                      Icon(LucideIcons.trophy, size: 18, color: p.on(C.yellow)),
                      const SizedBox(width: S.x3),
                      SizedBox(
                          width: 56,
                          child: Text(b.label,
                              style: F.body.copyWith(color: p.ink))),
                      Expanded(
                        child: Text(fmtClock(b.sec),
                            style: F.head.copyWith(color: p.ink)),
                      ),
                      Text('${b.when.day}.${b.when.month}.${b.when.year}',
                          style: F.cap.copyWith(color: p.ink3)),
                    ]),
                  ),
                const SizedBox(height: S.x1),
                Text(
                    tr(c, 'Aus aufeinanderfolgenden km-Splits deiner GPS-Läufe.',
                        'From consecutive km splits of your GPS runs.'),
                    style: F.cap.copyWith(color: p.ink3)),
              ]),
            ),
          ),
        Section(
          tr(c, 'Letzte Läufe', 'Recent runs'),
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
            child: Column(children: [
              for (final r in all.reversed.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x2),
                  child: Row(children: [
                    SizedBox(
                      width: 56,
                      child: Text('${r.start.day}.${r.start.month}.',
                          style: F.cap.copyWith(color: p.ink3)),
                    ),
                    Expanded(
                        child: Text('${(r.meters / 1000).toStringAsFixed(2)} km',
                            style: F.body.copyWith(color: p.ink))),
                    Text(r.pace == null ? '–' : '${paceText(r.pace!)} /km',
                        style: F.body.copyWith(color: p.ink2)),
                    const SizedBox(width: S.x3),
                    SizedBox(
                      width: 64,
                      child: Text(r.avgHr == null ? '' : '${r.avgHr!.round()} bpm',
                          textAlign: TextAlign.end,
                          style: F.cap.copyWith(color: p.ink3)),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  String _trendText(BuildContext c, double? s,
      {bool lowerBetter = false, required String unit}) {
    if (s == null) return '';
    final better = lowerBetter ? s < 0 : s > 0;
    if (s.abs() < .05) return tr(c, 'Gleichbleibend.', 'Steady.');
    return '${better ? tr(c, 'Wird besser', 'Improving') : tr(c, 'Wird schwächer', 'Declining')}: '
        '${s > 0 ? '+' : '−'}${s.abs().toStringAsFixed(1)} $unit';
  }

  Widget _stat(BuildContext c, P p, String v, String label, String delta) =>
      Expanded(
        child: Column(children: [
          Text(v, style: F.head.copyWith(color: p.ink)),
          Text(label, style: F.cap.copyWith(color: p.ink3)),
          if (delta.isNotEmpty)
            Text(delta,
                style: F.cap.copyWith(
                    color: delta.startsWith('+')
                        ? p.on(C.green)
                        : delta.startsWith('−')
                            ? p.on(C.orange)
                            : p.ink3)),
        ]),
      );

  Widget _barsFrame(BuildContext c, P p, List<double> weekly) {
    final mx = weekly.fold<double>(0, (a, b) => a > b ? a : b);
    final axis = AxisSpec(
        min: 0,
        max: mx <= 0 ? 10 : (mx / 5).ceil() * 5.0,
        format: (v) => v.round().toString());
    final now = DateTime.now();
    final first = weekStart(now);
    String lab(int i) {
      final d = DateTime(first.year, first.month, first.day - 7 * (11 - i));
      return '${d.day}.${d.month}.';
    }

    return ChartFrame(
      title: tr(c, 'Letzte 12 Wochen', 'Last 12 weeks'),
      unit: 'km',
      height: 130,
      yAxis: axis,
      xLabels: [lab(0), lab(6), lab(11)],
      series: weekly,
      child: CustomPaint(
          size: Size.infinite,
          painter: Bars(weekly, p.on(C.green), axis: axis, highlight: 11)),
    );
  }

  Widget _lineFrame(BuildContext c, P p, List<double> ys, Color col,
      {required String unit,
      required String Function(double) fmt,
      String foot = ''}) {
    final lo = ys.reduce((a, b) => a < b ? a : b);
    final hi = ys.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo).abs() < 1e-6 ? (hi.abs() * .05 + .1) : (hi - lo) * .15;
    final axis = AxisSpec(min: lo - pad, max: hi + pad, format: fmt);
    return ChartFrame(
      title: tr(c, 'Letzte ${ys.length} Läufe', 'Last ${ys.length} runs'),
      unit: unit,
      height: 120,
      yAxis: axis,
      series: ys,
      footnote: foot.isEmpty ? null : foot,
      child: CustomPaint(
          size: Size.infinite,
          painter: LineChart(ys, p.on(col), dots: true, dotInk: p.card, axis: axis)),
    );
  }
}
