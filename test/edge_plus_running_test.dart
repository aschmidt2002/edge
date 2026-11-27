// Edge+: running coach, live guide, stats and route planner — the pure parts.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openstrap_edge/gps/route_planner.dart';
import 'package:openstrap_edge/ui2/activity/run_coach.dart';
import 'package:openstrap_edge/ui2/activity/run_live_panel.dart';
import 'package:openstrap_edge/ui2/activity/run_stats.dart';

void main() {
  group('run coach plan', () {
    RunPlanConfig cfg(RunGoal g,
            {int weeks = 12, int perWeek = 4, RunLevel l = RunLevel.intermediate}) =>
        RunPlanConfig(
            goal: g,
            level: l,
            weeks: weeks,
            perWeek: perWeek,
            start: DateTime(2026, 11, 23));

    test('every week has the asked number of runs, no two hard days in a row',
        () {
      for (final g in RunGoal.values) {
        for (final n in [3, 4, 5, 6]) {
          final plan = buildPlan(cfg(g, perWeek: n));
          expect(plan.length, 12);
          for (final w in plan) {
            expect(w.runs.length, n);
            final hard = [
              for (final r in w.runs)
                if (r.workout.quality) r.weekday
            ]..sort();
            for (var i = 1; i < hard.length; i++) {
              expect(hard[i] - hard[i - 1], greaterThan(1),
                  reason: '$g $n week ${w.index}');
            }
          }
        }
      }
    });

    test('mostly easy: at most two quality sessions per week', () {
      for (final g in RunGoal.values) {
        for (final w in buildPlan(cfg(g, perWeek: 6))) {
          expect(w.runs.where((r) => r.workout.quality).length,
              lessThanOrEqualTo(2));
        }
      }
    });

    test('distance decides the key session', () {
      List<RunKind> kinds(RunGoal g) => [
            for (final w in buildPlan(cfg(g)))
              for (final r in w.runs) r.workout.kind
          ];
      final k5 = kinds(RunGoal.k5), mar = kinds(RunGoal.marathon);
      expect(k5.where((k) => k == RunKind.vo2).length,
          greaterThan(mar.where((k) => k == RunKind.vo2).length));
      expect(mar.where((k) => k == RunKind.tempo).length,
          greaterThan(k5.where((k) => k == RunKind.tempo).length));
    });

    test('long runs grow, the easier week and taper step back, race last', () {
      final plan = buildPlan(cfg(RunGoal.half, weeks: 12));
      int longSec(RunWeek w) => w.runs.last.workout.totalSec;
      expect(longSec(plan[6]), greaterThan(longSec(plan[0])));
      expect(plan[3].deload, isTrue);
      expect(longSec(plan[3]), lessThan(longSec(plan[2])));
      expect(plan.last.phase, RunPhase.taper);
      expect(plan.last.runs.last.workout.kind, RunKind.race);
    });

    test('config and workout survive a JSON round trip', () {
      final c = cfg(RunGoal.k10).copyWith(done: {'0-2', '1-7'});
      final back = RunPlanConfig.fromJson(jsonDecode(jsonEncode(c.toJson())))!;
      expect(back.goal, RunGoal.k10);
      expect(back.done, {'0-2', '1-7'});
      expect(back.start, DateTime(2026, 11, 23));
      final w = buildWorkout(RunKind.vo2, RunGoal.k5);
      final w2 = RunWorkout.fromJson(jsonDecode(jsonEncode(w.toJson())))!;
      expect(w2.totalSec, w.totalSec);
      expect(w2.steps.length, w.steps.length);
    });

    test('week index counts calendar days across DST', () {
      final c = RunPlanConfig(
          goal: RunGoal.k5,
          level: RunLevel.beginner,
          weeks: 8,
          perWeek: 3,
          start: DateTime(2026, 3, 23));
      expect(weekIndexOf(c, DateTime(2026, 3, 30, 0, 30)), 1);
      expect(weekIndexOf(c, DateTime(2026, 3, 22)), isNull);
      expect(weekIndexOf(c, DateTime(2026, 5, 18)), isNull);
    });

    test('low recovery swaps a hard day, an easy day is never touched', () {
      final hard = buildWorkout(RunKind.threshold, RunGoal.k10);
      final easy = buildWorkout(RunKind.easy, RunGoal.k10);
      expect(adviseToday(hard, 20, null)!.swap, isTrue);
      expect(adviseToday(hard, 50, null)!.swap, isFalse);
      expect(adviseToday(hard, 80, null), isNull);
      expect(adviseToday(easy, 10, 40), isNull);
    });

    test('Daniels paces: faster with a higher VO2max, none without one', () {
      // VDOT 50: threshold about 4:15/km, easy around 5:00-5:40/km.
      final t = paceBand(50, 4, 4)!;
      expect(t.fast, inInclusiveRange(240, 265));
      final e = paceBand(50, 2, 2)!;
      expect(e.slow, greaterThan(t.slow));
      expect(paceBand(55, 4, 4)!.fast, lessThan(t.fast));
      expect(paceBand(null, 4, 4), isNull);
      expect(paceBand(50, null, null), isNull);
    });
  });

  group('live guide', () {
    final steps = [
      const RunStep('warm', 600, 1, 2, '', ''),
      const RunStep('work', 180, 4, 5, '', ''),
      const RunStep('rest', 120, null, null, '', ''),
    ];

    test('stepAt walks the steps by elapsed time', () {
      expect(stepAt(steps, 0).i, 0);
      expect(stepAt(steps, 600).i, 1);
      expect(stepAt(steps, 650).into, 50);
      expect(stepAt(steps, 900).over, isTrue);
    });

    test('zone warnings wait for heart rate to arrive', () {
      final work = steps[1];
      expect(zoneVerdict(work, 30, 2), 0); // still climbing
      expect(zoneVerdict(work, 100, 2), -1);
      expect(zoneVerdict(work, 100, 4), 0);
      expect(zoneVerdict(work, 100, null), 0);
      expect(zoneVerdict(steps[0], 100, 3), 0); // warm-up: only far too high
      expect(zoneVerdict(steps[0], 100, 4), 1);
      expect(zoneVerdict(steps[2], 100, 5), 0); // rest has no target
    });
  });

  group('run stats', () {
    RunRecord run(DateTime d, List<int> kmSecs, {double hr = 150}) => RunRecord(
          id: '${d.millisecondsSinceEpoch}',
          start: d,
          meters: kmSecs.length * 1000.0,
          sec: kmSecs.fold(0, (a, b) => a + b),
          splits: [for (final s in kmSecs) RunSplit(1000, s, avgHr: hr)],
        );

    test('best efforts come from consecutive full km', () {
      final a = run(DateTime(2026, 11, 1), [300, 280, 290, 300, 310, 320]);
      final b = run(DateTime(2026, 11, 8), [270, 400]);
      final best = bestEfforts([a, b]);
      expect(best.firstWhere((x) => x.label == '1 km').sec, 270);
      expect(best.firstWhere((x) => x.label == '5 km').sec, 1480);
      expect(best.where((x) => x.label == '10 km'), isEmpty);
    });

    test('weekly km and the volume jump', () {
      final now = DateTime(2026, 11, 27); // a Friday
      final runs = [
        for (var w = 1; w <= 4; w++)
          run(DateTime(now.year, now.month, now.day - 7 * w), List.filled(10, 330)),
        run(DateTime(2026, 11, 24), List.filled(15, 330)),
      ];
      final wk = weeklyKm(runs, now);
      expect(wk.length, 12);
      expect(wk.last, 15);
      expect(wk[10], 10);
      expect(loadRatio(wk), closeTo(1.5, 1e-9));
      expect(weekStreak(runs, now), 5);
    });

    test('efficiency rises when the same pace costs fewer beats', () {
      final a = run(DateTime(2026, 10, 1), [330, 330], hr: 160);
      final b = run(DateTime(2026, 11, 1), [330, 330], hr: 150);
      expect(b.metersPerBeat!, greaterThan(a.metersPerBeat!));
      final noHr = RunRecord(
          id: 'x', start: DateTime(2026), meters: 2000, sec: 660,
          splits: const [RunSplit(1000, 330), RunSplit(1000, 330)]);
      expect(noHr.metersPerBeat, isNull);
    });
  });

  group('route planner', () {
    test('running time adds one km per 100 m of climb', () {
      expect(runSeconds(10000, 0, 360), 3600);
      expect(runSeconds(10000, 200, 360), 3600 + 720);
    });

    test('hiking time after DIN 33466', () {
      // 12 km flat at 4 km/h: 3 h.
      expect(hikeSeconds(12000, 0, 0), closeTo(3 * 3600, 1e-6));
      // 8 km, 600 m up, 600 m down: h = 2 h, v = 2 + 1.2 = 3.2 h → 3.2 + 1.
      expect(hikeSeconds(8000, 600, 600), closeTo(4.2 * 3600, 1e-6));
    });

    test('climb ignores small wiggles', () {
      final c = climbOf([100, 102, 99, 101, 120, 118, 140, 130, 100]);
      expect(c.up, closeTo(40, 1e-9));
      expect(c.down, closeTo(40, 1e-9));
    });

    test('BRouter GeoJSON gives points and elevation', () {
      final body = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'track-length': '120'},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [8.0, 50.0, 100.0],
                [8.001, 50.0, 110.0],
              ]
            }
          }
        ]
      });
      final r = parseBrouter(body)!;
      expect(r.pts.first, const LatLng(50.0, 8.0));
      expect(r.elev, [100.0, 110.0]);
      expect(parseBrouter('not json'), isNull);
      final uri = brouterUri(const [LatLng(50, 8), LatLng(50.1, 8.1)]);
      expect(uri.host, 'brouter.de');
      expect(uri.queryParameters['lonlats'], '8.000000,50.000000|8.100000,50.100000');
    });

    test('Overpass trails list and stitched geometry', () {
      final list = parseTrails(jsonEncode({
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'name': 'Rheinsteig', 'route': 'hiking', 'network': 'rwn', 'distance': '320 km'},
            'center': {'lat': 50.0, 'lon': 7.6},
          },
          {
            'type': 'relation',
            'id': 2,
            'tags': {'name': 'Laufpark', 'route': 'running', 'network': 'lwn', 'distance': '5,5'},
          },
          {'type': 'relation', 'id': 3, 'tags': {'route': 'hiking'}},
        ]
      }));
      expect(list.map((t) => t.name), ['Laufpark', 'Rheinsteig']);
      expect(list.first.km, 5.5);
      expect(list.last.km, 320);

      // Second way is stored backwards; stitching flips it.
      final geom = parseTrailGeometry(jsonEncode({
        'elements': [
          {
            'type': 'relation',
            'id': 2,
            'members': [
              {
                'type': 'way',
                'geometry': [
                  {'lat': 50.0, 'lon': 8.0},
                  {'lat': 50.0, 'lon': 8.001},
                ]
              },
              {
                'type': 'way',
                'geometry': [
                  {'lat': 50.0, 'lon': 8.002},
                  {'lat': 50.0, 'lon': 8.001},
                ]
              },
            ]
          }
        ]
      }));
      expect(geom.map((p) => p.longitude), [8.0, 8.001, 8.001, 8.002]);
    });

    test('planned route JSON and GPX', () {
      const r = PlannedRoute(
          id: '1',
          name: 'A & B',
          points: [LatLng(50, 8), LatLng(50.01, 8.01)],
          meters: 1340,
          up: 12);
      final back = PlannedRoute.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(back.points.length, 2);
      expect(back.up, 12);
      final gpx = buildPlannedGpx(r);
      expect(gpx, contains('<name>A &amp; B</name>'));
      expect('<rtept'.allMatches(gpx).length, 2);
    });

    test('thin keeps both ends and drops near-duplicates', () {
      final pts = [for (var i = 0; i <= 100; i++) LatLng(50, 8 + i * 1e-5)];
      final t = thin(pts);
      expect(t.first, pts.first);
      expect(t.last, pts.last);
      expect(t.length, lessThan(pts.length));
    });
  });
}
