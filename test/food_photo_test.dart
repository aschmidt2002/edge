import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ai/food_photo.dart';

void main() {
  String ok(Map<String, dynamic> est) => jsonEncode({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'thinking', 'thinking': ''},
          {'type': 'text', 'text': jsonEncode(est)},
        ],
      });

  test('reads the estimate from the text block', () {
    final e = parseFoodPhotoResponse(
        200,
        ok({
          'label': 'Spaghetti',
          'portion_g': 350,
          'kcal': 620.4,
          'protein_g': 22,
          'carbs_g': 80,
          'fat_g': 18,
          'fibre_g': 6,
          'confidence': 'medium',
          'questions': ['Mit Käse?', '', 'a', 'b', 'c'],
          'note': '',
        }));
    expect(e.label, 'Spaghetti');
    expect(e.kcal, 620.4);
    expect(e.portionG, 350);
    expect(e.questions, ['Mit Käse?', 'a', 'b']);
  });

  test('negative or missing numbers become unknown', () {
    final e = FoodPhotoEstimate.fromJson({'label': 'x', 'kcal': -5});
    expect(e.kcal, isNull);
    expect(e.proteinG, isNull);
  });

  test('a rejected key says so', () {
    expect(
        () => parseFoodPhotoResponse(401, '{"error":{"message":"bad"}}',
            lang: 'de'),
        throwsA(isA<FoodPhotoException>().having(
            (e) => e.message, 'message', contains('API-Key'))));
  });

  test('a refusal is an error, not an empty estimate', () {
    expect(
        () => parseFoodPhotoResponse(
            200, '{"stop_reason":"refusal","content":[]}'),
        throwsA(isA<FoodPhotoException>()));
  });

  group('gemini', () {
    String ok(Map<String, dynamic> est) => jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'thinking…', 'thought': true},
                  {'text': jsonEncode(est)},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        });

    test('reads the estimate, skipping thought parts', () {
      final e = parseGeminiResponse(
          200,
          ok({
            'label': 'Müsli',
            'portion_g': 250,
            'kcal': 410,
            'protein_g': 14,
            'carbs_g': 60,
            'fat_g': 11,
            'fibre_g': 8,
            'confidence': 'high',
            'questions': [],
            'note': '',
          }));
      expect(e.label, 'Müsli');
      expect(e.kcal, 410);
      expect(e.questions, isEmpty);
    });

    test('a used-up free quota says so', () {
      expect(
          () => parseGeminiResponse(429, '{"error":{"message":"quota"}}',
              lang: 'de'),
          throwsA(isA<FoodPhotoException>()
              .having((e) => e.message, 'message', contains('Kontingent'))));
    });

    test('an invalid key says so', () {
      expect(
          () => parseGeminiResponse(
              400, '{"error":{"message":"API key not valid."}}'),
          throwsA(isA<FoodPhotoException>()
              .having((e) => e.message, 'message', contains('Gemini key'))));
    });

    test('a blocked prompt is an error', () {
      expect(
          () => parseGeminiResponse(
              200, '{"promptFeedback":{"blockReason":"SAFETY"}}'),
          throwsA(isA<FoodPhotoException>()));
    });
  });
}
