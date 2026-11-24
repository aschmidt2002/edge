// Edge+: Bildschirmzeit — Digital Wellbeing's numbers next to your mood.
//
// Three values, the top apps, and a mood line only where the days carry one
// (lib/screentime/screen_time.dart decides that). Kept small on purpose.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart' show dayLabelOf;
import '../../data/db.dart' show LocalDb;
import '../../screentime/screen_time.dart';
import '../ui2.dart';
import 'metric_detail.dart' show detailScaffold;

class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen({super.key});

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> with WidgetsBindingObserver {
  Map<String, double> _mood = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Settings > Usage access: pick the grant up at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    await ScreenTime.refresh();
    var mood = const <String, double>{};
    try {
      final now = DateTime.now();
      final since = dayLabelOf(DateTime(now.year, now.month, now.day - 400));
      mood = dailyMood(await LocalDb.journalMetricsByDay(sinceDaysEpoch: since));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _mood = mood;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext c) => ValueListenableBuilder<int>(
    valueListenable: ScreenTime.changed,
    builder: (c, _, _) => _build(c),
  );

  Widget _build(BuildContext c) {
    final title = tr(c, 'Bildschirmzeit', 'Screen time');
    if (_loading) {
      return detailScaffold(c, title, const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }
    if (!ScreenTime.connected) {
      return detailScaffold(c, title, [
        StatusCard(
          tr(c, 'Nicht verbunden', 'Not connected'),
          tr(c, 'Erlaube Edge+ den Nutzungsdatenzugriff.',
              'Allow Edge+ usage access.'),
          icon: LucideIcons.smartphone,
          fix: tr(c, 'Erlauben', 'Allow'),
          onFix: ScreenTime.openSettings,
        ),
      ]);
    }

    final p = P.of(c);
    final now = DateTime.now();
    final today = dayLabelOf(now);
    final yesterday = dayLabelOf(DateTime(now.year, now.month, now.day - 1));
    final all = ScreenTime.days();
    final names = ScreenTime.labels();
    final week = [
      for (var i = 1; i <= 7; i++)
        ?all[dayLabelOf(DateTime(now.year, now.month, now.day - i))],
    ];
    final y = all[yesterday];
    final avg = week.isEmpty
        ? null
        : (week.fold<int>(0, (a, d) => a + d.total) / week.length).round();
    final perApp = <String, int>{};
    for (final d in week) {
      for (final e in d.apps.entries) {
        perApp[e.key] = (perApp[e.key] ?? 0) + e.value;
      }
    }
    final top = perApp.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final past = {for (final e in all.entries) if (e.key != today) e.key: e.value};
    final hints = moodHints(past, _mood);
    final paired = past.keys.where(_mood.containsKey).length;

    return detailScaffold(c, title, [
      Row(children: [
        Expanded(child: _Tile(tr(c, 'Gestern', 'Yesterday'), y == null ? '–' : hm(y.total))),
        const SizedBox(width: S.x3),
        Expanded(child: _Tile(tr(c, 'Ø 7 Tage', 'Avg 7 days'), avg == null ? '–' : hm(avg))),
        const SizedBox(width: S.x3),
        Expanded(child: _Tile(tr(c, 'Entsperrt', 'Unlocks'), y == null ? '–' : '${y.unlocks}')),
      ]),
      if (top.isNotEmpty)
        Section(
          tr(c, 'Apps · Ø pro Tag', 'Apps · avg per day'),
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(children: [
              for (final (i, e) in top.take(5).indexed) ...[
                if (i > 0) Divider(color: p.line, height: 1),
                _Row(ScreenTime.label(e.key, names), hm((e.value / week.length).round())),
              ],
            ]),
          ),
        ),
      Section(
        tr(c, 'Stimmung', 'Mood'),
        hints.isEmpty
            ? Surface(
                child: Text(
                  paired < kMinMoodDays
                      ? tr(c, 'Noch zu wenig Tage · $paired/$kMinMoodDays',
                          'Not enough days yet · $paired/$kMinMoodDays')
                      : tr(c, 'Kein Muster · $paired Tage', 'No pattern · $paired days'),
                  style: F.body.copyWith(color: p.ink3),
                ),
              )
            : Surface(
                pad: const EdgeInsets.symmetric(horizontal: S.x4),
                child: Column(children: [
                  for (final (i, h) in hints.take(4).indexed) ...[
                    if (i > 0) Divider(color: p.line, height: 1),
                    _HintRow(h, names),
                  ],
                ]),
              ),
      ),
      const SizedBox(height: S.x2),
      Text(
        tr(c, 'Zusammenhang, keine Ursache.', 'A link, not a cause.'),
        textAlign: TextAlign.center,
        style: F.cap.copyWith(color: p.ink3),
      ),
    ]);
  }
}

/// "2 h 05", "45 min".
String hm(int minutes) => minutes < 60
    ? '$minutes min'
    : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: F.head.copyWith(color: p.ink), maxLines: 1),
        Text(label, style: F.cap.copyWith(color: p.ink3), maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.name, this.value);
  final String name, value;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Expanded(child: Text(name, style: F.body.copyWith(color: p.ink),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text(value, style: F.body.copyWith(color: p.ink2)),
      ]),
    );
  }
}

/// "Instagram > 2 h   −0,8" with "Stimmung 2,9 statt 3,7 · 9/21 Tage" below.
class _HintRow extends StatelessWidget {
  const _HintRow(this.h, this.names);
  final MoodHint h;
  final Map<String, String> names;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    String n(double v) => v.toStringAsFixed(1).replaceAll('.', tr(c, ',', '.'));
    final what = h.unlocks
        ? tr(c, '> ${h.threshold}× entsperrt', '> ${h.threshold} unlocks')
        : '${h.what.isEmpty ? tr(c, 'Gesamt', 'Total') : ScreenTime.label(h.what, names)}'
            ' > ${hm(h.threshold)}';
    final worse = h.delta < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(what, style: F.body.copyWith(color: p.ink)),
            Text(
              tr(c, 'Stimmung ${n(h.moodAbove)} statt ${n(h.moodBelow)} · ${h.nAbove} Tage',
                  'Mood ${n(h.moodAbove)} vs ${n(h.moodBelow)} · ${h.nAbove} days'),
              style: F.cap.copyWith(color: p.ink3),
            ),
          ]),
        ),
        Text('${worse ? '−' : '+'}${n(h.delta.abs())}',
            style: F.head.copyWith(color: p.on(worse ? C.red : C.green))),
      ]),
    );
  }
}
