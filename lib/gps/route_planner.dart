// Edge+: planning a run or hike on the map — distance, climb and how long it
// takes at your pace; snapping to paths and listing marked trails nearby.
//
// NETWORK, OPT-IN. Unlike recorded routes (which never leave the phone), the
// planner asks three public OpenStreetMap services, and only after the user
// switched it on in the planner (see [kPlannerNetConsent]):
//   · map tiles (tile.openstreetmap.org / OpenTopoMap / Waymarked Trails),
//   · BRouter (brouter.de) to follow paths between the points you tap,
//   · Overpass (overpass-api.de) to list marked hiking/running routes around
//     the visible map.
// Each request sends coordinates of the area you are looking at, nothing else.
//
// Time estimates:
//   · Running: "effort kilometres" = km + climb/100 (1 km per 100 m up, the
//     ITRA rule of thumb), times your pace.
//   · Hiking: DIN 33466 — 4 km/h on the flat, 300 m/h up, 500 m/h down; the
//     larger of horizontal and vertical time plus half the smaller.

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../state/prefs.dart';
import 'route_math.dart' show haversineMeters;

const kPlannerNetConsent = 'edgeplus.route_planner_net';
const kPlannerRoutesKey = 'edgeplus.planned_routes.v1';
const _ua = 'OpenStrap-edge/1.0 (+https://github.com/OpenStrap/edge)';

bool get plannerNetAllowed => Prefs.getBool(kPlannerNetConsent, false);
void setPlannerNetAllowed(bool on) => Prefs.setBool(kPlannerNetConsent, on);

/// Total length of [pts] in metres.
double pathMeters(List<LatLng> pts) {
  var m = 0.0;
  for (var i = 1; i < pts.length; i++) {
    m += haversineMeters(pts[i - 1].latitude, pts[i - 1].longitude,
        pts[i].latitude, pts[i].longitude);
  }
  return m;
}

/// Climb and descent from an elevation profile, ignoring wiggles smaller than
/// [deadband] metres (DEM noise).
({double up, double down}) climbOf(List<double> elev, {double deadband = 5}) {
  if (elev.length < 2) return (up: 0, down: 0);
  var up = 0.0, down = 0.0;
  var ref = elev.first;
  for (final e in elev.skip(1)) {
    final d = e - ref;
    if (d >= deadband) {
      up += d;
      ref = e;
    } else if (d <= -deadband) {
      down -= d;
      ref = e;
    }
  }
  return (up: up, down: down);
}

/// Running time in seconds at [paceSecPerKm] on the flat.
double runSeconds(double meters, double climbM, double paceSecPerKm) =>
    (meters / 1000 + climbM / 100) * paceSecPerKm;

/// Hiking time in seconds after DIN 33466. [kmh] is the flat speed.
double hikeSeconds(double meters, double up, double down, {double kmh = 4}) {
  final h = meters / 1000 / kmh; // hours
  final v = up / 300 + down / 500;
  return (math.max(h, v) + math.min(h, v) / 2) * 3600;
}

class PlannedRoute {
  final String id;
  final String name;
  final List<LatLng> points;
  final double meters;
  final double? up, down;
  final String kind; // run · hike

  const PlannedRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.meters,
    this.up,
    this.down,
    this.kind = 'run',
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'm': meters,
        'up': up,
        'down': down,
        // 5 decimals ≈ 1 m: plenty, and a third of the bytes.
        'pts': [
          for (final p in points)
            [
              double.parse(p.latitude.toStringAsFixed(5)),
              double.parse(p.longitude.toStringAsFixed(5))
            ]
        ],
      };

  static PlannedRoute? fromJson(Object? j) {
    if (j is! Map) return null;
    final pts = <LatLng>[
      for (final e in (j['pts'] as List? ?? const []))
        if (e is List && e.length >= 2)
          LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()),
    ];
    if (pts.length < 2) return null;
    return PlannedRoute(
      id: '${j['id'] ?? ''}',
      name: j['name'] as String? ?? '',
      points: pts,
      meters: (j['m'] as num?)?.toDouble() ?? pathMeters(pts),
      up: (j['up'] as num?)?.toDouble(),
      down: (j['down'] as num?)?.toDouble(),
      kind: j['kind'] as String? ?? 'run',
    );
  }
}

class PlannedRouteStore {
  PlannedRouteStore._();

  static List<PlannedRoute> load() {
    final raw = Prefs.getString(kPlannerRoutesKey, '');
    if (raw.isEmpty) return [];
    try {
      final l = jsonDecode(raw);
      if (l is! List) return [];
      return [for (final e in l) ?PlannedRoute.fromJson(e)];
    } catch (_) {
      return [];
    }
  }

  static void _save(List<PlannedRoute> r) => Prefs.setString(
      kPlannerRoutesKey, jsonEncode([for (final x in r) x.toJson()]));

  static void put(PlannedRoute r) {
    final all = load()..removeWhere((x) => x.id == r.id);
    _save([r, ...all]);
  }

  static void remove(String id) => _save(load()..removeWhere((x) => x.id == id));
}

/// Fewer points for storage: drop points closer than [minM] to the last kept.
List<LatLng> thin(List<LatLng> pts, {double minM = 8, int max = 1500}) {
  if (pts.length <= 2) return pts;
  var d = minM;
  while (true) {
    final out = [pts.first];
    for (final p in pts.skip(1)) {
      final l = out.last;
      if (haversineMeters(l.latitude, l.longitude, p.latitude, p.longitude) >= d) {
        out.add(p);
      }
    }
    if (out.last != pts.last) out.add(pts.last);
    if (out.length <= max) return out;
    d *= 1.5;
  }
}

String buildPlannedGpx(PlannedRoute r) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="OpenStrap" '
        'xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <rte><name>${esc(r.name)}</name>');
  for (final p in r.points) {
    b.writeln('    <rtept lat="${p.latitude.toStringAsFixed(6)}" '
        'lon="${p.longitude.toStringAsFixed(6)}"/>');
  }
  b
    ..writeln('  </rte>')
    ..writeln('</gpx>');
  return b.toString();
}

// ─────────────── BRouter: follow paths ───────────────

/// The profile per activity. `hiking-mountain` prefers paths and trails,
/// `trekking` is more forgiving on roads — good for road running.
String brouterProfile(bool trail) => trail ? 'hiking-mountain' : 'trekking';

Uri brouterUri(List<LatLng> via, {bool trail = true}) => Uri.https(
      'brouter.de',
      '/brouter',
      {
        'lonlats': [
          for (final p in via)
            '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}'
        ].join('|'),
        'profile': brouterProfile(trail),
        'alternativeidx': '0',
        'format': 'geojson',
      },
    );

/// Points and elevation from a BRouter GeoJSON answer, or null if it is not
/// one.
({List<LatLng> pts, List<double> elev})? parseBrouter(String body) {
  try {
    final j = jsonDecode(body);
    final f = (j['features'] as List).first as Map;
    final coords = (f['geometry'] as Map)['coordinates'] as List;
    final pts = <LatLng>[];
    final elev = <double>[];
    var allElev = true;
    for (final c in coords) {
      final l = c as List;
      pts.add(LatLng((l[1] as num).toDouble(), (l[0] as num).toDouble()));
      if (l.length > 2 && l[2] is num) {
        elev.add((l[2] as num).toDouble());
      } else {
        allElev = false;
      }
    }
    if (pts.length < 2) return null;
    return (pts: pts, elev: allElev ? elev : const <double>[]);
  } catch (_) {
    return null;
  }
}

Future<({List<LatLng> pts, List<double> elev})?> fetchSnapped(
    List<LatLng> via, {bool trail = true}) async {
  if (!plannerNetAllowed || via.length < 2) return null;
  try {
    final r = await http
        .get(brouterUri(via, trail: trail), headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    return parseBrouter(r.body);
  } catch (_) {
    return null;
  }
}

// ─────────────── Overpass: marked trails nearby ───────────────

class TrailInfo {
  final int id;
  final String name;
  final String route; // hiking · foot · running · fitness_trail · nordic_walking
  final String? network; // iwn · nwn · rwn · lwn
  final double? km; // the route's own distance tag
  final bool roundtrip;
  final LatLng? center;

  const TrailInfo(this.id, this.name, this.route,
      {this.network, this.km, this.roundtrip = false, this.center});
}

String trailsQuery(double s, double w, double n, double e) =>
    '[out:json][timeout:25];'
    'relation["type"="route"]["route"~"^(hiking|foot|running|fitness_trail|nordic_walking)\$"]'
    '(${s.toStringAsFixed(4)},${w.toStringAsFixed(4)},${n.toStringAsFixed(4)},${e.toStringAsFixed(4)});'
    'out tags center 60;';

double? _km(Object? tag) {
  if (tag is! String) return null;
  final m = RegExp(r'([0-9]+(?:[.,][0-9]+)?)\s*(km|mi|m)?').firstMatch(tag);
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (v == null) return null;
  return switch (m.group(2)) {
    'mi' => v * 1.609344,
    'm' => v / 1000,
    _ => v,
  };
}

List<TrailInfo> parseTrails(String body) {
  try {
    final j = jsonDecode(body);
    final out = <TrailInfo>[];
    for (final e in (j['elements'] as List? ?? const [])) {
      if (e is! Map || e['type'] != 'relation') continue;
      final t = (e['tags'] as Map?) ?? const {};
      final name = (t['name'] ?? t['ref'] ?? '') as String;
      if (name.isEmpty) continue;
      final c = e['center'];
      out.add(TrailInfo(
        (e['id'] as num).toInt(),
        name,
        (t['route'] as String?) ?? 'hiking',
        network: t['network'] as String?,
        km: _km(t['distance']),
        roundtrip: t['roundtrip'] == 'yes',
        center: c is Map
            ? LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble())
            : null,
      ));
    }
    // Local and running routes first: those are the ones you can do today.
    int rank(TrailInfo t) =>
        (t.route == 'running' || t.route == 'fitness_trail' ? 0 : 2) +
        (t.network == 'lwn' ? 0 : 1);
    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  } catch (_) {
    return const [];
  }
}

/// One relation's ways, stitched into a single line in member order: each
/// way is flipped when its far end is nearer to where the line stands.
List<LatLng> parseTrailGeometry(String body) {
  try {
    final j = jsonDecode(body);
    final rel = (j['elements'] as List)
        .whereType<Map>()
        .firstWhere((e) => e['type'] == 'relation');
    final ways = <List<LatLng>>[
      for (final m in (rel['members'] as List? ?? const []))
        if (m is Map && m['type'] == 'way' && m['geometry'] is List)
          [
            for (final g in m['geometry'] as List)
              if (g is Map && g['lat'] is num)
                LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()),
          ],
    ]..removeWhere((w) => w.length < 2);
    if (ways.isEmpty) return const [];
    double d(LatLng a, LatLng b) =>
        haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);
    final out = <LatLng>[];
    var first = ways.first;
    if (ways.length > 1) {
      final n = ways[1];
      final endNear = math.min(d(first.last, n.first), d(first.last, n.last));
      final startNear = math.min(d(first.first, n.first), d(first.first, n.last));
      if (startNear < endNear) first = first.reversed.toList();
    }
    out.addAll(first);
    for (final w in ways.skip(1)) {
      final fwd = d(out.last, w.first), rev = d(out.last, w.last);
      out.addAll(rev < fwd ? w.reversed : w);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<String?> _overpass(String q) async {
  if (!plannerNetAllowed) return null;
  try {
    final r = await http.post(Uri.https('overpass-api.de', '/api/interpreter'),
        headers: {'User-Agent': _ua}, body: {'data': q}).timeout(
        const Duration(seconds: 30));
    return r.statusCode == 200 ? r.body : null;
  } catch (_) {
    return null;
  }
}

Future<List<TrailInfo>?> fetchTrails(
    double s, double w, double n, double e) async {
  final body = await _overpass(trailsQuery(s, w, n, e));
  return body == null ? null : parseTrails(body);
}

Future<List<LatLng>> fetchTrailGeometry(int id) async {
  final body = await _overpass('[out:json][timeout:25];relation($id);out geom;');
  return body == null ? const [] : parseTrailGeometry(body);
}
