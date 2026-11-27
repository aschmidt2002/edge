import 'package:flutter/material.dart';

import '../core/models.dart';
import 'common.dart';
import 'settings.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Severity severity = Severity.moderate;
  bool accepted = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Akku', style: t.displaySmall),
            const SizedBox(height: 8),
            Text('Energie einteilen bei ME/CFS und Long COVID.', style: t.titleMedium),
            const SizedBox(height: 24),
            const Text(
                'Die Idee: Du hast jeden Tag einen begrenzten Energie-Rahmen. Wer ihn '
                'regelmäßig überzieht, riskiert eine Verschlechterung (PEM, "Crash"), oft '
                'erst 1–3 Tage später. Akku schätzt, wie viel davon heute noch übrig ist – '
                'aus deinem Puls, deinem Morgen-Check-in und dem, was du einträgst – und '
                'warnt mit Vibration, bevor du die Grenze überschreitest.'),
            const SizedBox(height: 16),
            const Text(
                'Der Akku soll nicht "größer trainiert" werden. Er wächst nur, wenn dein '
                'Körper über Wochen stabil bleibt, und er schrumpft sofort nach einem Crash.'),
            const SectionTitle('Wie würdest du deinen Alltag gerade einschätzen?'),
            SegmentedButton<Severity>(
              segments: [
                for (final v in Severity.values)
                  ButtonSegment(value: v, label: Text(kSeverityNames[v]!)),
              ],
              selected: {severity},
              onSelectionChanged: (v) => setState(() => severity = v.first),
            ),
            const SizedBox(height: 24),
            Text(kDisclaimer, style: t.bodySmall),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: accepted,
              onChanged: (v) => setState(() => accepted = v ?? false),
              title: const Text('Verstanden'),
            ),
            FilledButton(
              onPressed: !accepted
                  ? null
                  : () => AppScope.of(context).updateSettings((s) {
                        s.severity = severity;
                        s.onboarded = true;
                      }),
              child: const Text('Los geht’s'),
            ),
          ],
        ),
      ),
    );
  }
}
