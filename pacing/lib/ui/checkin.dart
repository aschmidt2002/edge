import 'package:flutter/material.dart';

import '../core/models.dart';
import 'common.dart';

/// The daily check-in. The first question alone is enough; the rest is
/// folded away so a bad day costs one tap.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key, this.existing});
  final CheckIn? existing;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  late int? feeling = widget.existing?.feeling;
  late int? fatigue = widget.existing?.fatigue;
  late int? brainFog = widget.existing?.brainFog;
  late int? pain = widget.existing?.pain;
  late int? sleep = widget.existing?.sleepRefreshing;
  late int? ortho = widget.existing?.orthostatic;
  late bool crash = widget.existing?.crash ?? false;
  late int crashSeverity = widget.existing?.crashSeverity ?? 2;
  late bool menstruating = widget.existing?.menstruating ?? false;
  late bool infection = widget.existing?.infection ?? false;
  late final note = TextEditingController(text: widget.existing?.note);
  bool more = false;

  void _save() {
    final st = AppScope.of(context);
    st.saveCheckIn(CheckIn(
      day: widget.existing?.day ?? st.todayKey,
      feeling: feeling ?? 2,
      fatigue: fatigue,
      brainFog: brainFog,
      pain: pain,
      sleepRefreshing: sleep,
      orthostatic: ortho,
      crash: crash,
      crashSeverity: crash ? crashSeverity : null,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
      menstruating: menstruating ? true : null,
      infection: infection ? true : null,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check-in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScaleRow(
            label: 'Wie geht es dir insgesamt?',
            value: feeling,
            onChanged: (v) => setState(() => feeling = v),
            lowText: 'sehr schlecht',
            highText: 'sehr gut',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ich bin gerade im Crash / PEM'),
            subtitle: const Text(
                'Deutliche Verschlechterung nach Belastung, oft 1–3 Tage später.'),
            value: crash,
            onChanged: (v) => setState(() => crash = v),
          ),
          if (crash)
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('leicht')),
                ButtonSegment(value: 2, label: Text('mittel')),
                ButtonSegment(value: 3, label: Text('schwer')),
              ],
              selected: {crashSeverity},
              onSelectionChanged: (s) =>
                  setState(() => crashSeverity = s.first),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: feeling == null ? null : _save,
            child: const Text('Fertig'),
          ),
          TextButton(
            onPressed: () => setState(() => more = !more),
            child: Text(more ? 'Weniger' : 'Mehr Details (optional)'),
          ),
          if (more) ...[
            ScaleRow(
                label: 'Erschöpfung',
                value: fatigue,
                onChanged: (v) => setState(() => fatigue = v),
                lowText: 'keine',
                highText: 'stark'),
            ScaleRow(
                label: 'Brain Fog / Konzentration',
                value: brainFog,
                onChanged: (v) => setState(() => brainFog = v),
                lowText: 'klar',
                highText: 'stark'),
            ScaleRow(
                label: 'Schmerzen',
                value: pain,
                onChanged: (v) => setState(() => pain = v),
                lowText: 'keine',
                highText: 'stark'),
            ScaleRow(
                label: 'Schlaf erholsam?',
                value: sleep,
                onChanged: (v) => setState(() => sleep = v),
                lowText: 'gar nicht',
                highText: 'sehr'),
            ScaleRow(
                label: 'Kreislauf beim Stehen (Schwindel, Herzrasen)',
                value: ortho,
                onChanged: (v) => setState(() => ortho = v),
                lowText: 'keine',
                highText: 'stark'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Periode'),
              value: menstruating,
              onChanged: (v) => setState(() => menstruating = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Infekt / Erkältung'),
              value: infection,
              onChanged: (v) => setState(() => infection = v ?? false),
            ),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notiz', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: feeling == null ? null : _save,
              child: const Text('Speichern'),
            ),
          ],
        ],
      ),
    );
  }
}
