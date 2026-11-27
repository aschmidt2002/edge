// Edge+: what a run adds to the live screen — the numbers Strava shows while
// you run (current pace, last split, current split) and, when the run was
// started from the coach, the workout step you are in with its target zone.
//
// The band does the talking: a buzz at every kilometre (if wanted), at each
// step change, and when heart rate sits outside the target zone for a while.
// Buzzes go through `AppState.buzzBand`, which never throws; the phone gives a
// haptic too, for runs without the band in reach.
//
// Kilometre marks and the guide live in the session's LiveDraft, so they
// survive minimising the live screen and an app relaunch mid-run.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../state/units_controller.dart';
import '../ui2.dart';
import '../screens/home_screen.dart' show unitsOf;
import 'live.dart';
import 'run_coach.dart';
import 'summary.dart' show clock;

/// Draft keys.
const kRunGuideKey = 'run_guide';
const kRunGuidePlanKey = 'run_guide_plan_key';
const kRunPlannedRouteKey = 'run_planned_route';
const _kKmMarksKey = 'run_km_marks';

/// Buzz at every km. Default on: it is what a running watch does.
const kRunKmBuzzPref = 'edgeplus.run_km_buzz';

/// Where [elapsed] sits in [steps]: the step index and seconds into it.
/// Past the end returns the last index with `over` true.
({int i, int into, bool over}) stepAt(List<RunStep> steps, int elapsed) {
  var t = 0;
  for (var i = 0; i < steps.length; i++) {
    if (elapsed < t + steps[i].sec) return (i: i, into: elapsed - t, over: false);
    t += steps[i].sec;
  }
  return (i: steps.length - 1, into: steps.last.sec, over: true);
}

/// Whether to warn about the zone: −1 too low, +1 too high, 0 fine/unknown.
/// Warm-up, cool-down and rests only warn when far too high. Work steps give
/// heart rate [lag] seconds to arrive before any warning.
int zoneVerdict(RunStep s, int into, int? zone, {int lag = 90}) {
  if (!s.guided || zone == null) return 0;
  if (zone > s.zHi!) {
    if (s.kind == 'work' || s.kind == 'steady') return into >= 45 ? 1 : 0;
    return zone >= s.zHi! + 2 ? 1 : 0;
  }
  if (zone < s.zLo!) {
    if (s.kind == 'steady' && into >= 180) return -1;
    if (s.kind == 'work' && into >= lag) return -1;
  }
  return 0;
}

class RunLivePanel extends StatefulWidget {
  final LiveFeed feed;
  final int elapsed;
  final Color color;
  const RunLivePanel(
      {super.key,
      required this.feed,
      required this.elapsed,
      this.color = C.green});

  @override
  State<RunLivePanel> createState() => _RunLivePanelState();
}

class _RunLivePanelState extends State<RunLivePanel> {
  RunWorkout? _guide;
  ({String name, double m})? _planned;
  List<int> _marks = []; // elapsed seconds at each completed km
  int _lastStep = -1;
  int _offSince = -1; // elapsed when HR first left the zone, -1 = in zone
  int _lastWarnAt = -1000;
  bool _kmBuzz = true;

  @override
  void initState() {
    super.initState();
    final d = LiveDraft.current;
    _guide = RunWorkout.fromJson(d?.data[kRunGuideKey]);
    final pr = d?.data[kRunPlannedRouteKey];
    if (pr is Map && pr['m'] is num) {
      _planned = (name: pr['name'] as String? ?? '', m: (pr['m'] as num).toDouble());
    }
    final m = d?.data[_kKmMarksKey];
    if (m is List) _marks = [for (final v in m) if (v is num) v.toInt()];
    _kmBuzz = Prefs.getBool(kRunKmBuzzPref, true);
    if (_guide != null) {
      _lastStep = stepAt(_guide!.steps, widget.elapsed).i;
    }
  }

  void _buzz({int times = 1}) {
    HapticFeedback.heavyImpact();
    try {
      final app = context.read<AppState>();
      unawaited(() async {
        for (var i = 0; i < times; i++) {
          if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 700));
          await app.buzzBand();
        }
      }());
    } catch (_) {/* no provider in goldens */}
  }

  @override
  void didUpdateWidget(RunLivePanel old) {
    super.didUpdateWidget(old);
    final e = widget.elapsed;
    if (e == old.elapsed) return;
    // Kilometre marks.
    final km = widget.feed.distanceKm;
    if (km != null && km.floor() > _marks.length) {
      while (_marks.length < km.floor()) {
        _marks.add(e);
      }
      LiveDraft.current?.put(_kKmMarksKey, List<int>.of(_marks));
      if (_kmBuzz) _buzz();
    }
    final g = _guide;
    if (g == null) return;
    final at = stepAt(g.steps, e);
    if (at.i != _lastStep && !at.over) {
      _lastStep = at.i;
      _offSince = -1;
      _buzz(times: 2);
    }
    if (at.over) return;
    final v = zoneVerdict(g.steps[at.i], at.into, widget.feed.zone);
    if (v == 0) {
      _offSince = -1;
    } else {
      if (_offSince < 0) _offSince = e;
      // Out of zone for 20 s, then at most once a minute.
      if (e - _offSince >= 20 && e - _lastWarnAt >= 60) {
        _lastWarnAt = e;
        _buzz(times: v > 0 ? 3 : 1);
      }
    }
  }


  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final u = unitsOf(c);
    final f = widget.feed;
    final e = widget.elapsed;
    final unit = u?.distanceUnit ?? 'km';
    double perUnit(double m) => u == null ? m / 1000 : u.distanceValue(m);

    // Current pace from the tracker's smoothed speed.
    double? speed;
    try {
      speed = context.read<AppState>().routeTracker?.currentSpeedMps.value;
    } catch (_) {}
    final cur = speed == null || speed < .5
        ? null
        : UnitsController.formatPace(1 / perUnit(speed));
    String? lastSplit;
    if (_marks.isNotEmpty && unit == 'km') {
      final prev = _marks.length >= 2 ? _marks[_marks.length - 2] : 0;
      lastSplit = UnitsController.formatPace((_marks.last - prev).toDouble());
    }
    final km = f.distanceKm;
    String? thisSplit;
    if (km != null && unit == 'km') {
      final into = km - km.floor();
      final startE = _marks.isEmpty ? 0 : _marks.last;
      if (into > .05) {
        thisSplit = UnitsController.formatPace((e - startE) / into);
      }
    }

    final stats = <(String, String)>[
      if (cur != null) (cur, tr(c, 'Pace jetzt', 'Pace now')),
      if (thisSplit != null)
        (thisSplit, tr(c, 'Pace km ${_marks.length + 1}', 'Pace km ${_marks.length + 1}')),
      if (lastSplit != null)
        (lastSplit, tr(c, 'km ${_marks.length}', 'km ${_marks.length}')),
    ];

    final planned = _planned;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (stats.isNotEmpty) ...[
        const SizedBox(height: S.x5),
        statRow(p, stats),
      ],
      if (planned != null && km != null) ...[
        const SizedBox(height: S.x4),
        _plannedRow(c, p, planned, km),
      ],
      if (_guide != null) ...[
        const SizedBox(height: S.x5),
        _guideCard(c, p, _guide!, e),
      ],
      const SizedBox(height: S.x3),
      Center(
        child: Pressable(
          semanticLabel: tr(c, 'Vibration pro km', 'Buzz each km'),
          onTap: () {
            setState(() => _kmBuzz = !_kmBuzz);
            Prefs.setBool(kRunKmBuzzPref, _kmBuzz);
          },
          child: Padding(
            padding: const EdgeInsets.all(S.x2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_kmBuzz ? LucideIcons.vibrate : LucideIcons.vibrateOff,
                  size: 14, color: p.ink3),
              const SizedBox(width: S.x1),
              Flexible(
                child: Text(
                    _kmBuzz
                        ? tr(c, 'Band vibriert jeden km', 'Band buzzes every km')
                        : tr(c, 'km-Vibration aus', 'km buzz off'),
                    style: F.cap.copyWith(color: p.ink3)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _plannedRow(BuildContext c, P p, ({String name, double m}) r, double km) {
    final left = r.m / 1000 - km;
    final frac = (km * 1000 / r.m).clamp(0.0, 1.0);
    return Surface(
      pad: const EdgeInsets.all(S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.route, size: 16, color: p.on(widget.color)),
          const SizedBox(width: S.x2),
          Expanded(
              child: Text(r.name.isEmpty ? tr(c, 'Geplante Route', 'Planned route') : r.name,
                  style: F.cap.copyWith(color: p.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          Text(
              left > 0
                  ? tr(c, 'noch ${left.toStringAsFixed(1)} km',
                      '${left.toStringAsFixed(1)} km to go')
                  : tr(c, 'Ziel erreicht', 'Done'),
              style: F.cap.copyWith(color: p.ink)),
        ]),
        const SizedBox(height: S.x2),
        ClipRRect(
          borderRadius: R.rPill,
          child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: p.card2,
              color: p.on(widget.color)),
        ),
      ]),
    );
  }

  Widget _guideCard(BuildContext c, P p, RunWorkout g, int e) {
    final at = stepAt(g.steps, e);
    final s = g.steps[at.i];
    final left = s.sec - at.into;
    final de = Localizations.localeOf(c).languageCode == 'de';
    final v = at.over ? 0 : zoneVerdict(s, at.into, widget.feed.zone);
    final next = at.i + 1 < g.steps.length ? g.steps[at.i + 1] : null;
    final zone = widget.feed.zone;
    final (msg, col) = at.over
        ? (tr(c, 'Workout geschafft – locker auslaufen', 'Workout done – jog it out'), C.green)
        : v > 0
            ? (tr(c, 'Langsamer – über der Zielzone', 'Slow down – above target'), C.orange)
            : v < 0
                ? (tr(c, 'Etwas schneller – unter der Zielzone', 'A bit faster – below target'), C.blue)
                : s.guided && zone != null && zone >= s.zLo! && zone <= s.zHi!
                    ? (tr(c, 'Genau richtig', 'Right on target'), C.green)
                    : (null, C.green);
    return Surface(
      color: p.wash(col),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.target, size: 18, color: p.on(col)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(
                '${tr(c, 'Schritt', 'Step')} ${at.i + 1}/${g.steps.length} · '
                '${de ? s.de : s.en}',
                style: F.body.copyWith(color: p.ink)),
          ),
          if (!at.over)
            Text(clock(left), style: F.head.copyWith(color: p.ink)),
        ]),
        if (s.guided) ...[
          const SizedBox(height: S.x2),
          Row(children: [
            for (var z = 1; z <= 5; z++) ...[
              if (z > 1) const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: R.rSm,
                    color: z >= s.zLo! && z <= s.zHi!
                        ? p.on(col)
                        : p.card2,
                    border: zone == z
                        ? Border.all(color: p.ink, width: 2)
                        : null,
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: S.x1),
          Text(
              '${tr(c, 'Ziel', 'Target')}: Zone ${s.zLo}${s.zHi != s.zLo ? '–${s.zHi}' : ''}'
              '${zone == null ? '' : ' · ${tr(c, 'jetzt', 'now')} Zone $zone'}',
              style: F.cap.copyWith(color: p.ink2)),
        ] else ...[
          const SizedBox(height: S.x1),
          Text(tr(c, 'Nach Gefühl – der Puls kommt hier nicht hinterher.',
                  'By feel – heart rate cannot keep up here.'),
              style: F.cap.copyWith(color: p.ink2)),
        ],
        if (msg != null) ...[
          const SizedBox(height: S.x2),
          Text(msg, style: F.body.copyWith(color: p.on(col))),
        ],
        if (next != null && !at.over) ...[
          const SizedBox(height: S.x1),
          Text('${tr(c, 'Danach', 'Next')}: ${de ? next.de : next.en} · ${clock(next.sec)}',
              style: F.cap.copyWith(color: p.ink3)),
        ],
      ]),
    );
  }
}
