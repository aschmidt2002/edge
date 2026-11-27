import 'package:flutter/material.dart';

import '../state/pacing_state.dart';

/// Hands the one [PacingState] to every screen.
class AppScope extends InheritedNotifier<PacingState> {
  const AppScope({super.key, required PacingState state, required super.child})
      : super(notifier: state);

  static PacingState of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Calm, low-contrast dark theme: many people with ME/CFS are light and
/// sound sensitive. No animations beyond what Material does by default, large
/// touch targets.
ThemeData appTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6B8F71),
    brightness: b,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.comfortable,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
  );
}

Color batteryColor(double share, ColorScheme s) {
  if (share <= 0.2) return const Color(0xFFC9785F);
  if (share <= 0.45) return const Color(0xFFD1B25E);
  return const Color(0xFF7FA982);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// A row of 0..4 choices. Big buttons so it works with shaky hands and fog.
class ScaleRow extends StatelessWidget {
  const ScaleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.lowText,
    required this.highText,
  });
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String lowText;
  final String highText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i <= 4; i++)
                ButtonSegment(value: i, label: Text('$i')),
            ],
            selected: value == null ? {} : {value!},
            onSelectionChanged: (s) => onChanged(s.isEmpty ? null : s.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(lowText, style: t.bodySmall),
                Text(highText, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const kDisclaimer =
    'Akku ist ein Tagebuch und eine Orientierungshilfe für das eigene '
    'Energiemanagement. Es ist kein Medizinprodukt, stellt keine Diagnose und '
    'ersetzt keine ärztliche Beratung. Der Akku-Stand ist eine Schätzung aus '
    'Puls, deinen Eingaben und Faustregeln – dein Körpergefühl geht immer vor.';
