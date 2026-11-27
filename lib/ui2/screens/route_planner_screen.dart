// Edge+: plan a run or hike on a map. Tap points, optionally follow paths,
// see distance, climb and the time at your pace; browse marked trails nearby;
// save, export as GPX, or start a run with the plan on the live screen.
//
// Everything that talks to a server is in lib/gps/route_planner.dart and
// gated by one switch the user flips on this screen first.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../gps/gps_source.dart';
import '../../gps/route_planner.dart';
import '../activity/run_coach.dart' show paceText;
import '../activity/run_stats.dart' show fmtHours, typicalPace;
import '../ui2.dart';
import 'run_coach_screen.dart' show startGuidedRun;
import 'run_stats_screen.dart' show loadRuns;

class RoutePlannerScreen extends StatefulWidget {
  final double? weightKg;
  const RoutePlannerScreen({super.key, this.weightKg});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final map = MapController();
  bool allowed = plannerNetAllowed;
  bool hike = false;
  bool snap = true;
  bool topo = false;
  bool trailsLayer = false;
  bool busy = false;
  LatLng center = const LatLng(51.1657, 10.4515); // Germany until we know
  double zoom = 6;
  LatLng? me;

  final via = <LatLng>[];
  final legs = <List<LatLng>>[];
  final legElev = <List<double>>[];
  String? trailName;

  double pace = 360; // s/km
  double kmh = 4;

  List<TrailInfo>? trails;

  @override
  void initState() {
    super.initState();
    loadRuns(context, days: 120).then((r) {
      final t = typicalPace(r);
      if (t != null && mounted) setState(() => pace = (t / 5).round() * 5.0);
    }).catchError((_) {});
    _locate();
  }

  Future<void> _locate() async {
    try {
      if (await GpsSource.ensurePermission() != GpsPermissionStatus.granted) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        me = LatLng(pos.latitude, pos.longitude);
        center = me!;
        zoom = 14;
      });
      try {
        map.move(me!, 14);
      } catch (_) {/* map not built yet: initialCenter picks it up */}
    } catch (_) {}
  }

  List<LatLng> get path => [
        for (var i = 0; i < legs.length; i++)
          ...(i == 0 ? legs[i] : legs[i].skip(1)),
      ];

  double get meters => pathMeters(path);

  ({double up, double down})? get climb {
    if (legs.isEmpty || legElev.length != legs.length) return null;
    if (legElev.any((e) => e.isEmpty)) return null;
    return climbOf([for (final e in legElev) ...e]);
  }

  Future<void> _add(LatLng p) async {
    if (trailName != null) {
      // Tapping after picking a trail starts a fresh plan.
      _clear();
    }
    if (via.isEmpty) {
      setState(() => via.add(p));
      return;
    }
    final from = via.last;
    setState(() {
      via.add(p);
      legs.add([from, p]);
      legElev.add(const []);
      busy = snap;
    });
    if (!snap) return;
    final i = legs.length - 1;
    final r = await fetchSnapped([from, p], trail: hike || topo);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (r != null && i < legs.length) {
        legs[i] = r.pts;
        legElev[i] = r.elev;
      }
    });
  }

  void _undo() => setState(() {
        if (via.isNotEmpty) via.removeLast();
        if (legs.isNotEmpty) {
          legs.removeLast();
          legElev.removeLast();
        }
        if (via.isEmpty) trailName = null;
      });

  void _clear() => setState(() {
        via.clear();
        legs.clear();
        legElev.clear();
        trailName = null;
      });

  Future<void> _loop() async {
    if (via.length < 2) return;
    await _add(via.first);
  }

  Future<void> _findTrails() async {
    LatLngBounds b;
    try {
      b = map.camera.visibleBounds;
    } catch (_) {
      return;
    }
    if ((b.north - b.south).abs() > .4 || (b.east - b.west).abs() > .6) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(tr(context, 'Zoom etwas näher heran, um Wege zu suchen.',
              'Zoom in a bit to search for trails.'))));
      return;
    }
    setState(() => busy = true);
    final r = await fetchTrails(b.south, b.west, b.north, b.east);
    if (!mounted) return;
    setState(() {
      busy = false;
      trails = r ?? const [];
    });
    if (r == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(tr(context, 'Suche fehlgeschlagen. Später nochmal.',
              'Search failed. Try again later.'))));
    }
  }

  Future<void> _pickTrail(TrailInfo t) async {
    setState(() => busy = true);
    final g = await fetchTrailGeometry(t.id);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (g.length >= 2) {
        via
          ..clear()
          ..addAll([g.first, g.last]);
        legs
          ..clear()
          ..add(g);
        legElev
          ..clear()
          ..add(const []);
        trailName = t.name;
        trails = null;
        hike = t.route == 'hiking' || t.route == 'foot';
      }
    });
    if (g.length >= 2) {
      try {
        map.fitCamera(CameraFit.coordinates(
            coordinates: g, padding: const EdgeInsets.all(40)));
      } catch (_) {}
    }
  }

  PlannedRoute _current(String name) {
    final c = climb;
    return PlannedRoute(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      points: thin(path),
      meters: meters,
      up: c?.up,
      down: c?.down,
      kind: hike ? 'hike' : 'run',
    );
  }

  Future<void> _save() async {
    final ctl = TextEditingController(text: trailName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'Route speichern', 'Save route')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr(c, 'Name', 'Name')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr(c, 'Abbrechen', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: Text(tr(c, 'Speichern', 'Save'))),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final km = (meters / 1000).toStringAsFixed(1);
    PlannedRouteStore.put(_current(name.isEmpty ? '$km km' : name));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(tr(context, 'Gespeichert', 'Saved'))));
  }

  Future<void> _gpx(PlannedRoute r) async {
    try {
      final dir = await getTemporaryDirectory();
      final safe = r.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final f = File('${dir.path}/${safe.isEmpty ? 'route' : safe}.gpx');
      await f.writeAsString(buildPlannedGpx(r));
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/gpx+xml')]);
    } catch (_) {}
  }

  void _openSaved() {
    final saved = PlannedRouteStore.load();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: P.of(context).card,
      builder: (c) {
        final p = P.of(c);
        return SafeArea(
          child: saved.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(S.x6),
                  child: Text(tr(c, 'Noch keine gespeicherten Routen.',
                      'No saved routes yet.'),
                      style: F.body.copyWith(color: p.ink2)),
                )
              : ListView(shrinkWrap: true, children: [
                  for (final r in saved)
                    ListTile(
                      leading: Icon(
                          r.kind == 'hike'
                              ? LucideIcons.mountain
                              : LucideIcons.footprints,
                          color: p.ink2),
                      title: Text(r.name, style: F.body.copyWith(color: p.ink)),
                      subtitle: Text(
                          '${(r.meters / 1000).toStringAsFixed(1)} km'
                          '${r.up == null ? '' : ' · ↑ ${r.up!.round()} m'}',
                          style: F.cap.copyWith(color: p.ink3)),
                      trailing: IconButton(
                        icon: Icon(LucideIcons.trash2, size: 18, color: p.ink3),
                        onPressed: () {
                          PlannedRouteStore.remove(r.id);
                          Navigator.pop(c);
                          _openSaved();
                        },
                      ),
                      onTap: () {
                        Navigator.pop(c);
                        _show(r);
                      },
                    ),
                ]),
        );
      },
    );
  }

  void _show(PlannedRoute r) {
    setState(() {
      via
        ..clear()
        ..addAll([r.points.first, r.points.last]);
      legs
        ..clear()
        ..add(r.points);
      legElev
        ..clear()
        ..add(const []);
      trailName = r.name;
      hike = r.kind == 'hike';
    });
    try {
      map.fitCamera(CameraFit.coordinates(
          coordinates: r.points, padding: const EdgeInsets.all(40)));
    } catch (_) {}
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
            child: NavBar(
              tr(c, 'Route planen', 'Plan a route'),
              trailing: allowed
                  ? Pressable(
                      semanticLabel: tr(c, 'Gespeicherte Routen', 'Saved routes'),
                      onTap: _openSaved,
                      child: Icon(LucideIcons.bookmark, size: 22, color: p.ink),
                    )
                  : null,
            ),
          ),
          Expanded(child: allowed ? _mapView(c, p) : _consent(c, p)),
        ]),
      ),
    );
  }

  Widget _consent(BuildContext c, P p) => ListView(
        padding: const EdgeInsets.all(S.x4),
        children: [
          StatusCard(
            tr(c, 'Karte braucht Internet', 'The map needs the internet'),
            tr(
                c,
                'Deine aufgezeichneten Läufe bleiben auf dem Handy. Für die '
                    'Planung fragt die App öffentliche OpenStreetMap-Dienste: '
                    'Kartenkacheln, BRouter (Wegen folgen) und Overpass '
                    '(Wanderwege in der Nähe). Dabei wird nur der Kartenausschnitt '
                    'bzw. die angetippten Punkte gesendet.',
                'Your recorded runs stay on the phone. Planning asks public '
                    'OpenStreetMap services: map tiles, BRouter (follow paths) '
                    'and Overpass (trails nearby). Only the visible area or the '
                    'points you tap are sent.'),
            icon: LucideIcons.map,
          ),
          const SizedBox(height: S.x4),
          BigButton(tr(c, 'Karte einschalten', 'Turn on the map'),
              icon: LucideIcons.map, onTap: () {
            setPlannerNetAllowed(true);
            setState(() => allowed = true);
          }),
        ],
      );

  Widget _mapView(BuildContext c, P p) {
    final pts = path;
    final accent = hike ? C.orange : C.green;
    return Column(children: [
      Expanded(
        child: Stack(children: [
          FlutterMap(
            mapController: map,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              maxZoom: 18,
              onTap: (_, ll) => _add(ll),
            ),
            children: [
              TileLayer(
                urlTemplate: topo
                    ? 'https://tile.opentopomap.org/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'org.openstrap.edge',
                maxNativeZoom: topo ? 17 : 19,
              ),
              if (trailsLayer)
                TileLayer(
                  urlTemplate:
                      'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
                  userAgentPackageName: 'org.openstrap.edge',
                  maxNativeZoom: 17,
                ),
              if (pts.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                      points: pts,
                      strokeWidth: 5,
                      color: p.on(accent),
                      borderStrokeWidth: 2,
                      borderColor: p.card),
                ]),
              MarkerLayer(markers: [
                if (me != null)
                  Marker(
                    point: me!,
                    width: 18,
                    height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                          color: C.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.card, width: 3)),
                    ),
                  ),
                for (var i = 0; i < via.length; i++)
                  Marker(
                    point: via[i],
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                          color: i == 0 ? C.green : (i == via.length - 1 ? C.red : p.card),
                          shape: BoxShape.circle,
                          border: Border.all(color: p.ink, width: 2)),
                    ),
                  ),
              ]),
              SimpleAttributionWidget(
                source: Text(topo
                    ? '© OpenStreetMap · OpenTopoMap (CC-BY-SA)'
                    : (trailsLayer
                        ? '© OpenStreetMap · Waymarked Trails'
                        : '© OpenStreetMap contributors')),
              ),
            ],
          ),
          Positioned(
            right: S.x3,
            top: S.x3,
            child: Column(children: [
              _fab(p, LucideIcons.locateFixed, tr(c, 'Mein Standort', 'My location'), _locate),
              _fab(p, LucideIcons.layers, tr(c, 'Topokarte', 'Topo map'),
                  () => setState(() => topo = !topo), on: topo),
              _fab(p, LucideIcons.signpost, tr(c, 'Wanderwege einblenden', 'Show trails'),
                  () => setState(() => trailsLayer = !trailsLayer), on: trailsLayer),
              _fab(p, LucideIcons.search, tr(c, 'Wege hier suchen', 'Find trails here'),
                  _findTrails),
            ]),
          ),
          if (busy)
            const Positioned(
                left: 0, right: 0, top: S.x3,
                child: Center(child: CircularProgressIndicator())),
          if (via.isEmpty && trails == null)
            Positioned(
              left: S.x4,
              right: 72,
              top: S.x3,
              child: Surface(
                pad: const EdgeInsets.all(S.x3),
                child: Text(
                    tr(c, 'Tippe auf die Karte, um Punkte zu setzen – oder suche '
                            'markierte Wege mit der Lupe.',
                        'Tap the map to set points – or find marked trails '
                            'with the magnifier.'),
                    style: F.cap.copyWith(color: p.ink)),
              ),
            ),
        ]),
      ),
      if (trails != null) _trailList(c, p) else _panel(c, p),
    ]);
  }

  Widget _fab(P p, IconData i, String label, VoidCallback onTap, {bool on = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: S.x2),
        child: Pressable(
          semanticLabel: label,
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: on ? p.wash(C.green, strength: 2) : p.card,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
            ),
            child: Icon(i, size: 20, color: on ? p.on(C.green) : p.ink),
          ),
        ),
      );

  Widget _trailList(BuildContext c, P p) {
    final t = trails!;
    String net(String? n) => switch (n) {
          'lwn' => tr(c, 'lokal', 'local'),
          'rwn' => tr(c, 'regional', 'regional'),
          'nwn' => tr(c, 'national', 'national'),
          'iwn' => tr(c, 'international', 'international'),
          _ => '',
        };
    String kind(String r) => switch (r) {
          'running' => tr(c, 'Laufstrecke', 'Running route'),
          'fitness_trail' => tr(c, 'Trimm-dich-Pfad', 'Fitness trail'),
          'nordic_walking' => 'Nordic Walking',
          _ => tr(c, 'Wanderweg', 'Hiking trail'),
        };
    return Container(
      color: p.card,
      constraints: const BoxConstraints(maxHeight: 300),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: S.x4),
          Expanded(
              child: Text(
                  tr(c, '${t.length} markierte Wege hier', '${t.length} marked trails here'),
                  style: F.head.copyWith(color: p.ink))),
          IconButton(
              icon: Icon(LucideIcons.x, color: p.ink2),
              onPressed: () => setState(() => trails = null)),
        ]),
        if (t.isEmpty)
          Padding(
            padding: const EdgeInsets.all(S.x4),
            child: Text(
                tr(c, 'Keine markierten Wege im Ausschnitt. Verschiebe die Karte '
                        'oder blende die Wanderwege ein.',
                    'No marked trails in view. Move the map or turn on the '
                        'trail layer.'),
                style: F.cap.copyWith(color: p.ink3)),
          ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final x in t)
              ListTile(
                dense: true,
                leading: Icon(
                    x.route == 'running' || x.route == 'fitness_trail'
                        ? LucideIcons.footprints
                        : LucideIcons.mountain,
                    color: p.ink2),
                title: Text(x.name, style: F.body.copyWith(color: p.ink)),
                subtitle: Text(
                    [
                      kind(x.route),
                      if (net(x.network).isNotEmpty) net(x.network),
                      if (x.km != null) '${x.km!.toStringAsFixed(1)} km',
                      if (x.roundtrip) tr(c, 'Rundweg', 'loop'),
                    ].join(' · '),
                    style: F.cap.copyWith(color: p.ink3)),
                onTap: () => _pickTrail(x),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _panel(BuildContext c, P p) {
    final m = meters;
    final cl = climb;
    final secs = hike
        ? hikeSeconds(m, cl?.up ?? 0, cl?.down ?? 0, kmh: kmh)
        : runSeconds(m, cl?.up ?? 0, pace);
    final has = m > 0;
    return Container(
      color: p.card,
      padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 190,
            child: SubTabs([tr(c, 'Laufen', 'Run'), tr(c, 'Wandern', 'Hike')],
                hike ? 1 : 0, (i) => setState(() => hike = i == 1),
                color: hike ? C.orange : C.green),
          ),
          const Spacer(),
          Text(tr(c, 'Wegen folgen', 'Follow paths'),
              style: F.cap.copyWith(color: p.ink2)),
          Switch(value: snap, onChanged: (v) => setState(() => snap = v)),
        ]),
        if (trailName != null)
          Padding(
            padding: const EdgeInsets.only(top: S.x1),
            child: Text(trailName!,
                style: F.body.copyWith(color: p.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        const SizedBox(height: S.x2),
        Row(children: [
          _big(p, has ? (m / 1000).toStringAsFixed(2) : '–', 'km'),
          _big(p, cl == null ? '–' : '${cl.up.round()}', tr(c, 'Hm ↑', 'm ↑')),
          _big(p, has ? fmtHours(secs.round()) : '–',
              hike ? tr(c, 'Gehzeit', 'walking') : tr(c, 'Laufzeit', 'run time')),
        ]),
        const SizedBox(height: S.x2),
        Row(children: [
          Pressable(
            semanticLabel: '−',
            onTap: () => setState(() {
              if (hike) {
                kmh = (kmh - .5).clamp(2.0, 8.0);
              } else {
                pace = (pace - 15).clamp(150.0, 600.0);
              }
            }),
            child: Padding(
                padding: const EdgeInsets.all(S.x2),
                child: Icon(LucideIcons.minus, size: 18, color: p.ink)),
          ),
          Expanded(
            child: Text(
                hike
                    ? tr(c, '${kmh.toStringAsFixed(1)} km/h in der Ebene (DIN 33466)',
                        '${kmh.toStringAsFixed(1)} km/h on the flat (DIN 33466)')
                    : tr(c, 'Pace ${paceText(pace)} /km · +1 km je 100 Hm',
                        'Pace ${paceText(pace)} /km · +1 km per 100 m up'),
                textAlign: TextAlign.center,
                style: F.cap.copyWith(color: p.ink2)),
          ),
          Pressable(
            semanticLabel: '+',
            onTap: () => setState(() {
              if (hike) {
                kmh = (kmh + .5).clamp(2.0, 8.0);
              } else {
                pace = (pace + 15).clamp(150.0, 600.0);
              }
            }),
            child: Padding(
                padding: const EdgeInsets.all(S.x2),
                child: Icon(LucideIcons.plus, size: 18, color: p.ink)),
          ),
        ]),
        const SizedBox(height: S.x2),
        Row(children: [
          _act(p, LucideIcons.undo2, tr(c, 'Zurück', 'Undo'), via.isEmpty ? null : _undo),
          _act(p, LucideIcons.repeat, tr(c, 'Rundkurs', 'Loop'),
              via.length < 2 || trailName != null ? null : _loop),
          _act(p, LucideIcons.trash2, tr(c, 'Löschen', 'Clear'), via.isEmpty ? null : _clear),
          _act(p, LucideIcons.save, tr(c, 'Speichern', 'Save'), has ? _save : null),
          _act(p, LucideIcons.share2, 'GPX', has ? () => _gpx(_current(trailName ?? 'Route')) : null),
        ]),
        const SizedBox(height: S.x2),
        BigButton(
          hike
              ? tr(c, 'Wanderung mit dieser Route starten', 'Start a hike on this route')
              : tr(c, 'Lauf mit dieser Route starten', 'Start a run on this route'),
          icon: LucideIcons.play,
          color: accent(),
          onTap: has
              ? () => startGuidedRun(c,
                  plannedRoute: (name: trailName ?? '', m: m),
                  activity: hike ? 'hiking' : 'running',
                  weightKg: widget.weightKg)
              : null,
        ),
      ]),
    );
  }

  Color accent() => hike ? C.orange : C.green;

  Widget _big(P p, String v, String label) => Expanded(
        child: Column(children: [
          Text(v, style: F.head.copyWith(color: p.ink)),
          Text(label, style: F.cap.copyWith(color: p.ink3)),
        ]),
      );

  Widget _act(P p, IconData i, String label, VoidCallback? onTap) => Expanded(
        child: Pressable(
          semanticLabel: label,
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? .35 : 1,
            child: Column(children: [
              Icon(i, size: 20, color: p.ink),
              const SizedBox(height: 2),
              Text(label, style: F.mini.copyWith(color: p.ink2)),
            ]),
          ),
        ),
      );
}
