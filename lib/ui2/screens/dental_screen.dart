// Edge+: Zahnhygiene — the Oral-B brush's sessions, kept small.
//
// After the Oral-B app's own summary: the last clean against two minutes,
// twice a day, the streak and the pressure ring. Everything here is read from
// sessions this app heard (lib/oralb/oralb.dart); nothing is estimated.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../oralb/oralb.dart';
import '../../oralb/oralb_watcher.dart';
import '../ui2.dart';
import '../skeleton/guide_plot.dart' show GuidePlot;
import 'metric_detail.dart' show detailScaffold;

class DentalScreen extends StatelessWidget {
  const DentalScreen({super.key, this.now});

  /// Tests pin the clock.
  final DateTime? now;

  @override
  Widget build(BuildContext c) => ValueListenableBuilder<int>(
    valueListenable: OralBStore.changed,
    builder: (c, _, _) => ValueListenableBuilder<OralBAdvert?>(
      valueListenable: OralBWatcher.instance.live,
      builder: (c, live, _) => _build(c, live),
    ),
  );

  Widget _build(BuildContext c, OralBAdvert? live) {
    final p = P.of(c);
    final sessions = OralBStore.sessions();
    final st = BrushStats(sessions, now ?? DateTime.now());
    final last = sessions.firstOrNull;
    void connect() => Navigator.of(c).push(
        MaterialPageRoute<void>(builder: (_) => const OralBConnectScreen()));

    return detailScaffold(
      c,
      tr(c, 'Zahnhygiene', 'Oral care'),
      [
        if (live != null) ...[_LiveCard(live), const SizedBox(height: S.x3)],
        if (last == null)
          StatusCard(
            OralBStore.paired
                ? tr(c, 'Noch kein Putzen erfasst', 'No brushing heard yet')
                : tr(c, 'Keine Zahnbürste verbunden', 'No toothbrush connected'),
            OralBStore.paired
                ? tr(c, 'Putz mit der App im Hintergrund und der Bürste in der Nähe.',
                    'Brush with the app running and the brush nearby.')
                : tr(c, 'Verbinde deine Oral-B unter Profil > Meine Quellen.',
                    'Connect your Oral-B under Profile > My sources.'),
            icon: LucideIcons.smile,
            fix: OralBStore.paired ? '' : tr(c, 'Verbinden', 'Connect'),
            onFix: OralBStore.paired ? null : connect,
          )
        else ...[
          _Hero(last: last, today: st.todayCount),
          const SizedBox(height: S.x3),
          Row(children: [
            Expanded(child: _Tile(tr(c, 'Ø Dauer', 'Avg time'),
                st.avgSeconds == null ? '–' : brushClock(st.avgSeconds!),
                ok: (st.avgSeconds ?? 0) >= kBrushGoalSeconds)),
            const SizedBox(width: S.x3),
            Expanded(child: _Tile(tr(c, '2× täglich', 'Twice a day'), '${st.twiceDays}/7',
                ok: st.twiceDays >= 6)),
            const SizedBox(width: S.x3),
            Expanded(child: _Tile(tr(c, 'Serie', 'Streak'),
                tr(c, '${st.streak} T', '${st.streak} d'), ok: st.streak >= 3)),
          ]),
          const SizedBox(height: S.x3),
          Surface(
            child: Row(children: [
              Icon(LucideIcons.gauge, size: 18,
                  color: p.on(st.pressureSessions == 0 ? C.green : C.red)),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(
                  st.pressureSessions == 0
                      ? tr(c, 'Druck passt', 'Pressure fine')
                      : tr(c, 'Zu fest in ${st.pressureSessions} von ${st.weekSessions}',
                          'Too hard in ${st.pressureSessions} of ${st.weekSessions}'),
                  style: F.body.copyWith(color: p.ink),
                ),
              ),
              Text(tr(c, '7 Tage', '7 days'), style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          if (zoneTrend(sessions, now ?? DateTime.now()) case final z?)
            Section(tr(c, 'Bereiche · 30 Tage', 'Areas · 30 days'), _JawCard(z)),
          Section(
            tr(c, 'Verlauf', 'History'),
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Column(children: [
                for (final (i, s) in sessions.take(7).indexed) ...[
                  if (i > 0) Divider(color: p.line, height: 1),
                  _SessionRow(s),
                ],
              ]),
            ),
          ),
        ],
        const SizedBox(height: S.x4),
        Pressable(
          onTap: connect,
          semanticLabel: tr(c, 'Zahnbürste', 'Toothbrush'),
          child: Text(
            OralBStore.paired
                ? '${OralBStore.deviceName} · ${tr(c, 'erfasst, solange die App läuft', 'heard while the app runs')}'
                : tr(c, 'Zahnbürste verbinden', 'Connect toothbrush'),
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.last, required this.today});
  final BrushSession last;
  final int today;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ok = last.seconds >= kBrushGoalSeconds;
    return Surface(
      child: Row(children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: (last.seconds / kBrushGoalSeconds).clamp(0.0, 1.0),
                strokeWidth: 7,
                backgroundColor: p.track,
                color: p.fill(ok ? C.green : C.orange),
                strokeCap: StrokeCap.round,
              ),
            ),
            Text(brushClock(last.seconds), style: F.head.copyWith(color: p.ink)),
          ]),
        ),
        const SizedBox(width: S.x4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(c, 'Heute', 'Today'), style: F.cap.copyWith(color: p.ink3)),
            const SizedBox(height: S.x1),
            Row(children: [
              for (var i = 0; i < 2; i++) ...[
                Icon(i < today ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 22, color: i < today ? p.on(C.green) : p.ink3),
                const SizedBox(width: S.x2),
              ],
              Text('$today/2', style: F.body.copyWith(color: p.ink)),
            ]),
            const SizedBox(height: S.x1),
            Text(
              '${tr(c, 'Zuletzt', 'Last')} ${_when(c, last.start)}',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.ok = false});
  final String label, value;
  final bool ok;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: F.head.copyWith(color: ok ? p.on(C.green) : p.ink)),
        Text(label, style: F.cap.copyWith(color: p.ink3), maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow(this.s);
  final BrushSession s;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Expanded(child: Text(_when(c, s.start), style: F.body.copyWith(color: p.ink))),
        if (s.pressureWarnings > 0) ...[
          Icon(LucideIcons.gauge, size: 15, color: p.on(C.red)),
          const SizedBox(width: S.x3),
        ],
        Text(brushClock(s.seconds),
            style: F.body.copyWith(
                color: s.seconds >= kBrushGoalSeconds ? p.on(C.green) : p.ink2)),
      ]),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard(this.a);
  final OralBAdvert a;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      child: Row(children: [
        Icon(LucideIcons.activity, size: 18, color: p.on(C.teal)),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(
            a.sector > 0
                ? tr(c, 'Putzt · Bereich ${a.sector}/${a.sectors ?? 4}',
                    'Brushing · area ${a.sector}/${a.sectors ?? 4}')
                : tr(c, 'Putzt', 'Brushing'),
            style: F.body.copyWith(color: p.ink),
          ),
        ),
        if (a.highPressure) ...[
          Icon(LucideIcons.gauge, size: 18, color: p.on(C.red)),
          const SizedBox(width: S.x3),
        ],
        Text(brushClock(a.seconds), style: F.head.copyWith(color: p.ink)),
      ]),
    );
  }
}

/// Upper and lower jaw, each tooth coloured by how long the timer ran in its
/// zone on average against an even share of two minutes.
///
/// Zone order is the dental quadrant order (FDI): 1 upper right, 2 upper
/// left, 3 lower left, 4 lower right; six zones split each jaw into right,
/// front and left. Drawn as you see a face, so the user's right is on the left.
/// ponytail: the order is the convention, not read from the brush. If a
/// real iO shows another order, change [jawZone] only.
class _JawCard extends StatelessWidget {
  const _JawCard(this.z);
  final ({int sessions, int zones, Map<int, double> avg}) z;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final goal = kBrushGoalSeconds / z.zones;
    Color colour(int zone) {
      final r = (z.avg[zone] ?? 0) / goal;
      return p.fill(r >= 0.85 ? C.green : r >= 0.6 ? C.orange : C.red);
    }

    final weakest = z.avg.entries.reduce((a, b) => a.value <= b.value ? a : b);
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          label: [
            for (var i = 1; i <= z.zones; i++)
              '${zoneName(c, i, z.zones)} ${z.avg[i]!.round()} s',
          ].join(', '),
          child: AspectRatio(
            aspectRatio: 1.15,
            child: Stack(children: [
              Positioned.fill(
                  child: CustomPaint(painter: _JawPainter(z.zones, colour))),
              // As you see a face: the user's right is on the left.
              Align(
                alignment: Alignment.centerLeft,
                child: Text(tr(c, 'R', 'R'), style: F.cap.copyWith(color: p.ink3)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(tr(c, 'L', 'L'), style: F.cap.copyWith(color: p.ink3)),
              ),
              Align(
                child: Text(tr(c, 'oben\n\nunten', 'upper\n\nlower'),
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: p.ink3)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: S.x2),
        Row(children: [
          Expanded(
            child: Text(
              weakest.value / goal >= 0.85
                  ? tr(c, 'Alle Bereiche gleichmäßig', 'All areas even')
                  : tr(c, 'Am kürzesten: ${zoneName(c, weakest.key, z.zones)}',
                      'Shortest: ${zoneName(c, weakest.key, z.zones)}'),
              style: F.body.copyWith(color: p.ink),
            ),
          ),
          Text('Ø ${weakest.value.round()} / ${goal.round()} s',
              style: F.cap.copyWith(color: p.ink3)),
        ]),
        const SizedBox(height: S.x1),
        Text(
          tr(c, 'Nach dem Bereichs-Timer der Bürste, nicht nach erkannter Position · ${z.sessions}× geputzt',
              'From the brush’s area timer, not a detected position · ${z.sessions} sessions'),
          style: F.cap.copyWith(color: p.ink3),
        ),
      ]),
    );
  }
}

/// Which zone a tooth belongs to: [upper] jaw, [i] 0..15 left to right on
/// screen (the user's right first).
int jawZone(bool upper, int i, int zones) {
  final right = i < 8;
  if (zones == 4) return upper ? (right ? 1 : 2) : (right ? 4 : 3);
  final part = i < 5 ? 0 : i < 11 ? 1 : 2; // right, front, left
  return upper ? 1 + part : 6 - part;
}

String zoneName(BuildContext c, int zone, int zones) {
  if (zones == 4) {
    return switch (zone) {
      1 => tr(c, 'oben rechts', 'upper right'),
      2 => tr(c, 'oben links', 'upper left'),
      3 => tr(c, 'unten links', 'lower left'),
      _ => tr(c, 'unten rechts', 'lower right'),
    };
  }
  return switch (zone) {
    1 => tr(c, 'oben rechts', 'upper right'),
    2 => tr(c, 'oben vorne', 'upper front'),
    3 => tr(c, 'oben links', 'upper left'),
    4 => tr(c, 'unten links', 'lower left'),
    5 => tr(c, 'unten vorne', 'lower front'),
    _ => tr(c, 'unten rechts', 'lower right'),
  };
}

// Brushing time per zone is data, so a guide placeholder turns it into a wave.
class _JawPainter extends CustomPainter implements GuidePlot {
  _JawPainter(this.zones, this.colour);
  final int zones;
  final Color Function(int zone) colour;

  @override
  Color get guideLineColor => colour(0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rx = w * 0.40, ry = h * 0.30;
    for (final upper in [true, false]) {
      // Each jaw is a U: the upper one opens downward from the top half, the
      // lower one upward from the bottom half, with a gap between them.
      final centre = Offset(w / 2, upper ? h * 0.44 : h * 0.56);
      for (var i = 0; i < 16; i++) {
        // Angles across the U, molars at the ends.
        final t = (i + 0.5) / 16;
        final a = math.pi * (1 + t); // 180°..360°: the top arc
        final dir = upper ? 1.0 : -1.0;
        final pos = Offset(centre.dx + rx * math.cos(a), centre.dy + dir * ry * math.sin(a));
        // Back teeth are wider than the front ones.
        final back = (t - 0.5).abs() * 2; // 0 front, 1 back
        final tw = w * (0.050 + 0.030 * back), th = w * (0.060 + 0.012 * back);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(math.atan2(dir * ry * math.cos(a), -rx * math.sin(a)));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: tw, height: th),
              Radius.circular(tw * 0.35)),
          Paint()..color = colour(jawZone(upper, i, zones)),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_JawPainter old) => true;
}

/// "Heute 07:41", "Gestern 22:10", "Mo 21.11. 07:30".
String _when(BuildContext c, DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (days == 0) return '${tr(c, 'Heute', 'Today')} $hm';
  if (days == 1) return '${tr(c, 'Gestern', 'Yesterday')} $hm';
  return '${t.day}.${t.month}. $hm';
}

/// Connect or forget the brush. Reached from My sources and from the page.
class OralBConnectScreen extends StatefulWidget {
  const OralBConnectScreen({super.key});

  @override
  State<OralBConnectScreen> createState() => _OralBConnectScreenState();
}

class _OralBConnectScreenState extends State<OralBConnectScreen> {
  Map<String, ({String name, int rssi})> _found = const {};
  bool _scanning = false, _searched = false;
  String? _problem;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _searched = true;
      _problem = null;
      _found = const {};
    });
    try {
      await scanForBrushes((f) {
        if (mounted) setState(() => _found = f);
      });
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _pick(String id, String name) {
    OralBStore.pair(id, name);
    OralBWatcher.instance.start();
    OralBWatcher.instance.poke();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return detailScaffold(c, tr(c, 'Zahnbürste', 'Toothbrush'), [
      if (OralBStore.paired) ...[
        Surface(
          child: Row(children: [
            Icon(LucideIcons.smile, size: 18, color: p.on(C.teal)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Text(OralBStore.deviceName,
                  style: F.body.copyWith(color: p.ink)),
            ),
            Pressable(
              onTap: () {
                OralBStore.unpair();
                setState(() {});
              },
              semanticLabel: tr(c, 'Trennen', 'Forget'),
              child: Padding(
                padding: const EdgeInsets.all(S.x2),
                child: Text(tr(c, 'Trennen', 'Forget'),
                    style: F.cap.copyWith(color: p.on(C.red))),
              ),
            ),
          ]),
        ),
        const SizedBox(height: S.x3),
      ],
      Text(
        tr(c, 'Bürste einschalten, dann suchen.', 'Switch the brush on, then search.'),
        style: F.cap.copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x3),
      BigButton(
        _scanning ? tr(c, 'Suche …', 'Searching …') : tr(c, 'Suchen', 'Search'),
        icon: LucideIcons.bluetooth,
        busy: _scanning,
        onTap: _scanning ? null : _scan,
      ),
      if (_problem != null) ...[
        const SizedBox(height: S.x3),
        Text(_problem!, style: F.cap.copyWith(color: p.on(C.red))),
      ],
      if (_found.isNotEmpty) ...[
        const SizedBox(height: S.x3),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (final (i, e) in _found.entries.indexed) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              Pressable(
                onTap: () => _pick(e.key, e.value.name),
                semanticLabel: e.value.name,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x4),
                  child: Row(children: [
                    Expanded(
                      child: Text(e.value.name,
                          style: F.body.copyWith(color: p.ink)),
                    ),
                    Text('${e.value.rssi} dBm', style: F.cap.copyWith(color: p.ink3)),
                    const SizedBox(width: S.x2),
                    Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ],
      if (!_scanning && _problem == null && _found.isEmpty && _searched)
        Padding(
          padding: const EdgeInsets.only(top: S.x3),
          child: Text(tr(c, 'Keine Oral-B gefunden.', 'No Oral-B found.'),
              style: F.cap.copyWith(color: p.ink3)),
        ),
    ]);
  }

}
