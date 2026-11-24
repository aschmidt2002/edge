// Edge+: where the user's own Anthropic API key is entered, for the meal
// photo estimate (lib/ai/food_photo.dart). Reached from Profile and from the
// log sheet the first time a photo is taken without a key.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/food_photo.dart';
import '../ui2.dart';

/// Resolves true when a key was saved (or removed).
Future<bool?> editClaudeKey(BuildContext c) async {
  final current = await ClaudeKey.read();
  if (!c.mounted) return null;
  return showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (_) => _ClaudeKeySheet(hasKey: current != null),
  );
}

class _ClaudeKeySheet extends StatefulWidget {
  const _ClaudeKeySheet({required this.hasKey});
  final bool hasKey;

  @override
  State<_ClaudeKeySheet> createState() => _ClaudeKeySheetState();
}

class _ClaudeKeySheetState extends State<_ClaudeKeySheet> {
  final _key = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save(String v) async {
    try {
      await ClaudeKey.write(v);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(context, 'Konnte nicht gespeichert werden.',
              'Could not be saved.'))));
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(c, 'Claude-API-Key', 'Claude API key'),
                  style: F.t2.copyWith(color: p.ink)),
              const SizedBox(height: S.x3),
              Text(
                tr(
                    c,
                    'Für die Nährwert-Schätzung aus Essensfotos. Das Foto wird '
                        'nur mit deinem eigenen Key an Anthropic geschickt. Der '
                        'Key bleibt verschlüsselt auf diesem Gerät. Jede '
                        'Schätzung kostet ein paar Cent auf deinem '
                        'Anthropic-Konto.',
                    'For nutrition estimates from meal photos. The photo is '
                        'sent only to Anthropic, with your own key. The key '
                        'stays encrypted on this device. Each estimate costs '
                        'a few cents on your Anthropic account.'),
                style: F.body.copyWith(color: p.ink2, height: 1.5),
              ),
              const SizedBox(height: S.x4),
              TextField(
                controller: _key,
                obscureText: _hide,
                autocorrect: false,
                enableSuggestions: false,
                style: F.body.copyWith(color: p.ink),
                decoration: InputDecoration(
                  hintText: widget.hasKey
                      ? tr(c, 'Gespeichert. Neuen Key eingeben zum Ersetzen',
                          'Saved. Type a new key to replace it')
                      : 'sk-ant-…',
                  hintStyle: F.body.copyWith(color: p.ink3),
                  filled: true,
                  fillColor: p.card2,
                  border: OutlineInputBorder(
                      borderRadius: R.rMd, borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility : Icons.visibility_off,
                        color: p.ink3),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: S.x2),
              Pressable(
                onTap: () => launchUrl(
                    Uri.parse('https://console.anthropic.com/settings/keys'),
                    mode: LaunchMode.externalApplication),
                child: Text(
                  tr(c, 'Key erstellen auf console.anthropic.com',
                      'Create a key at console.anthropic.com'),
                  style: F.cap.copyWith(
                      color: p.ink2, decoration: TextDecoration.underline),
                ),
              ),
              const SizedBox(height: S.x5),
              BigButton(tr(c, 'Speichern', 'Save'),
                  color: C.domFood,
                  onTap: () {
                    if (_key.text.trim().isEmpty) {
                      Navigator.of(c).pop(false);
                    } else {
                      _save(_key.text);
                    }
                  }),
              if (widget.hasKey) ...[
                const SizedBox(height: S.x3),
                BigButton(tr(c, 'Key entfernen', 'Remove key'),
                    color: C.red, soft: true, onTap: () => _save('')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
