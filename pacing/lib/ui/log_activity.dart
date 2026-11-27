import 'package:flutter/material.dart';

import '../core/models.dart';
import 'common.dart';

/// Quick presets for effort heart rate does not see well.
const _presets = <(String, EffortKind, int, int)>[
  ('Duschen', EffortKind.orthostatic, 15, 2),
  ('Telefonat', EffortKind.cognitive, 15, 1),
  ('Arzttermin', EffortKind.emotional, 60, 2),
  ('Besuch', EffortKind.emotional, 30, 2),
  ('Bildschirm / Lesen', EffortKind.cognitive, 30, 1),
  ('Kochen', EffortKind.orthostatic, 20, 2),
  ('Einkaufen', EffortKind.physical, 30, 3),
  ('Formulare / Behörde', EffortKind.cognitive, 30, 3),
];

const kEffortNames = {
  EffortKind.physical: 'körperlich',
  EffortKind.cognitive: 'geistig',
  EffortKind.emotional: 'emotional',
  EffortKind.orthostatic: 'Stehen / Kreislauf',
};

class LogActivityScreen extends StatefulWidget {
  const LogActivityScreen({super.key});
  @override
  State<LogActivityScreen> createState() => _LogActivityScreenState();
}

class _LogActivityScreenState extends State<LogActivityScreen> {
  final label = TextEditingController();
  EffortKind kind = EffortKind.cognitive;
  int minutes = 15;
  int intensity = 1;

  void _save() {
    final st = AppScope.of(context);
    final now = DateTime.now();
    st.logActivity(ActivityLog(
      id: now.microsecondsSinceEpoch.toString(),
      start: now.subtract(Duration(minutes: minutes)),
      minutes: minutes,
      kind: kind,
      intensity: intensity,
      label: label.text.trim().isEmpty ? kEffortNames[kind]! : label.text.trim(),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Aktivität eintragen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              'Der Puls sieht vor allem körperliche Anstrengung. Denken, Gefühle '
              'und langes Stehen kosten auch Energie – trag sie hier ein.',
              style: t.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _presets)
                ActionChip(
                  label: Text(p.$1),
                  onPressed: () => setState(() {
                    label.text = p.$1;
                    kind = p.$2;
                    minutes = p.$3;
                    intensity = p.$4;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: label,
            decoration: const InputDecoration(
                labelText: 'Was?', border: OutlineInputBorder()),
          ),
          const SectionTitle('Art der Anstrengung'),
          Wrap(
            spacing: 8,
            children: [
              for (final k in EffortKind.values)
                ChoiceChip(
                  label: Text(kEffortNames[k]!),
                  selected: kind == k,
                  onSelected: (_) => setState(() => kind = k),
                ),
            ],
          ),
          SectionTitle('Dauer: $minutes min'),
          Slider(
            value: minutes.toDouble(),
            min: 5,
            max: 180,
            divisions: 35,
            label: '$minutes min',
            onChanged: (v) => setState(() => minutes = v.round()),
          ),
          const SectionTitle('Wie anstrengend war es für dich?'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('leicht')),
              ButtonSegment(value: 2, label: Text('mittel')),
              ButtonSegment(value: 3, label: Text('schwer')),
            ],
            selected: {intensity},
            onSelectionChanged: (s) => setState(() => intensity = s.first),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Eintragen')),
        ],
      ),
    );
  }
}
