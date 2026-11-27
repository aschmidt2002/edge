import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/pem_lookback.dart';
import 'common.dart';

/// Last 28 days: how much of the envelope each day used, crashes marked.
/// Tapping a crash day shows the crash look-back.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final keys = [
      for (var n = 27; n >= 0; n--) dayKey(now.subtract(Duration(days: n)))
    ];
    final byDay = {for (final d in st.data.days) d.day: d};
    final checks = {for (final c in st.data.checkIns) c.day: c};
    final crashes =
        st.data.checkIns.where((c) => c.crash).toList()
          ..sort((a, b) => b.day.compareTo(a.day));

    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Verbrauch je Tag (Anteil am Rahmen)', style: t.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final k in keys)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: _Bar(
                        share: byDay[k]?.usedShare,
                        crash: checks[k]?.crash ?? false,
                        color: s,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('vor 4 Wochen', style: t.bodySmall),
              Text('heute', style: t.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'Linie = 100 % des Rahmens. Rot markiert = Crash gemeldet. '
              'Ruhige, gleichmäßige Balken unter der Linie sind das Ziel – nicht hohe.',
              style: t.bodySmall),
          const SectionTitle('Rahmen'),
          Text('Aktuell ${st.settings.envelope.round()} Punkte', style: t.bodyLarge),
          for (final line in st.data.envelopeLog.reversed.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(line, style: t.bodySmall),
            ),
          const SectionTitle('Crash-Rückblick'),
          if (crashes.isEmpty)
            Text('Noch kein Crash eingetragen.', style: t.bodySmall),
          for (final c in crashes.take(10))
            Card(
              child: ExpansionTile(
                title: Text('Crash am ${c.day}'),
                subtitle: const Text('Was die 1–3 Tage davor gekostet haben'),
                children: [
                  for (final i in crashLookback(
                    crashDay: c.day,
                    days: st.data.days,
                    logs: st.data.logs,
                    costOf: st.costOf,
                  ))
                    ListTile(
                      dense: true,
                      title: Text(i.label),
                      subtitle: Text(i.day),
                      trailing: i.overspent
                          ? const Icon(Icons.warning_amber)
                          : Text('${i.points.round()}'),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                        'Kandidaten, keine Ursache. PEM kommt oft verzögert – Muster zeigen sich erst über mehrere Crashs.'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.share, required this.crash, required this.color});
  final double? share;
  final bool crash;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const maxShare = 1.5;
      final h = c.maxHeight;
      final v = (share ?? 0).clamp(0.0, maxShare) / maxShare;
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: h / maxShare,
            left: 0,
            right: 0,
            child: Container(height: 1, color: color.outline),
          ),
          Container(
            height: share == null ? 2 : h * v,
            decoration: BoxDecoration(
              color: crash
                  ? const Color(0xFFC9785F)
                  : (share ?? 0) > 1
                      ? const Color(0xFFD1B25E)
                      : color.primary.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
    });
  }
}
