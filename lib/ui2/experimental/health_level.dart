// EXPERIMENTELL — Gesundheitslevel: how far last night sat from your normal,
// read as a chance of getting ill, and corrected by what you say.
//
// Four overnight signals the app already stores (resting HR, HRV, breathing
// rate, skin temperature), each as a z-score against your own previous four
// weeks, signed so that "towards ill" is positive. A small logistic model turns
// them into a risk; the level is 100 minus that risk in percent.
//
// It learns from you: a day you mark ill (here, or the "sick" tag in the
// journal) and a day you say you are fine are labels, and the weights are
// refit from them on every read. The answer here is written into the journal
// too, so the two places never disagree.
//
// Not a diagnosis, and the screen says so.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/decimal_text.dart';
import '../activity/recovery_card.dart' show RecoveryRead, loadRecovery;
import '../screens/home_screen.dart' show readinessBand;
import '../ui2.dart';
import 'xp_core.dart';
import 'xp_features.dart';

/// The four signals, in model order. `skin_temp` is already stored as a z.
const kHealthSignals = ['resting_hr', 'hrv', 'resp_rate', 'skin_temp'];

/// +1 where a RISE points towards illness, -1 where a fall does (HRV).
const _sign = [1.0, -1.0, 1.0, 1.0];

/// The starting weights (one per signal, then the bias) before any answer of
/// yours. A night at your normal reads ~5 % risk; resting HR +2σ with HRV
/// -1.5σ reads well over half.
const kHealthPrior = [1.0, 0.8, 0.6, 0.6, -3.0];

/// Where answers are kept: `{ 'YYYY-MM-DD': true (ill) | false (fine) }`.
const _kFeedback = 'health_feedback';

/// [day]'s z for one signal against the 28 days before it, signed towards
/// illness and clamped to ±4. Null without a value or five days of history.
double? healthZ(Map<String, double>? s, String key, String day) {
  final v = s?[day];
  if (v == null) return null;
  final i = kHealthSignals.indexOf(key);
  if (key == 'skin_temp') return (v * _sign[i]).clamp(-4.0, 4.0);
  final from = dayLabelBefore(day, 28) ?? '';
  final prior = [
    for (final e in s!.entries)
      if (e.key.compareTo(day) < 0 && e.key.compareTo(from) >= 0) e.value,
  ];
  if (prior.length < 5) return null;
  final mean = prior.reduce((a, b) => a + b) / prior.length;
  final sd = math.sqrt(
    prior.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
        prior.length,
  );
  // A floor, so a very steady month does not turn one beat into 4σ.
  final floor = switch (key) {
    'resting_hr' => 1.0,
    'hrv' => math.max(2.0, mean * .05),
    _ => 0.3,
  };
  return ((v - mean) / math.max(sd, floor) * _sign[i]).clamp(-4.0, 4.0);
}

/// Every day's signed z's, keyed by day, from `{signal: {day: value}}`.
Map<String, List<double?>> healthFeatures(
  Map<String, Map<String, double>> series,
) {
  final days = {for (final s in series.values) ...s.keys};
  return {
    for (final d in days)
      d: [for (final k in kHealthSignals) healthZ(series[k], k, d)],
  };
}

/// The chance of illness for one day's z's. A missing signal counts as normal.
double healthRisk(List<double?> x, [List<double> w = kHealthPrior]) {
  var s = w.last;
  for (var i = 0; i < x.length; i++) {
    s += w[i] * (x[i] ?? 0);
  }
  return 1 / (1 + math.exp(-s));
}

/// The weights refit to your answers: logistic regression pulled towards
/// [kHealthPrior], the pull fading as answers pile up.
// ponytail: plain batch gradient descent on a handful of labels, no
// validation split. Upgrade path: move the model to analytics once there are
// enough labelled days to check it against.
List<double> learnHealthWeights(List<(List<double?>, bool)> labels) {
  final w = [...kHealthPrior];
  if (labels.isEmpty) return w;
  final n = labels.length;
  final pull = 1.0 / (1 + n);
  for (var epoch = 0; epoch < 400; epoch++) {
    final g = List.filled(w.length, 0.0);
    for (final (x, ill) in labels) {
      final e = healthRisk(x, w) - (ill ? 1 : 0);
      for (var i = 0; i < x.length; i++) {
        g[i] += e * (x[i] ?? 0);
      }
      g[x.length] += e;
    }
    for (var i = 0; i < w.length; i++) {
      w[i] -= .2 * (g[i] / n + pull * (w[i] - kHealthPrior[i]));
    }
  }
  return w;
}

int healthLevelOf(double risk) => (100 * (1 - risk)).round().clamp(0, 100);

({String word, Color color}) healthBand(BuildContext c, int level) =>
    level >= 75
    ? (word: tr(c, 'Gesund', 'Healthy'), color: C.green)
    : level >= 50
    ? (word: tr(c, 'Leicht belastet', 'Slightly strained'), color: C.yellow)
    : level >= 25
    ? (
        word: tr(c, 'Erhöhtes Krankheitsrisiko', 'Raised illness risk'),
        color: C.orange,
      )
    : (
        word: tr(c, 'Hohes Krankheitsrisiko', 'High illness risk'),
        color: C.red,
      );

class HealthLevel {
  /// The night the level is about, or null when none of the last two days has
  /// a signal.
  final String? day;
  final List<double?> x;
  final double? risk;
  final int? level;

  /// How many of your answers the weights were fitted to.
  final int answers;

  /// Your answer for today, null when you gave none.
  final bool? todayAnswer;

  /// Recent days, oldest first: (day, level, your answer).
  final List<(String, int, bool?)> history;

  const HealthLevel(
    this.day,
    this.x,
    this.risk,
    this.level,
    this.answers,
    this.todayAnswer,
    this.history,
  );
}

/// Your answers: the journal's "sick" tag, then this screen's, which win.
Future<Map<String, bool>> healthAnswers(LocalRepository repo) async {
  final out = <String, bool>{};
  try {
    for (final e in await repo.getJournal(range: '180d')) {
      final tags = (e['tags'] as List?)?.map((t) => t.toString()) ?? const [];
      if (tags.contains('sick')) out[e['date'].toString()] = true;
    }
  } catch (_) {}
  xpGet(_kFeedback).forEach((k, v) {
    if (v is bool) out[k] = v;
  });
  return out;
}

/// Records [ill] for [day] and writes the journal's "sick" tag to match.
Future<void> setHealthAnswer(LocalRepository repo, String day, bool ill) async {
  xpSet(_kFeedback, {...xpGet(_kFeedback), day: ill});
  Map<String, dynamic>? row;
  for (final e in await repo.getJournal(range: '7d')) {
    if (e['date'] == day) row = e;
  }
  final tags = {...?(row?['tags'] as List?)?.map((t) => t.toString())};
  if ((ill ? tags.add('sick') : tags.remove('sick'))) {
    await repo.postJournal(day, tags.toList(), (row?['note'] as String?) ?? '');
  }
}

Future<HealthLevel> loadHealthLevel(LocalRepository repo) async {
  final series = {
    for (final k in kHealthSignals)
      k: {
        for (final (t, v) in await xpSeries(repo, k, days: 150))
          dayLabelOf(t): v,
      },
  };
  final feats = healthFeatures(series);
  final answers = await healthAnswers(repo);
  final labels = [
    for (final e in answers.entries)
      if (feats[e.key] case final x? when x.any((v) => v != null)) (x, e.value),
  ];
  final w = learnHealthWeights(labels);
  final today = todayLabel();
  final day = [today, dayLabelBefore(today, 1)].firstWhere(
    (d) => feats[d]?.any((v) => v != null) ?? false,
    orElse: () => null,
  );
  final x = day == null ? const <double?>[] : feats[day]!;
  final risk = day == null ? null : healthRisk(x, w);
  final history = <(String, int, bool?)>[];
  for (var i = 13; i >= 0; i--) {
    final d = dayLabelBefore(today, i);
    final f = d == null ? null : feats[d];
    if (f != null && f.any((v) => v != null)) {
      history.add((d!, healthLevelOf(healthRisk(f, w)), answers[d]));
    }
  }
  return HealthLevel(
    day,
    x,
    risk,
    risk == null ? null : healthLevelOf(risk),
    labels.length,
    answers[today],
    history,
  );
}

String _signalName(BuildContext c, String k) => switch (k) {
  'resting_hr' => tr(c, 'Ruhepuls', 'Resting HR'),
  'hrv' => 'HRV',
  'resp_rate' => tr(c, 'Atemfrequenz', 'Breathing rate'),
  _ => tr(c, 'Hauttemperatur', 'Skin temperature'),
};

IconData _signalIcon(String k) => switch (k) {
  'resting_hr' => LucideIcons.heart,
  'hrv' => LucideIcons.activity,
  'resp_rate' => LucideIcons.wind,
  _ => LucideIcons.thermometer,
};

/// The Gesundheitslevel screen.
Future<List<Widget>> loadHealthLevelScreen(
  BuildContext c,
  LocalRepository repo,
  VoidCallback reload,
) async {
  final h = await loadHealthLevel(repo);
  if (!c.mounted) return const [];
  final p = P.of(c);
  final today = todayLabel();

  Widget answer(bool ill, String text, IconData icon) => Pressable(
    onTap: () async {
      await setHealthAnswer(repo, today, ill);
      reload();
    },
    semanticLabel: text,
    child: Pill(
      text,
      h.todayAnswer == ill ? (ill ? C.red : C.green) : C.n400,
      icon: h.todayAnswer == ill ? LucideIcons.check : icon,
    ),
  );

  return [
    if (h.level == null)
      xpNote(
        c,
        tr(
          c,
          'Noch kein Wert: es braucht eine Nacht mit Ruhepuls, HRV, '
              'Atemfrequenz oder Hauttemperatur und fünf Nächte davor als Vergleich.',
          'No level yet: it needs a night with resting HR, HRV, breathing '
              'rate or skin temperature, and five nights before it to compare.',
        ),
      )
    else
      xpStat(
        c,
        tr(c, 'Gesundheitslevel', 'Health level'),
        '${h.level}',
        sub:
            '${healthBand(c, h.level!).word} · '
            '${tr(c, 'Krankheitsrisiko', 'Illness risk')} '
            '${(h.risk! * 100).round()} %',
        color: healthBand(c, h.level!).color,
      ),
    const SizedBox(height: S.x3),
    Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(c, 'Wie geht es dir heute?', 'How are you today?'),
            style: F.head.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x1),
          Text(
            tr(
              c,
              'Deine Antwort landet auch im Journal und verbessert die Prognose.',
              'Your answer goes into the journal too and trains the prediction.',
            ),
            style: F.cap.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              answer(
                true,
                tr(c, 'Ich bin krank', 'I am ill'),
                LucideIcons.thermometer,
              ),
              answer(
                false,
                tr(c, 'Mir geht es gut', 'I feel fine'),
                LucideIcons.smile,
              ),
            ],
          ),
        ],
      ),
    ),
    if (h.day != null)
      xpSection(tr(c, 'Was reinspielt', 'What feeds it'), [
        for (var i = 0; i < kHealthSignals.length; i++)
          if (h.x[i] case final z?)
            Row(
              children: [
                Icon(_signalIcon(kHealthSignals[i]), size: 18, color: p.ink2),
                const SizedBox(width: S.x2),
                Expanded(
                  child: xpBar(
                    c,
                    _signalName(c, kHealthSignals[i]),
                    z.abs() / 3,
                    z.abs() < .5
                        ? tr(c, 'normal', 'normal')
                        : '${z > 0 ? tr(c, 'auffällig', 'off') : tr(c, 'besser', 'better')} '
                              '${z.abs().toStringAsFixed(1)} σ',
                    color: z > 1
                        ? C.red
                        : z > .5
                        ? C.orange
                        : C.green,
                  ),
                ),
              ],
            ),
      ]),
    if (h.history.length >= 2)
      xpSection(tr(c, 'Letzte 14 Tage', 'Last 14 days'), [
        xpStrip(
          c,
          [for (final e in h.history) e.$2.toDouble()],
          100,
          (v) => healthBand(c, v.round()).color,
          left: prettyShort(h.history.first.$1),
          right: prettyShort(h.history.last.$1),
        ),
        if (h.history.where((e) => e.$3 == true).isNotEmpty)
          xpNote(
            c,
            '${tr(c, 'Als krank markiert', 'Marked ill')}: '
            '${h.history.where((e) => e.$3 == true).map((e) => prettyShort(e.$1)).join(', ')}',
          ),
      ]),
    xpNote(
      c,
      '${tr(c, 'Gelernt aus ${h.answers} eigenen Angaben.', 'Learned from ${h.answers} answers of yours.')} '
      '${tr(c, 'Der Journal-Tag „Krank“ zählt mit. Keine Diagnose.', 'The journal tag "sick" counts too. Not a diagnosis.')}',
    ),
  ];
}

/// "2026-11-24" → "24.11.".
String prettyShort(String day) {
  final p = day.split('-');
  return p.length == 3 ? '${p[2]}.${p[1]}.' : day;
}

void openHealthLevel(BuildContext c) => Navigator.of(c).push(
  MaterialPageRoute<void>(
    builder: (_) => XpScreen(
      tr(c, 'Gesundheitslevel', 'Health level'),
      loadHealthLevelScreen,
    ),
  ),
);

/// The small button in Home's header that opens [showHealthReport].
class HealthReportButton extends StatelessWidget {
  const HealthReportButton({super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: () => showHealthReport(c),
      semanticLabel: tr(c, 'Mini-Gesundheitsbericht', 'Mini health report'),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.card2),
        child: Icon(LucideIcons.clipboardPlus, size: 18, color: p.ink2),
      ),
    );
  }
}

/// The mini health report: the health level first, then today's key numbers.
Future<void> showHealthReport(BuildContext c) {
  final repo = xpRepo(c);
  final read = repo == null
      ? null
      : Future.wait<Object?>([loadRecovery(c), loadHealthLevel(repo)]);
  return showModalBottomSheet<void>(
    context: c,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: P.of(c).bg,
    builder: (sc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x4),
        child: FutureBuilder<List<Object?>>(
          future: read,
          builder: (sc, snap) {
            final p = P.of(sc);
            if (read == null) {
              return xpNote(
                sc,
                tr(sc, 'Keine Daten verfügbar.', 'No data available.'),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(S.x8),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final r = snap.data![0] as RecoveryRead?;
            final h = snap.data![1] as HealthLevel;
            final d = r?.d;
            final l = AppLocalizations.of(sc);
            final band = h.level == null ? null : healthBand(sc, h.level!);
            String n(num? v, [int dp = 0, String unit = '']) =>
                v == null ? '–' : '${displayFixed(v, dp)}$unit';
            final tiles = <(IconData, Color, String, String)>[
              (
                LucideIcons.batteryCharging,
                readinessBand(d?.readiness.value, l).color,
                'Recovery',
                n(d?.readiness.value, 0, ' %'),
              ),
              (
                LucideIcons.moon,
                C.blue,
                tr(sc, 'Schlaf', 'Sleep'),
                d?.sleepMin.value == null ? '–' : hmText(d!.sleepMin.value!),
              ),
              (
                LucideIcons.heart,
                C.red,
                tr(sc, 'Ruhepuls', 'Resting HR'),
                n(d?.rhr.value, 0, ' bpm'),
              ),
              (LucideIcons.activity, C.green, 'HRV', n(d?.hrvMs, 0, ' ms')),
              (
                LucideIcons.wind,
                C.blue,
                tr(sc, 'Atemfrequenz', 'Breathing'),
                n(d?.respRate, 1, '/min'),
              ),
              (
                LucideIcons.thermometer,
                C.orange,
                tr(sc, 'Hauttemp.', 'Skin temp'),
                d?.skinDevC != null
                    ? '${d!.skinDevC! >= 0 ? '+' : ''}${displayFixed(d.skinDevC!, 1)} °C'
                    : n(d?.skinZ, 1),
              ),
              (LucideIcons.zap, C.purple, 'Strain', n(d?.strain.value, 1)),
              (
                LucideIcons.activity,
                r?.stress == null ? C.n400 : stressColor(r!.stress!),
                'Stress',
                n(r?.stress, 1),
              ),
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Surface(
                  onTap: () {
                    Navigator.of(sc).pop();
                    openHealthLevel(c);
                  },
                  semanticLabel: tr(sc, 'Gesundheitslevel', 'Health level'),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.shieldPlus,
                        size: 26,
                        color: p.on(band?.color ?? C.n400),
                      ),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(sc, 'Gesundheitslevel', 'Health level'),
                              style: F.cap.copyWith(color: p.ink2),
                            ),
                            Text(
                              band?.word ??
                                  tr(sc, 'Noch kein Wert', 'No level yet'),
                              style: F.head.copyWith(color: p.ink),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        h.level == null ? '–' : '${h.level}',
                        style: F.n34.copyWith(
                          color: p.on(band?.color ?? C.n400),
                        ),
                      ),
                      const SizedBox(width: S.x1),
                      Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
                    ],
                  ),
                ),
                const SizedBox(height: S.x3),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: S.x2,
                  crossAxisSpacing: S.x2,
                  childAspectRatio: 2.6,
                  children: [
                    for (final (icon, color, label, value) in tiles)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: S.x3),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: R.rLg,
                        ),
                        child: Row(
                          children: [
                            Icon(icon, size: 18, color: p.on(color)),
                            const SizedBox(width: S.x2),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: F.cap.copyWith(color: p.ink2),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      value,
                                      style: F.head.copyWith(color: p.ink),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
