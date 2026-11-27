import 'package:flutter/material.dart';

import '../core/models.dart';
import 'common.dart';

class MedsScreen extends StatelessWidget {
  const MedsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final meds = st.data.meds.where((m) => m.active).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Medikamente')),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              'Medikamente und Nahrungsergänzung mit Uhrzeit festhalten. '
              'Hilft, Veränderungen später mit Ärztin/Arzt zu besprechen. '
              'Die App gibt keine Empfehlungen zu Medikamenten.',
              style: t.bodySmall),
          const SizedBox(height: 12),
          if (meds.isEmpty) const Text('Noch nichts eingetragen.'),
          for (final m in meds)
            Card(
              child: ListTile(
                title: Text(m.dose.isEmpty ? m.name : '${m.name} · ${m.dose}'),
                subtitle: Text([
                  if (m.times.isNotEmpty) 'geplant ${m.times.join(', ')}',
                  'heute ${st.intakesToday(m.id).length}× genommen',
                  if (m.affectsHeartRate) 'senkt den Puls',
                ].join(' · ')),
                trailing: IconButton.filledTonal(
                  tooltip: 'Jetzt genommen',
                  icon: const Icon(Icons.check),
                  onPressed: () => st.takeMed(m),
                ),
                onTap: () => _edit(context, m),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, Medication? m) async {
    final st = AppScope.of(context);
    final name = TextEditingController(text: m?.name);
    final dose = TextEditingController(text: m?.dose);
    final times = TextEditingController(text: m?.times.join(', '));
    var hr = m?.affectsHeartRate ?? false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                  controller: dose,
                  decoration: const InputDecoration(labelText: 'Dosis')),
              TextField(
                  controller: times,
                  decoration: const InputDecoration(
                      labelText: 'Uhrzeiten (z. B. 08:00, 20:00)')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Senkt den Puls (z. B. Betablocker, Ivabradin)'),
                value: hr,
                onChanged: (v) => set(() => hr = v),
              ),
              Row(
                children: [
                  if (m != null)
                    TextButton(
                      onPressed: () {
                        st.removeMed(m);
                        Navigator.pop(c);
                      },
                      child: const Text('Löschen'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (name.text.trim().isEmpty) return;
                      st.upsertMed(Medication(
                        id: m?.id ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        name: name.text.trim(),
                        dose: dose.text.trim(),
                        times: times.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                        affectsHeartRate: hr,
                      ));
                      Navigator.pop(c);
                    },
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
