import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openstrap_edge/ai/food_photo.dart';
import 'package:openstrap_edge/ai/gemini_coach.dart';
import 'package:openstrap_edge/coach/coach_config.dart';

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

  test('the coach counts as on Gemini only on the Gemini origin', () {
    expect(coachEndpointOrigin(kGeminiOpenAiBase),
        'https://generativelanguage.googleapis.com');
    expect(coachUsesGemini(CoachConfig()), isFalse); // default is OpenAI
    expect(CoachApi.defaultFor(kGeminiOpenAiBase), CoachApi.chatCompletions);
  });

  group('gemini retries', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      retryDelay = (_) => Duration.zero;
    });
    final good = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text': jsonEncode({
                  'label': 'Apfel', 'portion_g': 150, 'kcal': 80,
                  'protein_g': 0, 'carbs_g': 20, 'fat_g': 0, 'fibre_g': 3,
                  'confidence': 'high', 'questions': [], 'note': '',
                }),
              },
            ],
          },
        },
      ],
    });

    test('a 503 is retried and the answer used', () async {
      var n = 0;
      final e = await estimateFoodPhotoGemini(
        apiKey: 'k', jpeg: [1, 2, 3], lang: 'de',
        client: MockClient((r) async =>
            ++n < 3 ? http.Response('{}', 503) : http.Response(good, 200)),
      );
      expect(n, 3);
      expect(e.label, 'Apfel');
    });

    test('after the retries it falls back to the lighter model', () async {
      final urls = <String>[];
      await expectLater(
        estimateFoodPhotoGemini(
          apiKey: 'k', jpeg: [1], lang: 'de',
          client: MockClient((r) async {
            urls.add(r.url.path);
            return http.Response('{}', 503);
          }),
        ),
        throwsA(isA<FoodPhotoException>()
            .having((e) => e.message, 'message', contains('ausgelastet'))),
      );
      expect(urls.length, 5);
      expect(urls.first, contains(kGeminiFlash));
      expect(urls.last, contains(kGeminiFallback));
    });

    test('a bad key is not retried', () async {
      var n = 0;
      await expectLater(
        estimateFoodPhotoGemini(
          apiKey: 'k', jpeg: [1], lang: 'en',
          client: MockClient((r) async {
            n++;
            return http.Response('{"error":{"message":"API key not valid"}}', 400);
          }),
        ),
        throwsA(isA<FoodPhotoException>()),
      );
      expect(n, 1);
    });
  });
}
