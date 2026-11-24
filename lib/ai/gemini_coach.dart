// Edge+: one Gemini key for every AI task. The key entered once (Nutrition ›
// Goals, or AI settings) is used for the meal photo estimate AND, through
// Gemini's OpenAI-compatible endpoint, for the coach. The coach logic itself
// is unchanged: it simply gets Gemini as one more Chat Completions provider.

import '../coach/coach_config.dart';
import 'food_photo.dart';

const kGeminiOpenAiBase =
    'https://generativelanguage.googleapis.com/v1beta/openai';

/// Follows Google's current Flash model, which is on the free tier.
const kGeminiCoachModel = kGeminiFlash;

bool coachUsesGemini(CoachConfig cfg) =>
    !cfg.usesChatGpt &&
    coachEndpointOrigin(cfg.baseUrl) == coachEndpointOrigin(kGeminiOpenAiBase);

/// Point the coach at Gemini with [key] and the centrally chosen model.
Future<void> useGeminiForCoach(CoachConfig cfg, String key) async =>
    cfg.save(
      useChatGpt: false,
      baseUrl: kGeminiOpenAiBase,
      api: CoachApi.chatCompletions,
      model: await geminiModel(),
      apiKey: key,
    );

/// A coach that was never set up adopts a Gemini key saved for meal photos.
/// Only when it is certain nothing was set up: no model, no ChatGPT sign-in,
/// and no coach key that merely could not be read yet.
Future<void> adoptGeminiKeyForCoach(CoachConfig cfg) async {
  if (cfg.configured ||
      cfg.usesChatGpt ||
      cfg.model.isNotEmpty ||
      cfg.keyUnreadable ||
      cfg.keyUndetermined) {
    return;
  }
  final key = await geminiKey.read();
  if (key == null) return;
  await useGeminiForCoach(cfg, key);
}

/// Mirror a key saved in the coach's own setup onto the shared Gemini key, so
/// the meal photo uses it too.
Future<void> syncGeminiKeyFromCoach(CoachConfig cfg) async {
  final k = cfg.apiKey;
  if (coachUsesGemini(cfg) && k != null && k.isNotEmpty) {
    await geminiKey.write(k);
  }
}
