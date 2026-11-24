// Edge+: where the user's own API keys for the meal photo estimate are
// entered (lib/ai/food_photo.dart). Gemini first, because its key is free;
// Claude is the optional alternative and only used when no Gemini key is set.
// Reached from Nutrition › Goals and from the log sheet the first time a
// photo is taken without a key.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/food_photo.dart';
import '../ui2.dart';

/// Resolves true when something was saved or removed.
Future<bool?> editFoodAiKeys(BuildContext c) async {
  final hasGemini = await geminiKey.read() != null;
  final hasClaude = await claudeKey.read() != null;
  if (!c.mounted) return null;
  return showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (_) => _FoodAiKeySheet(hasGemini: hasGemini, hasClaude: hasClaude),
  );
}

class _FoodAiKeySheet extends StatefulWidget {
  const _FoodAiKeySheet({required this.hasGemini, required this.hasClaude});
  final bool hasGemini, hasClaude;

  @override
  State<_FoodAiKeySheet> createState() => _FoodAiKeySheetState();
}

class _FoodAiKeySheetState extends State<_FoodAiKeySheet> {
  final _gemini = TextEditingController();
  final _claude = TextEditingController();
  late bool _hasGemini = widget.hasGemini;
  late bool _hasClaude = widget.hasClaude;
  late bool _showClaude = widget.hasClaude;

  @override
  void dispose() {
    _gemini.dispose();
    _claude.dispose();
    super.dispose();
  }

  Future<bool> _write(ApiKeyStore store, String v) async {
    try {
      await store.write(v);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(context, 'Konnte nicht gespeichert werden.',
                'Could not be saved.'))));
      }
      return false;
    }
  }

  Future<void> _save() async {
    var changed = false;
    if (_gemini.text.trim().isNotEmpty) {
      if (!await _write(geminiKey, _gemini.text)) return;
      changed = true;
    }
    if (_claude.text.trim().isNotEmpty) {
      if (!await _write(claudeKey, _claude.text)) return;
      changed = true;
    }
    if (mounted) Navigator.of(context).pop(changed);
  }

  Future<void> _remove(ApiKeyStore store) async {
    if (!await _write(store, '')) return;
    if (!mounted) return;
    setState(() {
      if (store == geminiKey) {
        _hasGemini = false;
      } else {
        _hasClaude = false;
      }
    });
  }

  Widget _field(BuildContext c, TextEditingController ctl, bool has,
      String placeholder) {
    final p = P.of(c);
    return TextField(
      controller: ctl,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      style: F.body.copyWith(color: p.ink),
      decoration: InputDecoration(
        hintText: has
            ? tr(c, 'Gespeichert. Neuen Key eingeben zum Ersetzen',
                'Saved. Type a new key to replace it')
            : placeholder,
        hintStyle: F.body.copyWith(color: p.ink3),
        filled: true,
        fillColor: p.card2,
        border:
            OutlineInputBorder(borderRadius: R.rMd, borderSide: BorderSide.none),
      ),
    );
  }

  Widget _link(BuildContext c, String text, String url) {
    final p = P.of(c);
    return Pressable(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(text,
          style: F.cap
              .copyWith(color: p.ink2, decoration: TextDecoration.underline)),
    );
  }

  Widget _removeLink(BuildContext c, ApiKeyStore store) {
    final p = P.of(c);
    return Pressable(
      onTap: () => _remove(store),
      child: Text(tr(c, 'Key entfernen', 'Remove key'),
          style: F.cap.copyWith(color: p.on(C.red))),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(c, 'KI für Essensfotos', 'AI for meal photos'),
                  style: F.t2.copyWith(color: p.ink)),
              const SizedBox(height: S.x3),
              Text(
                tr(
                    c,
                    'Die KI schätzt aus einem Foto Portion und Nährwerte. Das '
                        'Foto geht nur an den Anbieter deines Keys, der Key '
                        'bleibt verschlüsselt auf diesem Gerät.',
                    'The AI estimates portion and nutrition from a photo. The '
                        'photo goes only to the provider of your key, and the '
                        'key stays encrypted on this device.'),
                style: F.body.copyWith(color: p.ink2, height: 1.5),
              ),
              const SizedBox(height: S.x5),
              Text(tr(c, 'GOOGLE GEMINI (KOSTENLOS)', 'GOOGLE GEMINI (FREE)'),
                  style: F.over.copyWith(color: p.ink3)),
              const SizedBox(height: S.x2),
              _field(c, _gemini, _hasGemini, 'AIza…'),
              const SizedBox(height: S.x2),
              Text(
                tr(
                    c,
                    'Kostenloser Key mit deinem Google-Konto, ohne Kreditkarte. '
                        'Im kostenlosen Kontingent darf Google die Anfragen zur '
                        'Verbesserung seiner Dienste nutzen.',
                    'A free key with your Google account, no credit card. On '
                        'the free tier Google may use requests to improve its '
                        'services.'),
                style: F.cap.copyWith(color: p.ink3, height: 1.45),
              ),
              const SizedBox(height: S.x2),
              Row(children: [
                Expanded(
                  child: _link(
                      c,
                      tr(c, 'Key holen auf aistudio.google.com',
                          'Get a key at aistudio.google.com'),
                      'https://aistudio.google.com/apikey'),
                ),
                if (_hasGemini) _removeLink(c, geminiKey),
              ]),
              const SizedBox(height: S.x5),
              if (!_showClaude)
                Pressable(
                  onTap: () => setState(() => _showClaude = true),
                  child: Text(
                    tr(c, 'Stattdessen Claude nutzen (kostenpflichtig) …',
                        'Use Claude instead (paid) …'),
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                )
              else ...[
                Text(
                    tr(c, 'ANTHROPIC CLAUDE (OPTIONAL, KOSTENPFLICHTIG)',
                        'ANTHROPIC CLAUDE (OPTIONAL, PAID)'),
                    style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x2),
                _field(c, _claude, _hasClaude, 'sk-ant-…'),
                const SizedBox(height: S.x2),
                Text(
                  tr(
                      c,
                      'Braucht API-Guthaben auf console.anthropic.com, der '
                          'Pro-Plan reicht dafür nicht. Wird nur genutzt, wenn '
                          'kein Gemini-Key gespeichert ist.',
                      'Needs API credit at console.anthropic.com; a Pro plan '
                          'does not cover it. Used only when no Gemini key is '
                          'saved.'),
                  style: F.cap.copyWith(color: p.ink3, height: 1.45),
                ),
                const SizedBox(height: S.x2),
                Row(children: [
                  Expanded(
                    child: _link(
                        c,
                        tr(c, 'Key erstellen auf console.anthropic.com',
                            'Create a key at console.anthropic.com'),
                        'https://console.anthropic.com/settings/keys'),
                  ),
                  if (_hasClaude) _removeLink(c, claudeKey),
                ]),
              ],
              const SizedBox(height: S.x5),
              BigButton(tr(c, 'Speichern', 'Save'),
                  color: C.domFood, onTap: _save),
            ],
          ),
        ),
      ),
    );
  }
}
