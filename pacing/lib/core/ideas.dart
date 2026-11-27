// Activity ideas for what is left in the battery. Ideas, not advice: what is
// "light" differs a lot between people (crocheting is restful for one person
// and a brain-fog trigger for another), so every idea carries the kinds of
// effort it costs and the person can hide ideas that do not fit. The lists
// follow the logic of the NICE severity descriptions: the more severe, the
// more the ideas are about lying down, low stimulation and rest itself.

import 'models.dart';

class ActivityIdea {
  const ActivityIdea(this.id, this.label, this.kinds, this.cost,
      {this.minSeverityIndexAllowed = 3, this.hint});
  final String id;
  final String label;
  final Set<EffortKind> kinds;

  /// 0 = rest, 1 = very light, 2 = light, 3 = moderate (for this illness).
  final int cost;

  /// Hidden when severity index is greater than this (0 mild … 3 very severe).
  final int minSeverityIndexAllowed;
  final String? hint;
}

const kIdeas = <ActivityIdea>[
  ActivityIdea('rest_dark', 'Liegen im abgedunkelten, ruhigen Raum', {}, 0,
      hint: 'Echte Ruhe: Augen zu, kein Bildschirm, keine Geräusche.'),
  ActivityIdea('breathing', 'Ruhige Atemübung im Liegen', {}, 0),
  ActivityIdea('audio_soft', 'Leise Musik oder Hörbuch im Liegen',
      {EffortKind.cognitive}, 1,
      hint: 'Kurz halten, Lautstärke niedrig.'),
  ActivityIdea('window', 'Aus dem Fenster schauen', {}, 1),
  ActivityIdea('message_short', 'Eine kurze Nachricht schreiben',
      {EffortKind.cognitive, EffortKind.emotional}, 1),
  ActivityIdea('crochet', 'Häkeln oder Stricken (kurz, mit Pausen)',
      {EffortKind.cognitive, EffortKind.physical}, 2,
      minSeverityIndexAllowed: 2,
      hint: 'Feinmotorik und Konzentration kosten auch Energie.'),
  ActivityIdea('read_short', 'Ein paar Seiten lesen',
      {EffortKind.cognitive}, 2,
      minSeverityIndexAllowed: 2),
  ActivityIdea('puzzle_easy', 'Leichtes Rätsel oder Malbuch',
      {EffortKind.cognitive}, 2,
      minSeverityIndexAllowed: 2),
  ActivityIdea('call_short', 'Kurzes Telefonat (im Liegen)',
      {EffortKind.cognitive, EffortKind.emotional}, 2,
      minSeverityIndexAllowed: 2),
  ActivityIdea('shower_seated', 'Duschen im Sitzen',
      {EffortKind.physical, EffortKind.orthostatic}, 2,
      minSeverityIndexAllowed: 2,
      hint: 'Warmes Wasser und Stehen belasten den Kreislauf.'),
  ActivityIdea('cook_seated', 'Einfaches Essen im Sitzen vorbereiten',
      {EffortKind.physical, EffortKind.orthostatic}, 3,
      minSeverityIndexAllowed: 1),
  ActivityIdea('walk_short', 'Kurzer, langsamer Spaziergang unter der Pulsgrenze',
      {EffortKind.physical, EffortKind.orthostatic}, 3,
      minSeverityIndexAllowed: 1,
      hint: 'Nur wenn es sich in den letzten Tagen bewährt hat. Pulsgrenze im Blick.'),
  ActivityIdea('nature_sit', 'Draußen sitzen, Natur anschauen',
      {EffortKind.orthostatic}, 2,
      minSeverityIndexAllowed: 1),
  ActivityIdea('hobby_desk', 'Hobby am Tisch (z. B. Zeichnen)',
      {EffortKind.cognitive, EffortKind.physical}, 3,
      minSeverityIndexAllowed: 1),
];

/// Ideas that fit [severity] and the battery share left. Below 15 % only
/// rest is offered: with nothing left, the honest suggestion is to stop.
List<ActivityIdea> ideasFor(Severity severity, double batteryShare,
    {Set<String> hidden = const {}, bool inCrash = false}) {
  final sev = severity.index;
  final int maxCost;
  if (inCrash || batteryShare < 0.15) {
    maxCost = 0;
  } else if (batteryShare < 0.35) {
    maxCost = 1;
  } else if (batteryShare < 0.6) {
    maxCost = 2;
  } else {
    maxCost = 3;
  }
  return kIdeas
      .where((i) =>
          !hidden.contains(i.id) &&
          i.cost <= maxCost &&
          sev <= i.minSeverityIndexAllowed)
      .toList();
}
