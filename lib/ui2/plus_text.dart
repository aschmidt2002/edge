// Edge+ text: German and English for the features this fork adds.
//
// Upstream strings live in lib/l10n/*.arb. The fork's own strings stay out of
// those files on purpose: upstream edits them in nearly every release, and the
// daily upstream merge would conflict on every key we append. So a fork
// string is written once, both languages side by side at the call site:
//
//   Text(tr(context, 'Zielgewicht', 'Target weight'))
//
// German shows when the app language is German; every other language gets
// English (the fork only speaks these two).
// ponytail: two languages inline, no key table. If the fork ever needs a third
// language, move these pairs into a lib/l10n_plus ARB set with its own gen-l10n.

import 'package:flutter/widgets.dart';

import '../state/locale_controller.dart';

/// The fork's text in the language the app shows. Reading the locale from
/// [context] makes the widget rebuild when the user switches language.
String tr(BuildContext context, String de, String en) =>
    Localizations.localeOf(context).languageCode == 'de' ? de : en;

/// For text built outside the widget tree (notifications): same rule, from
/// the saved language setting.
Future<String> trNow(String de, String en) async =>
    await LocaleController.presentationLanguageCode() == 'de' ? de : en;
