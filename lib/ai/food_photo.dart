// Edge+: estimate a meal's nutrition from a photo with Claude.
//
// BYOK: the user's own Anthropic API key, stored in the platform
// keychain/keystore and sent only to api.anthropic.com. The photo goes to the
// same place and nowhere else; it is not kept on the device.
//
// The answer is an ESTIMATE and is treated as one: it pre-fills the log form,
// the user can correct it or answer a short follow-up question, and only a
// tap on Save writes it (as FoodSource.photo, confirmed).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// The user's Anthropic API key. Same keychain options as the coach key, so a
/// background relaunch on a locked phone can still read it.
class ClaudeKey {
  static const _k = 'claude_api_key';
  static const _s = FlutterSecureStorage();
  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static Future<String?> read() async {
    try {
      final v = await _s.read(key: _k, iOptions: _ios);
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    } catch (_) {
      return null;
    }
  }

  /// Empty deletes.
  static Future<void> write(String key) async {
    final v = key.trim();
    if (v.isEmpty) {
      await _s.delete(key: _k, iOptions: _ios);
    } else {
      await _s.write(key: _k, value: v, iOptions: _ios);
    }
  }
}

/// One follow-up question and the user's answer to it.
class FoodQa {
  const FoodQa(this.question, this.answer);
  final String question;
  final String answer;
}

class FoodPhotoEstimate {
  const FoodPhotoEstimate({
    required this.label,
    required this.portionG,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fibreG,
    required this.confidence,
    required this.questions,
    required this.note,
  });

  final String label;
  final double? portionG, kcal, proteinG, carbsG, fatG, fibreG;

  /// 'low' | 'medium' | 'high'
  final String confidence;

  /// Short questions whose answers would change the estimate. Empty when
  /// there is nothing worth asking.
  final List<String> questions;
  final String note;

  static double? _d(Object? v) {
    if (v is! num) return null;
    final d = v.toDouble();
    return (d.isFinite && d >= 0) ? d : null;
  }

  static FoodPhotoEstimate fromJson(Map<String, dynamic> j) => FoodPhotoEstimate(
        label: (j['label'] as String? ?? '').trim(),
        portionG: _d(j['portion_g']),
        kcal: _d(j['kcal']),
        proteinG: _d(j['protein_g']),
        carbsG: _d(j['carbs_g']),
        fatG: _d(j['fat_g']),
        fibreG: _d(j['fibre_g']),
        confidence: j['confidence'] as String? ?? 'low',
        questions: [
          for (final q in (j['questions'] as List? ?? const []))
            if (q is String && q.trim().isNotEmpty) q.trim(),
        ].take(3).toList(),
        note: (j['note'] as String? ?? '').trim(),
      );
}

class FoodPhotoException implements Exception {
  FoodPhotoException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _model = 'claude-opus-5-5';
const _endpoint = 'https://api.anthropic.com/v1/messages';

const _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': [
    'label',
    'portion_g',
    'kcal',
    'protein_g',
    'carbs_g',
    'fat_g',
    'fibre_g',
    'confidence',
    'questions',
    'note',
  ],
  'properties': {
    'label': {'type': 'string'},
    'portion_g': {'type': 'number'},
    'kcal': {'type': 'number'},
    'protein_g': {'type': 'number'},
    'carbs_g': {'type': 'number'},
    'fat_g': {'type': 'number'},
    'fibre_g': {'type': 'number'},
    'confidence': {
      'type': 'string',
      'enum': ['low', 'medium', 'high'],
    },
    'questions': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'note': {'type': 'string'},
  },
};

String _system(String lang) => '''
You estimate the nutrition of a meal from one photo for a personal food log.

Estimate what is actually on the plate or in the picture (the whole visible
portion, as eaten), not a per-100 g value. Use visual cues such as plate size,
cutlery and packaging to judge the amount. Hidden fat (oil, butter, sauces)
is the most common source of error, so account for it.

Fields:
- label: a short name for the meal, e.g. "Spaghetti Bolognese".
- portion_g: total weight of the food in grams.
- kcal, protein_g, carbs_g, fat_g, fibre_g: totals for that portion.
- confidence: how sure you are of the energy figure.
- questions: at most 2 short questions whose answer would change the
  estimate noticeably (e.g. "Was it fried in oil?", "Is the drink sugar-free?").
  Leave empty when the photo is clear enough, or when the user has already
  answered questions.
- note: one short sentence on what you assumed. Empty if nothing notable.

If the photo shows no food, set label to "" and every number to 0.

Write label, questions and note in ${lang == 'de' ? 'German' : 'English'}.
''';

/// Send [jpeg] to Claude and return its estimate. [answers] are earlier
/// follow-up questions with the user's answers; with them the request is
/// made again from the same photo.
Future<FoodPhotoEstimate> estimateFoodPhoto({
  required String apiKey,
  required List<int> jpeg,
  required String lang,
  String mediaType = 'image/jpeg',
  List<FoodQa> answers = const [],
  String hint = '',
  http.Client? client,
}) async {
  final text = StringBuffer('Estimate the nutrition of this meal.');
  if (hint.trim().isNotEmpty) {
    text.write('\nThe user says it is: ${hint.trim()}');
  }
  if (answers.isNotEmpty) {
    text.write('\nAnswers to your earlier questions:');
    for (final a in answers) {
      text.write('\n- ${a.question} ${a.answer}');
    }
    text.write('\nUse these answers. Do not ask further questions.');
  }

  final body = {
    'model': _model,
    'max_tokens': 16000,
    'fallbacks': 'default',
    'thinking': {'type': 'adaptive'},
    'output_config': {
      'effort': 'medium',
      'format': {'type': 'json_schema', 'schema': _schema},
    },
    'system': _system(lang),
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': mediaType,
              'data': base64Encode(jpeg),
            },
          },
          {'type': 'text', 'text': text.toString()},
        ],
      },
    ],
  };

  final c = client ?? http.Client();
  final http.Response res;
  try {
    res = await c
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2026-10-21',
            'anthropic-beta': 'server-side-fallback-2026-07-01',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));
  } catch (e) {
    throw FoodPhotoException(lang == 'de'
        ? 'Claude ist nicht erreichbar. Prüfe die Internetverbindung.'
        : 'Could not reach Claude. Check your connection.');
  } finally {
    if (client == null) c.close();
  }
  return parseFoodPhotoResponse(res.statusCode, utf8.decode(res.bodyBytes),
      lang: lang);
}

/// Split out so the error handling can be tested without the network.
FoodPhotoEstimate parseFoodPhotoResponse(int status, String raw,
    {String lang = 'en'}) {
  final de = lang == 'de';
  Map<String, dynamic>? j;
  try {
    j = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {}
  if (status != 200) {
    final msg = (j?['error'] as Map?)?['message'] as String?;
    if (status == 401) {
      throw FoodPhotoException(de
          ? 'Der API-Key wurde abgelehnt. Prüfe ihn in den Einstellungen.'
          : 'The API key was rejected. Check it in the settings.');
    }
    if (status == 429 || status == 529) {
      throw FoodPhotoException(de
          ? 'Claude ist gerade ausgelastet. Versuch es gleich nochmal.'
          : 'Claude is busy right now. Try again in a moment.');
    }
    throw FoodPhotoException(
        '${de ? 'Fehler' : 'Error'} $status${msg == null ? '' : ': $msg'}');
  }
  if (j == null) {
    throw FoodPhotoException(de ? 'Unlesbare Antwort.' : 'Unreadable answer.');
  }
  if (j['stop_reason'] == 'refusal') {
    throw FoodPhotoException(de
        ? 'Claude hat dieses Foto nicht ausgewertet.'
        : 'Claude declined to read this photo.');
  }
  final text = [
    for (final b in (j['content'] as List? ?? const []))
      if (b is Map && b['type'] == 'text') b['text'] as String? ?? '',
  ].join();
  try {
    return FoodPhotoEstimate.fromJson(
        jsonDecode(text) as Map<String, dynamic>);
  } catch (_) {
    throw FoodPhotoException(de ? 'Unlesbare Antwort.' : 'Unreadable answer.');
  }
}
