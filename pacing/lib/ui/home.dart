import 'package:flutter/material.dart';

import '../core/ideas.dart';
import 'battery.dart';
import 'checkin.dart';
import 'common.dart';
import 'log_activity.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final day = st.today;
    final share = st.batteryShare;
    final th = st.threshold;
    final ideas = ideasFor(st.settings.severity, share,
        hidden: st.data.hiddenIdeas, inCrash: st.inCrash);

    return Scaffold(
      appBar: AppBar(title: const Text('Heute')),
      floatingActionButton: FloatingActionButton.extended(
        // Both tabs with a FAB stay alive in the IndexedStack.
        heroTag: null,
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LogActivityScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Aktivität'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${(share * 100).round()} %',
                          style: t.displayMedium),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${day.remaining.round()} von ${day.envelope.round()} Punkten',
                            style: t.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BatteryGauge(share: share),
                  const SizedBox(height: 12),
                  Text(_statusLine(share, st.inCrash), style: t.bodyLarge),
                  if (st.lastEnvelopeNote != null) ...[
                    const SizedBox(height: 8),
                    Text(st.lastEnvelopeNote!, style: t.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(st.sensorConnected
                  ? Icons.favorite
                  : Icons.favorite_border),
              title: Text(st.liveHr == null
                  ? (st.settings.hrDeviceId == null
                      ? 'Kein Pulssensor verbunden'
                      : 'Warte auf Puls …')
                  : 'Puls ${st.liveHr}'),
              subtitle: Text([
                if (th.ceiling != null)
                  'Grenze ${th.ceiling}'
                else
                  'Grenze nicht gesetzt (Ruhepuls oder Alter fehlt)',
                if (day.minutesOverThreshold > 0)
                  '${day.minutesOverThreshold} min darüber',
                if (th.warning != null) th.warning!,
              ].join(' · ')),
            ),
          ),
          if (st.todayCheckIn == null)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.wb_twilight),
                title: const Text('Wie geht es dir heute?'),
                subtitle: const Text(
                    'Kurze Abfrage, ein Tipp reicht. Damit startet der Akku richtig.'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CheckInScreen())),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: Icon(st.inCrash ? Icons.bedtime : Icons.check_circle),
                title: Text(st.inCrash
                    ? 'Crash-Tag: Ruhe hat Vorrang'
                    : 'Check-in erledigt'),
                subtitle: const Text('Antippen zum Ändern'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CheckInScreen(existing: st.todayCheckIn))),
              ),
            ),
          const SectionTitle('Ideen für jetzt'),
          Text(
            'Nur Ideen, keine Empfehlung. Was für dich leicht ist, weißt du am besten. '
            'Lange drücken blendet eine Idee aus.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 6),
          for (final i in ideas)
            Card(
              child: ListTile(
                title: Text(i.label),
                subtitle: i.hint == null ? null : Text(i.hint!),
                trailing: Text(_costLabel(i.cost), style: t.labelMedium),
                onLongPress: () => st.toggleIdea(i.id),
              ),
            ),
          const SectionTitle('Heute eingetragen'),
          ...st.data.logs.where((l) => l.day == st.todayKey).map((l) => Card(
                child: ListTile(
                  title: Text(l.label),
                  subtitle: Text('${l.minutes} min · −${st.costOf(l).round()} Punkte'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => st.deleteActivity(l),
                  ),
                ),
              )),
          const SizedBox(height: 12),
          Text(kDisclaimer, style: t.bodySmall),
        ],
      ),
    );
  }

  static String _costLabel(int c) =>
      const ['Ruhe', 'sehr leicht', 'leicht', 'mittel'][c];

  static String _statusLine(double share, bool crash) {
    if (crash) {
      return 'Heute ist ein Crash-Tag. Der Rahmen ist bewusst klein gehalten.';
    }
    if (share <= 0.05) return 'Akku leer. Zeit für echte Ruhe.';
    if (share <= 0.2) return 'Akku niedrig. Jetzt eine Pause einplanen.';
    if (share <= 0.45) return 'Halb leer. Lieber Puffer lassen als ausreizen.';
    return 'Genug Energie für ruhige Aktivitäten. Pausen trotzdem vorher einplanen.';
  }
}
