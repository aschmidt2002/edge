import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/plus_text.dart';

Future<String> _shown(WidgetTester t, Locale locale) async {
  late String out;
  await t.pumpWidget(Localizations(
    locale: locale,
    delegates: const [GlobalWidgetsLocalizations.delegate],
    child: Builder(builder: (c) {
      out = tr(c, 'Zielgewicht', 'Target weight');
      return const SizedBox();
    }),
  ));
  return out;
}

void main() {
  testWidgets('German app language shows German, everything else English',
      (t) async {
    expect(await _shown(t, const Locale('de')), 'Zielgewicht');
    expect(await _shown(t, const Locale('en')), 'Target weight');
    expect(await _shown(t, const Locale('fr')), 'Target weight');
  });
}
