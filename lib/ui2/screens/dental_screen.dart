// Edge+: Zahnhygiene — the Oral-B brush's sessions, kept small.
//
// After the Oral-B app's own summary: the last clean against two minutes,
// twice a day, the streak and the pressure ring. Everything here is read from
// sessions this app heard (lib/oralb/oralb.dart); nothing is estimated.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../oralb/oralb.dart';
import '../../oralb/oralb_watcher.dart';
import '../ui2.dart';
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
