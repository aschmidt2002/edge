// EXPERIMENTELL — the experiments themselves, one screen each.
//
// Each screen is an [XpScreen]: a loader that turns stored data into a list of
// widgets, re-run by pull-to-refresh. Absent data says so instead of guessing.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../activity/catalogue.dart' show exerciseByKey;
import '../screens/metric_detail.dart' show detailScaffold;
import '../ui2.dart';
import 'xp_core.dart';

// ── frame ────────────────────────────────────────────────────────────────────

typedef XpLoader = Future<List<Widget>> Function(
    BuildContext c, LocalRepository repo, VoidCallback reload);

class XpScreen extends StatefulWidget {
  final String title;
  final XpLoader load;
  const XpScreen(this.title, this.load, {super.key});

  @override
  State<XpScreen> createState() => _XpScreenState();
}

class _XpScreenState extends State<XpScreen> {
  List<Widget>? _body;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = xpRepo(context);
    if (repo == null) {
      setState(() => _body = [xpNote(context, tr(context, 'Keine Daten verfügbar.', 'No data available.'))]);
      return;
    }
    try {
      final body = await widget.load(context, repo, _reload);
      if (mounted) setState(() => (_body = body, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext c) {
    final body = _error != null
        ? [xpNote(c, tr(c, 'Konnte nicht geladen werden: $_error', 'Could not load: $_error'))]
        : _body ??
            const [
              Padding(
                  padding: EdgeInsets.all(S.x8),
                  child: Center(child: CircularProgressIndicator()))
            ];
    return detailScaffold(c, widget.title, [
      const SizedBox(height: S.x3),
      Align(alignment: Alignment.centerLeft, child: Pill(tr(c, 'Experimentell', 'Experimental'), C.orange)),
      ...body,
    ]);
  }
}

Widget xpNote(BuildContext c, String text) {
  final p = P.of(c);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: S.x3),
    child: Text(text, style: F.cap.copyWith(color: p.ink2)),
  );
}

/// A big number with a label, the one card shape every experiment uses.
Widget xpStat(BuildContext c, String label, String value,
    {String sub = '', Color color = C.blue}) {
  final p = P.of(c);
  return Padding(
    padding: const EdgeInsets.only(top: S.x3),
    child: Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(height: S.x1),
        Text(value, style: F.n34.copyWith(color: p.on(color))),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: S.x1),
          Text(sub, style: F.body.copyWith(color: p.ink)),
        ],
      ]),
    ),
  );
}

/// A labelled bar, for "x of y" and per-group comparisons.
Widget xpBar(BuildContext c, String label, double frac, String value,
    {Color color = C.blue}) {
  final p = P.of(c);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: S.x2),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: F.body.copyWith(color: p.ink))),
        Text(value, style: F.body.copyWith(color: p.ink2)),
      ]),
      const SizedBox(height: S.x1),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: frac.clamp(0.0, 1.0),
          minHeight: 8,
          backgroundColor: p.track,
          color: color,
        ),
      ),
    ]),
  );
}

/// A row of slim bars over time, coloured per value.
Widget xpStrip(BuildContext c, List<double> values, double max,
    Color Function(double) colorOf,
    {String left = '', String right = ''}) {
  final p = P.of(c);
  return Surface(
    child: Column(children: [
      SizedBox(
        height: 90,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final v in values)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: .5),
                height: 6 + 84 * (v / max).clamp(0.0, 1.0),
                decoration: BoxDecoration(
                    color: colorOf(v), borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: S.x2),
      Row(children: [
        Text(left, style: F.cap.copyWith(color: p.ink2)),
        const Spacer(),
        Text(right, style: F.cap.copyWith(color: p.ink2)),
      ]),
    ]),
  );
}

Widget xpSection(String title, List<Widget> children) =>
    Section(title, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));

// ── today, read once ─────────────────────────────────────────────────────────

class _Today {
  final double? recovery, strain, steps, kcal, rhr, rmssd, hrvBase, needMin;
  final double? targetLo, targetHi;
  const _Today(this.recovery, this.strain, this.steps, this.kcal, this.rhr,
      this.rmssd, this.hrvBase, this.needMin, this.targetLo, this.targetHi);

  static Future<_Today> load(LocalRepository repo) async {
    final t = await repo.getToday();
    final d = (t['daily'] as Map?) ?? const {};
    final hrv = (t['hrv'] as Map?) ?? const {};
    final target = ((t['coach'] as Map?)?['strain_target'] as Map?) ?? const {};
    return _Today(
      mv(d['recovery']),
      mv(d['strain']),
      mv(d['steps']),
      mv(d['calories']),
      mv(d['resting_hr']),
      mv(hrv['rmssd']),
      mv(hrv['baseline']),
      mv((t['sleep'] as Map?)?['need_min']),
      mv(target['low']),
      mv(target['high']),
    );
  }
}

String _n(double? v, [int places = 0]) =>
    v == null ? '—' : v.toStringAsFixed(places);

// ═══ 1 · Schlafplaner ════════════════════════════════════════════════════════

/// Wake time in, bedtime out. Lives on the Sleep tab and in the hub.
class SleepPlannerCard extends StatefulWidget {
  const SleepPlannerCard({super.key});

  @override
  State<SleepPlannerCard> createState() => _SleepPlannerCardState();
}

class _SleepPlannerCardState extends State<SleepPlannerCard> {
  double? _need, _eff;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = xpRepo(context);
    if (repo == null) return;
    final t = await _Today.load(repo);
    final eff = await xpSeries(repo, 'efficiency', days: 14);
    if (!mounted) return;
    setState(() {
      _need = t.needMin;
      final e = avgOf(eff.map((x) => x.$2));
      // Stored as a percentage on most days, as a fraction on a few.
      _eff = e == null ? null : (e > 1 ? e / 100 : e).clamp(.7, 1.0);
    });
  }

  TimeOfDay get _wake {
    final w = xpGet('sleepplan');
    return TimeOfDay(
        hour: (w['h'] as num?)?.toInt() ?? 7,
        minute: (w['m'] as num?)?.toInt() ?? 0);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final need = _need ?? 480;
    final eff = _eff ?? .9;
    const latency = 15;
    final inBed = need / eff + latency;
    final wake = _wake;
    final now = DateTime.now();
    var wakeAt = DateTime(now.year, now.month, now.day, wake.hour, wake.minute);
    if (!wakeAt.isAfter(now)) wakeAt = wakeAt.add(const Duration(days: 1));
    final bed = wakeAt.subtract(Duration(minutes: inBed.round()));
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.bedDouble, color: p.on(C.indigo), size: 20),
          const SizedBox(width: S.x2),
          Expanded(
              child: Text(tr(c, 'Schlafplaner', 'Sleep planner'),
                  style: F.head.copyWith(color: p.ink))),
          Pill(tr(c, 'Experimentell', 'Experimental'), C.orange),
        ]),
        const SizedBox(height: S.x3),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(c, 'Ins Bett um', 'Go to bed at'),
                  style: F.cap.copyWith(color: p.ink2)),
              Text(clock(bed), style: F.n34.copyWith(color: p.on(C.indigo))),
            ]),
          ),
          Pressable(
            onTap: () async {
              final t = await showTimePicker(context: c, initialTime: wake);
              if (t == null) return;
              xpSet('sleepplan', {'h': t.hour, 'm': t.minute});
              setState(() {});
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tr(c, 'Wecker', 'Wake up'), style: F.cap.copyWith(color: p.ink2)),
              Text(
                  '${two(wake.hour)}:${two(wake.minute)}',
                  style: F.n24.copyWith(color: p.on(C.blue))),
            ]),
          ),
        ]),
        const SizedBox(height: S.x2),
        Text(
          tr(
              c,
              'Schlafbedarf ${hmText(need)}${_need == null ? ' (Standard)' : ''}, '
                  'Effizienz ${(eff * 100).round()} %, ~$latency min zum Einschlafen. '
                  'Tippe auf die Weckzeit, um sie zu ändern.',
              'Sleep need ${hmText(need)}${_need == null ? ' (default)' : ''}, '
                  'efficiency ${(eff * 100).round()} %, ~$latency min to fall asleep. '
                  'Tap the wake time to change it.'),
          style: F.cap.copyWith(color: p.ink2),
        ),
      ]),
    );
  }
}

Future<List<Widget>> loadSleepPlanner(
        BuildContext c, LocalRepository repo, VoidCallback reload) async =>
    [const SizedBox(height: S.x3), const SleepPlannerCard()];

// ═══ 2 · Tagesrückblick ══════════════════════════════════════════════════════

Future<List<Widget>> loadDayReview(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final t = await _Today.load(repo);
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  final sessions = await repo.getSessions(
      from: midnight.millisecondsSinceEpoch ~/ 1000);
  final journal = await repo.getJournal(range: '1d');
  final todayTags = [
    for (final j in journal)
      if (j['date'] == todayLabel()) ...(j['tags'] as List? ?? const []),
  ];
  final tst = await xpSeries(repo, 'sleep', days: 2);
  if (!c.mounted) return const [];
  final lines = <String>[
    if (t.strain != null)
      tr(c, 'Strain ${_n(t.strain, 1)}', 'Strain ${_n(t.strain, 1)}') +
          (t.targetHi != null
              ? (t.strain! > t.targetHi!
                  ? tr(c, ', über deinem Ziel', ', above your target')
                  : t.strain! >= (t.targetLo ?? 0)
                      ? tr(c, ', im Zielbereich', ', inside your target')
                      : tr(c, ', unter deinem Ziel', ', below your target'))
              : ''),
    if (sessions.isNotEmpty)
      tr(c, '${sessions.length} Training(s): ', '${sessions.length} workout(s): ') +
          sessions.map((s) => '${s['name'] ?? s['type'] ?? ''}').join(', '),
    if (todayTags.isNotEmpty)
      tr(c, 'Journal: ${todayTags.join(', ')}', 'Journal: ${todayTags.join(', ')}'),
  ];
  return [
    xpStat(c, tr(c, 'Recovery heute', 'Recovery today'),
        t.recovery == null ? '—' : '${t.recovery!.round()} %',
        color: C.green),
    Row(children: [
      Expanded(child: xpStat(c, 'Strain', _n(t.strain, 1), color: C.blue)),
      const SizedBox(width: S.x3),
      Expanded(child: xpStat(c, tr(c, 'Schritte', 'Steps'), _n(t.steps), color: C.teal)),
    ]),
    Row(children: [
      Expanded(
          child: xpStat(c, tr(c, 'Aktive Energie', 'Active energy'),
              t.kcal == null ? '—' : '${t.kcal!.round()} kcal',
              color: C.orange)),
      const SizedBox(width: S.x3),
      Expanded(
          child: xpStat(c, tr(c, 'Schlaf', 'Sleep'),
              tst.isEmpty ? '—' : hmText(tst.last.$2),
              color: C.indigo)),
    ]),
    xpSection(tr(c, 'Dein Tag', 'Your day'), [
      if (lines.isEmpty) xpNote(c, tr(c, 'Noch nichts aufgezeichnet.', 'Nothing recorded yet.')),
      for (final l in lines) xpNote(c, '• $l'),
    ]),
  ];
}

// ═══ 3 · Trainingsempfehlung ═════════════════════════════════════════════════

Future<List<Widget>> loadTrainingAdvice(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final t = await _Today.load(repo);
  if (!c.mounted) return const [];
  final r = t.recovery;
  final (head, body, color) = r == null
      ? (
          tr(c, 'Noch keine Recovery', 'No recovery yet'),
          tr(c, 'Ohne Recovery-Wert heute nach Gefühl trainieren.',
              'Without a recovery score, train by feel today.'),
          C.n500
        )
      : r >= 67
          ? (
              tr(c, 'Grünes Licht', 'Green light'),
              tr(c, 'Gut erholt. Heute passt eine harte Einheit: Intervalle, ein schweres Krafttraining oder 45–75 min mit Abschnitten in Zone 4–5.',
                  'Well recovered. A hard session fits today: intervals, heavy lifting, or 45–75 min with stretches in zones 4–5.'),
              C.green
            )
          : r >= 34
              ? (
                  tr(c, 'Moderat', 'Moderate'),
                  tr(c, 'Teilweise erholt. Am besten 30–60 min locker in Zone 2 oder Technik- und Krafttraining mit mittlerem Gewicht.',
                      'Partly recovered. Best is 30–60 min easy in zone 2, or technique and moderate lifting.'),
                  C.yellow
                )
              : (
                  tr(c, 'Erholung', 'Recover'),
                  tr(c, 'Wenig erholt. Spaziergang, Mobility oder Dehnen, höchstens 30 min in Zone 1. Früh schlafen hilft am meisten.',
                      'Low recovery. Walk, mobility or stretching, at most 30 min in zone 1. An early night helps most.'),
                  C.red
                );
  final left = t.targetHi != null && t.strain != null
      ? math.max(0, t.targetHi! - t.strain!)
      : null;
  return [
    xpStat(c, tr(c, 'Empfehlung für heute', 'Today’s advice'), head,
        sub: body, color: color),
    if (t.targetLo != null && t.targetHi != null)
      xpStat(c, tr(c, 'Strain-Ziel', 'Strain target'),
          '${_n(t.targetLo, 1)}–${_n(t.targetHi, 1)}',
          sub: left == null
              ? ''
              : left == 0
                  ? tr(c, 'Ziel erreicht. Alles weitere geht auf die Erholung.',
                      'Target reached. Anything more costs recovery.')
                  : tr(c, 'Noch ${left.toStringAsFixed(1)} Strain bis zum oberen Ende.',
                      '${left.toStringAsFixed(1)} strain left to the top of the band.'),
          color: C.blue),
    xpNote(
        c,
        tr(c, 'Recovery ${r == null ? '—' : '${r.round()} %'}. Die Empfehlung ist eine einfache Regel, kein Trainingsplan.',
            'Recovery ${r == null ? '—' : '${r.round()} %'}. The advice is a simple rule, not a training plan.')),
  ];
}

// ═══ 4 · Schlaf-Stress ═══════════════════════════════════════════════════════

/// The newest stored night's sleep window, from its day result.
Future<(DateTime, DateTime)?> lastNight(LocalRepository repo) async {
  final days = await repo.availableDays();
  for (final d in days.take(3)) {
    final row = await LocalDb.dayResult(d);
    final raw = row?['window_json'];
    final w = raw is String ? jsonDecode(raw) : null;
    if (w is! Map) continue;
    final on = w['onset_ms'], off = w['offset_ms'];
    if (on is num && off is num && off > on) {
      return (
        DateTime.fromMillisecondsSinceEpoch(on.toInt()),
        DateTime.fromMillisecondsSinceEpoch(off.toInt())
      );
    }
  }
  return null;
}

double _pct(List<double> xs, double q) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * q).round()];
}

Future<List<Widget>> loadSleepStress(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final night = await lastNight(repo);
  final wins = night == null
      ? const <BeatWindow>[]
      : await beatWindows(night.$1, night.$2);
  if (!c.mounted) return const [];
  if (wins.length < 6) {
    return [
      xpNote(c, tr(c, 'Für die letzte Nacht liegen zu wenige Herzschläge vor.',
          'Too few stored beats for last night.'))
    ];
  }
  // The night's own calmest stretch is the reference.
  final refR = _pct([for (final w in wins) w.rmssd], .75);
  final refH = _pct([for (final w in wins) w.hr], .25);
  final s = [
    for (final w in wins)
      stressScore(hr: w.hr, rmssd: w.rmssd, refHr: refH, refRmssd: refR)
  ];
  final high = s.where((x) => x >= 2).length / s.length;
  final avg = avgOf(s)!;
  return [
    xpStat(c, tr(c, 'Schlaf-Stress', 'Sleep stress'), avg.toStringAsFixed(1),
        sub: tr(c, '${stressWord(c, avg)} im Schnitt (0–3). ${(high * 100).round()} % der Nacht mit hohem Stress.',
            '${stressWord(c, avg)} on average (0–3). ${(high * 100).round()} % of the night high.'),
        color: stressColor(avg)),
    const SizedBox(height: S.x3),
    xpStrip(c, s, 3, stressColor,
        left: clock(night!.$1), right: clock(night.$2)),
    xpNote(
        c,
        tr(c, 'Jeder Balken sind 10 Minuten. Verglichen wird mit der ruhigsten Phase derselben Nacht: niedrigere HRV und höherer Puls zählen als Stress.',
            'Each bar is 10 minutes, compared with the calmest stretch of the same night: lower HRV and higher pulse count as stress.')),
  ];
}

// ═══ 5 · Stress jetzt ════════════════════════════════════════════════════════

Future<List<Widget>> loadStressNow(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final t = await _Today.load(repo);
  final now = DateTime.now();
  final wins = await beatWindows(
      DateTime(now.year, now.month, now.day), now,
      window: const Duration(minutes: 15));
  if (!c.mounted) return const [];
  final refR = t.hrvBase ?? t.rmssd;
  final refH = t.rhr;
  if (refR == null || refH == null) {
    return [
      xpNote(c, tr(c, 'Es fehlt noch ein Ruhepuls und eine HRV aus der Nacht als Vergleich.',
          'Needs last night’s resting HR and HRV as a reference.'))
    ];
  }
  if (wins.isEmpty) {
    return [
      xpNote(c, tr(c, 'Heute sind noch keine Herzschläge synchronisiert.',
          'No beats synced yet today.'))
    ];
  }
  final s = [
    for (final w in wins)
      stressScore(hr: w.hr, rmssd: w.rmssd, refHr: refH, refRmssd: refR)
  ];
  final last = wins.last;
  final ago = now.difference(last.start).inMinutes;
  return [
    xpStat(c, tr(c, 'Stress zuletzt', 'Latest stress'), s.last.toStringAsFixed(1),
        sub: tr(c, '${stressWord(c, s.last)}, Stand ${clock(last.start)} (vor $ago min). Puls ${last.hr.round()}, HRV ${last.rmssd.round()} ms.',
            '${stressWord(c, s.last)}, as of ${clock(last.start)} ($ago min ago). HR ${last.hr.round()}, HRV ${last.rmssd.round()} ms.'),
        color: stressColor(s.last)),
    const SizedBox(height: S.x3),
    xpStrip(c, s, 3, stressColor,
        left: clock(wins.first.start), right: clock(last.start)),
    xpNote(
        c,
        tr(c, 'Je 15 Minuten, verglichen mit deinem Ruhepuls und deiner Nacht-HRV. Bewegung wird nicht herausgerechnet, ein Spaziergang zählt also mit. Neue Werte kommen mit jeder Synchronisierung.',
            'Per 15 minutes, against your resting HR and night HRV. Movement is not removed, so a walk counts too. New values arrive with each sync.')),
  ];
}

// ═══ 6 · Muskuläre Belastung ═════════════════════════════════════════════════

Future<List<Widget>> loadMuscleLoad(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final since = DateTime.now().subtract(const Duration(days: 7));
  final db = await LocalDb.instance;
  final rows = await db.rawQuery(
      'SELECT exercise_key, reps, load_kg, at_ts FROM strength_set WHERE at_ts >= ?',
      [since.millisecondsSinceEpoch ~/ 1000]);
  final byMuscle = <String, double>{};
  var today = 0.0, week = 0.0, unloaded = 0;
  final midnight = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  for (final r in rows) {
    final reps = (r['reps'] as num?)?.toDouble() ?? 0;
    final kg = (r['load_kg'] as num?)?.toDouble();
    if (kg == null) unloaded++;
    // A bodyweight set still loads the muscle; count it at a nominal 20 kg.
    // ponytail: no body-weight share per exercise; the upgrade is a factor per lift.
    final vol = reps * (kg ?? 20);
    week += vol;
    final at = DateTime.fromMillisecondsSinceEpoch(((r['at_ts'] as num?)?.toInt() ?? 0) * 1000);
    if (!at.isBefore(midnight)) today += vol;
    final ex = exerciseByKey('${r['exercise_key']}');
    for (final m in ex?.primaryMuscles ?? const ['Andere']) {
      byMuscle[m] = (byMuscle[m] ?? 0) + vol;
    }
    for (final m in ex?.secondaryMuscles ?? const <String>[]) {
      byMuscle[m] = (byMuscle[m] ?? 0) + vol / 2;
    }
  }
  if (!c.mounted) return const [];
  if (rows.isEmpty) {
    return [
      xpNote(c, tr(c, 'In den letzten 7 Tagen wurden keine Sätze geloggt. Logge Sätze im Krafttraining, dann erscheint hier die Belastung pro Muskel.',
          'No sets logged in the last 7 days. Log sets in a strength workout to see load per muscle.'))
    ];
  }
  // 0–21 like strain, saturating: 8 t of volume is about a 13.
  // ponytail: one curve for everyone; the upgrade is scaling by the user's own history.
  double score(double v) => 21 * (1 - math.exp(-v / 8000));
  final sorted = byMuscle.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted.first.value;
  return [
    Row(children: [
      Expanded(
          child: xpStat(c, tr(c, 'Muskel-Strain heute', 'Muscular strain today'),
              score(today).toStringAsFixed(1),
              sub: '${today.round()} kg', color: C.purple)),
      const SizedBox(width: S.x3),
      Expanded(
          child: xpStat(c, tr(c, 'Volumen 7 Tage', 'Volume 7 days'),
              '${(week / 1000).toStringAsFixed(1)} t',
              sub: tr(c, '${rows.length} Sätze', '${rows.length} sets'),
              color: C.purple)),
    ]),
    xpSection(tr(c, 'Pro Muskelgruppe (7 Tage)', 'Per muscle group (7 days)'), [
      for (final e in sorted)
        xpBar(c, e.key, e.value / top, '${e.value.round()} kg', color: C.purple),
    ]),
    if (unloaded > 0)
      xpNote(c, tr(c, '$unloaded Sätze ohne Gewicht sind mit 20 kg angesetzt.',
          '$unloaded sets without a load are counted at 20 kg.')),
    xpNote(c, tr(c, 'Volumen = Gewicht × Wiederholungen. Nebenmuskeln zählen zur Hälfte.',
        'Volume = load × reps. Secondary muscles count half.')),
  ];
}

// ═══ 7 · Ziele ═══════════════════════════════════════════════════════════════

Future<List<Widget>> loadGoals(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final g = xpGet('goals');
  final profile = await repo.getProfile();
  final stepGoal = (profile['step_goal'] as num?)?.toDouble() ?? 8000;
  final sleepH = (g['sleep_h'] as num?)?.toDouble() ?? 8;
  final workouts = (g['workouts'] as num?)?.toInt() ?? 3;
  final strainAvg = (g['strain'] as num?)?.toDouble() ?? 10;
  final steps = await xpSeries(repo, 'steps', days: 7);
  final sleep = await xpSeries(repo, 'sleep', days: 7);
  final strain = await xpSeries(repo, 'strain', days: 7);
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final sessions =
      await repo.getSessions(from: monday.millisecondsSinceEpoch ~/ 1000);
  if (!c.mounted) return const [];
  final stepsAvg = avgOf(steps.map((e) => e.$2));
  final sleepAvg = avgOf(sleep.map((e) => e.$2));
  final strainNow = avgOf(strain.map((e) => e.$2));

  Future<void> edit(String key, String title, double value, double step,
      double min, double max) async {
    var v = value;
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(title),
          content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                onPressed: () => set(() => v = math.max(min, v - step)),
                icon: const Icon(LucideIcons.minus)),
            Text(v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1),
                style: F.n24),
            IconButton(
                onPressed: () => set(() => v = math.min(max, v + step)),
                icon: const Icon(LucideIcons.plus)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr(c, 'Abbrechen', 'Cancel'))),
            TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tr(c, 'Speichern', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (key == 'steps') {
      await repo.setStepGoal(v.round());
    } else {
      xpSet('goals', {...xpGet('goals'), key: v});
    }
    reload();
  }

  Widget goal(String key, String label, double? actual, double target,
      String Function(double) fmt, double step, double min, double max,
      {Color color = C.green}) {
    return Pressable(
      onTap: () => edit(key, label, target, step, min, max),
      child: xpBar(c, label, actual == null ? 0 : actual / target,
          '${actual == null ? '—' : fmt(actual)} / ${fmt(target)}',
          color: (actual ?? 0) >= target ? C.green : color),
    );
  }

  return [
    xpSection(tr(c, 'Diese Woche', 'This week'), [
      goal('steps', tr(c, 'Schritte pro Tag (Ø 7 Tage)', 'Steps per day (7-day avg)'),
          stepsAvg, stepGoal, (v) => '${v.round()}', 500, 1000, 40000, color: C.teal),
      goal('sleep_h', tr(c, 'Schlaf pro Nacht (Ø 7 Tage)', 'Sleep per night (7-day avg)'),
          sleepAvg == null ? null : sleepAvg / 60, sleepH,
          (v) => '${v.toStringAsFixed(1)} h', .5, 5, 11, color: C.indigo),
      goal('workouts', tr(c, 'Trainings seit Montag', 'Workouts since Monday'),
          sessions.length.toDouble(), workouts.toDouble(),
          (v) => '${v.round()}', 1, 1, 14, color: C.purple),
      goal('strain', tr(c, 'Strain pro Tag (Ø 7 Tage)', 'Strain per day (7-day avg)'),
          strainNow, strainAvg, (v) => v.toStringAsFixed(1), .5, 4, 21, color: C.blue),
    ]),
    xpNote(c, tr(c, 'Tippe auf ein Ziel, um es zu ändern. Das Schrittziel ist dasselbe wie auf Home; dein Gewichtsziel findest du unter Ernährung.',
        'Tap a goal to change it. The step goal is the same one Home uses; your weight goal lives in Nutrition.')),
  ];
}

// ═══ 8 · Streak ══════════════════════════════════════════════════════════════

int _streak(Set<String> days) {
  var d = DateTime.now();
  // Today still counts as open: a streak that reached yesterday is alive.
  if (!days.contains(dayLabelOf(d))) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (days.contains(dayLabelOf(d))) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

Future<List<Widget>> loadStreaks(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final journal = await repo.getJournal(range: '400d');
  final profile = await repo.getProfile();
  final stepGoal = (profile['step_goal'] as num?)?.toDouble() ?? 8000;
  final sleepH = (xpGet('goals')['sleep_h'] as num?)?.toDouble() ?? 8;
  final steps = await xpSeries(repo, 'steps', days: 400);
  final sleep = await xpSeries(repo, 'sleep', days: 400);
  final rec = await xpSeries(repo, 'recovery', days: 400);
  if (!c.mounted) return const [];
  Set<String> where(List<(DateTime, double)> s, bool Function(double) ok) =>
      {for (final e in s) if (ok(e.$2)) dayLabelOf(e.$1)};
  final rows = [
    (tr(c, 'Journal ausgefüllt', 'Journal filled in'), {for (final j in journal) '${j['date']}'}, LucideIcons.notebookPen, C.teal),
    (tr(c, 'Schrittziel erreicht', 'Step goal reached'), where(steps, (v) => v >= stepGoal), LucideIcons.footprints, C.green),
    (tr(c, 'Schlafziel erreicht', 'Sleep goal reached'), where(sleep, (v) => v >= sleepH * 60), LucideIcons.moon, C.indigo),
    (tr(c, 'Recovery im grünen Bereich', 'Recovery in the green'), where(rec, (v) => v >= 67), LucideIcons.heartPulse, C.green),
  ];
  final p = P.of(c);
  return [
    for (final (label, days, icon, color) in rows)
      Padding(
        padding: const EdgeInsets.only(top: S.x3),
        child: Surface(
          child: Row(children: [
            Icon(icon, color: p.on(color)),
            const SizedBox(width: S.x3),
            Expanded(child: Text(label, style: F.body.copyWith(color: p.ink))),
            Text('${_streak(days)}', style: F.n24.copyWith(color: p.on(color))),
            const SizedBox(width: S.x1),
            Text(tr(c, 'Tage', 'days'), style: F.cap.copyWith(color: p.ink2)),
          ]),
        ),
      ),
    xpNote(c, tr(c, 'Tage am Stück bis heute. Ist heute noch offen, zählt die Serie bis gestern weiter.',
        'Days in a row up to today. While today is still open, the run up to yesterday stays alive.')),
  ];
}

// ═══ 9 · Wochenplan ══════════════════════════════════════════════════════════

const _planBands = {
  'rest': (0.0, 7.0),
  'easy': (7.0, 11.0),
  'mid': (11.0, 14.0),
  'hard': (14.0, 18.0),
};
const _planOrder = ['rest', 'easy', 'mid', 'hard'];

String _planWord(BuildContext c, String k) => switch (k) {
      'rest' => tr(c, 'Ruhe', 'Rest'),
      'easy' => tr(c, 'Locker', 'Easy'),
      'mid' => tr(c, 'Mittel', 'Moderate'),
      _ => tr(c, 'Hart', 'Hard'),
    };

Future<List<Widget>> loadWeekPlan(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final plan = xpGet('weekplan');
  final strain = await xpSeries(repo, 'strain', days: 8);
  final t = await _Today.load(repo);
  if (!c.mounted) return const [];
  final byDay = {for (final e in strain) dayLabelOf(e.$1): e.$2};
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final names = Localizations.localeOf(c).languageCode == 'de'
      ? ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
      : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final p = P.of(c);
  final todayPlan = '${plan['${now.weekday}'] ?? 'easy'}';
  final warn = todayPlan == 'hard' && (t.recovery ?? 100) < 34;
  return [
    if (warn)
      xpStat(c, tr(c, 'Hinweis für heute', 'Heads-up for today'),
          tr(c, 'Lieber locker', 'Go easy instead'),
          sub: tr(c, 'Geplant ist eine harte Einheit, aber deine Recovery liegt bei ${t.recovery!.round()} %. Tausche heute mit einem lockeren Tag.',
              'A hard session is planned, but recovery is ${t.recovery!.round()} %. Swap today with an easy day.'),
          color: C.red),
    const SizedBox(height: S.x3),
    for (var i = 0; i < 7; i++)
      Builder(builder: (_) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        final k = '${plan['${i + 1}'] ?? 'easy'}';
        final band = _planBands[k]!;
        final actual = byDay[dayLabelOf(day)];
        final isToday = i == now.weekday - 1;
        final hit = actual != null && actual >= band.$1 && actual <= band.$2;
        return Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Surface(
            onTap: () {
              final next = _planOrder[(_planOrder.indexOf(k) + 1) % _planOrder.length];
              xpSet('weekplan', {...xpGet('weekplan'), '${i + 1}': next});
              reload();
            },
            child: Row(children: [
              SizedBox(
                  width: 40,
                  child: Text(names[i],
                      style: F.head.copyWith(color: isToday ? p.on(C.blue) : p.ink))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_planWord(c, k), style: F.body.copyWith(color: p.ink)),
                  Text('Strain ${band.$1.round()}–${band.$2.round()}',
                      style: F.cap.copyWith(color: p.ink2)),
                ]),
              ),
              if (actual != null)
                Pill(actual.toStringAsFixed(1), hit ? C.green : C.orange),
            ]),
          ),
        );
      }),
    xpNote(c, tr(c, 'Tippe auf einen Tag, um zwischen Ruhe, Locker, Mittel und Hart zu wechseln. Grün = der Strain lag im geplanten Bereich.',
        'Tap a day to cycle rest, easy, moderate and hard. Green = strain landed in the planned band.')),
  ];
}

// ═══ 10 · Biologisches Alter ═════════════════════════════════════════════════

/// Years added (+) or taken off (−) per input, against simple age norms.
// ponytail: hand-set norms from population averages, not a fitted model;
// the upgrade is a published fitness-age formula once sex and height are asked.
({double age, Map<String, double> parts})? bioAge({
  required double age,
  required bool female,
  double? vo2,
  double? rhr,
  double? hrv,
  double? sleepH,
  double? steps,
}) {
  final parts = <String, double>{};
  if (vo2 != null) {
    final norm = (female ? 43 : 50) - .35 * (age - 20);
    parts['vo2'] = (-(vo2 - norm) * .4).clamp(-6.0, 6.0);
  }
  if (rhr != null) parts['rhr'] = ((rhr - 60) * .2).clamp(-4.0, 4.0);
  if (hrv != null) {
    final norm = math.max(20, 65 - .7 * (age - 20));
    parts['hrv'] = ((norm - hrv) * .1).clamp(-3.0, 3.0);
  }
  if (sleepH != null) parts['sleep'] = ((sleepH - 7.5).abs() * 1.0 - .5).clamp(-.5, 2.0);
  if (steps != null) parts['steps'] = ((8000 - steps) / 2000 * .5).clamp(-2.0, 2.0);
  if (parts.isEmpty) return null;
  return (age: age + parts.values.reduce((a, b) => a + b), parts: parts);
}

Future<List<Widget>> loadBioAge(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final profile = await repo.getProfile();
  final age = (profile['age'] as num?)?.toDouble();
  final female = '${profile['sex'] ?? ''}'.toLowerCase().startsWith('f');
  final sessions = await repo.getSessions(
      from: DateTime.now().subtract(const Duration(days: 365)).millisecondsSinceEpoch ~/ 1000);
  final vo2s = [
    for (final s in sessions)
      if (s['vo2max_estimate'] is num) (s['vo2max_estimate'] as num).toDouble()
  ];
  final rhr = await xpSeries(repo, 'resting_hr', days: 180);
  final hrv = await xpSeries(repo, 'hrv', days: 180);
  final sleep = await xpSeries(repo, 'sleep', days: 180);
  final steps = await xpSeries(repo, 'steps', days: 180);
  if (!c.mounted) return const [];
  if (age == null) {
    return [xpNote(c, tr(c, 'Trage dein Alter im Profil ein, dann lässt sich das biologische Alter schätzen.',
        'Add your age in your profile to estimate a biological age.'))];
  }
  final now = DateTime.now();
  double? win(List<(DateTime, double)> s, int fromDays, int toDays) => avgOf([
        for (final e in s)
          if (now.difference(e.$1).inDays >= fromDays && now.difference(e.$1).inDays < toDays) e.$2
      ]);
  final vo2 = vo2s.isEmpty ? null : medianOf(vo2s.take(5).toList());
  final cur = bioAge(
      age: age, female: female, vo2: vo2,
      rhr: win(rhr, 0, 30), hrv: win(hrv, 0, 30),
      sleepH: win(sleep, 0, 30) == null ? null : win(sleep, 0, 30)! / 60,
      steps: win(steps, 0, 30));
  final then = bioAge(
      age: age, female: female, vo2: vo2,
      rhr: win(rhr, 90, 180), hrv: win(hrv, 90, 180),
      sleepH: win(sleep, 90, 180) == null ? null : win(sleep, 90, 180)! / 60,
      steps: win(steps, 90, 180));
  if (cur == null) {
    return [xpNote(c, tr(c, 'Noch zu wenige Daten aus den letzten 30 Tagen.', 'Not enough data from the last 30 days yet.'))];
  }
  final diff = cur.age - age;
  // Pace: how many "years" the score moved over the ~4.5 months between the
  // two windows, per calendar year. 1.0 = ageing in step with the calendar.
  final pace = then == null ? null : 1 + (cur.age - then.age) / (135 / 365);
  final labels = {
    'vo2': 'VO₂max',
    'rhr': tr(c, 'Ruhepuls', 'Resting HR'),
    'hrv': 'HRV',
    'sleep': tr(c, 'Schlafdauer', 'Sleep duration'),
    'steps': tr(c, 'Schritte', 'Steps'),
  };
  return [
    xpStat(c, tr(c, 'Biologisches Alter', 'Biological age'), cur.age.toStringAsFixed(1),
        sub: tr(c, '${diff <= 0 ? '${(-diff).toStringAsFixed(1)} Jahre jünger' : '${diff.toStringAsFixed(1)} Jahre älter'} als dein Alter (${age.round()}).',
            '${diff <= 0 ? '${(-diff).toStringAsFixed(1)} years younger' : '${diff.toStringAsFixed(1)} years older'} than your age (${age.round()}).'),
        color: diff <= 0 ? C.green : C.orange),
    if (pace != null)
      xpStat(c, tr(c, 'Tempo des Alterns', 'Pace of aging'), '${pace.clamp(-1.0, 3.0).toStringAsFixed(2)}×',
          sub: tr(c, 'Verglichen mit vor 3–6 Monaten. Unter 1,0 heißt: langsamer als der Kalender.',
              'Compared with 3–6 months ago. Below 1.0 means slower than the calendar.'),
          color: pace <= 1 ? C.green : C.orange),
    xpSection(tr(c, 'Was es ausmacht', 'What moves it'), [
      for (final e in cur.parts.entries)
        xpNote(c, '${labels[e.key]}: ${e.value >= 0 ? '+' : '−'}${e.value.abs().toStringAsFixed(1)} ${tr(c, 'Jahre', 'years')}'),
    ]),
    xpNote(c, tr(c, 'Eine grobe Schätzung aus Durchschnittswerten deiner letzten 30 Tage gegen Normwerte für dein Alter. Kein medizinischer Wert.',
        'A rough estimate from your last 30 days against norms for your age. Not a medical measure.')),
  ];
}

// ═══ 11 · Gesundheitsbericht ═════════════════════════════════════════════════

Future<List<Widget>> loadReport(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final keys = <(String, String, String, int)>[
    ('recovery', 'Recovery', '%', 0),
    ('resting_hr', tr(c, 'Ruhepuls', 'Resting HR'), 'bpm', 0),
    ('hrv', 'HRV (RMSSD)', 'ms', 0),
    ('resp_rate', tr(c, 'Atemfrequenz', 'Respiratory rate'), '/min', 1),
    ('skin_temp', tr(c, 'Hauttemperatur (Abweichung)', 'Skin temp (deviation)'), 'z', 2),
    ('sleep', tr(c, 'Schlafdauer', 'Sleep duration'), 'min', 0),
    ('efficiency', tr(c, 'Schlafeffizienz', 'Sleep efficiency'), '%', 0),
    ('strain', 'Strain', '', 1),
    ('steps', tr(c, 'Schritte', 'Steps'), '', 0),
  ];
  final rows = <(String, String, double, double, double, double, int)>[];
  for (final (k, label, unit, places) in keys) {
    final s = await xpSeries(repo, k, days: 90);
    if (s.isEmpty) continue;
    final v = [for (final e in s) e.$2];
    final last30 = [for (final e in s) if (DateTime.now().difference(e.$1).inDays < 30) e.$2];
    rows.add((label, unit, avgOf(last30) ?? double.nan, avgOf(v)!,
        v.reduce(math.min), v.reduce(math.max), places));
  }
  if (!c.mounted) return const [];
  String f(double v, int p) => v.isNaN ? '—' : v.toStringAsFixed(p);
  final table = StringBuffer();
  final lines = <Widget>[];
  for (final (label, unit, a30, a90, mn, mx, places) in rows) {
    table.writeln('<tr><td>$label</td><td>${f(a30, places)}</td><td>${f(a90, places)}</td>'
        '<td>${f(mn, places)}–${f(mx, places)}</td><td>$unit</td></tr>');
    lines.add(xpNote(c, '$label: Ø30 ${f(a30, places)} · Ø90 ${f(a90, places)} $unit'));
  }
  final html = '''<!doctype html><html><head><meta charset="utf-8">
<title>Edge+ ${tr(c, 'Gesundheitsbericht', 'Health report')}</title>
<style>body{font-family:sans-serif;max-width:720px;margin:24px auto;padding:0 16px}
table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ddd;padding:6px;text-align:left}</style>
</head><body><h1>${tr(c, 'Gesundheitsbericht', 'Health report')}</h1>
<p>${tr(c, 'Erstellt am', 'Created on')} ${todayLabel()} · ${tr(c, 'letzte 90 Tage', 'last 90 days')}</p>
<table><tr><th>${tr(c, 'Wert', 'Metric')}</th><th>Ø 30</th><th>Ø 90</th><th>Min–Max</th><th></th></tr>
$table</table>
<p><small>${tr(c, 'Werte aus einem Fitness-Armband, berechnet auf dem Handy. Keine medizinische Messung.', 'Values from a fitness band, computed on the phone. Not a medical measurement.')}</small></p>
</body></html>''';
  return [
    xpStat(c, tr(c, 'Gesundheitsbericht', 'Health report'), '90 ${tr(c, 'Tage', 'days')}',
        sub: tr(c, 'Durchschnitt, Minimum und Maximum der wichtigsten Werte als Datei zum Teilen, z. B. mit deiner Ärztin oder deinem Arzt. Im Browser geöffnet lässt sie sich als PDF drucken.',
            'Average, minimum and maximum of the key metrics as a file to share, e.g. with your doctor. Open it in a browser to print it as a PDF.'),
        color: C.blue),
    const SizedBox(height: S.x3),
    BigButton(tr(c, 'Bericht teilen', 'Share report'),
        icon: LucideIcons.share2,
        color: C.blue,
        onTap: rows.isEmpty
            ? null
            : () => Share.shareXFiles([
                  XFile.fromData(Uint8List.fromList(utf8.encode(html)),
                      mimeType: 'text/html', name: 'edge-bericht-${todayLabel()}.html'),
                ])),
    xpSection(tr(c, 'Vorschau', 'Preview'), lines.isEmpty
        ? [xpNote(c, tr(c, 'Noch keine Daten.', 'No data yet.'))]
        : lines),
  ];
}

// ═══ 12 · Zyklus-Analysen ════════════════════════════════════════════════════

Future<List<Widget>> loadCycleAnalysis(
    BuildContext c, LocalRepository repo, VoidCallback reload) async {
  final cyc = await repo.getCycle();
  if (!c.mounted) return const [];
  if (cyc['enabled'] != true) {
    return [xpNote(c, tr(c, 'Zyklus-Tracking ist im Profil ausgeschaltet. Schalte es ein und trage den Beginn deiner Periode ein, dann erscheinen hier die Vergleiche.',
        'Cycle tracking is off in your profile. Turn it on and log period starts to see the comparisons.'))];
  }
  final overlay = [
    for (final o in (cyc['overlay'] as List?) ?? const [])
      if (o is Map && o['cycle_day'] is num) o
  ];
  final rec = {for (final e in await xpSeries(repo, 'recovery', days: 400)) dayLabelOf(e.$1): e.$2};
  final sleep = {for (final e in await xpSeries(repo, 'sleep', days: 400)) dayLabelOf(e.$1): e.$2};
  final strain = {for (final e in await xpSeries(repo, 'strain', days: 400)) dayLabelOf(e.$1): e.$2};
  if (!c.mounted) return const [];
  const bands = [(1, 5), (6, 13), (14, 20), (21, 99)];
  final out = <Widget>[];
  for (final (lo, hi) in bands) {
    final days = [
      for (final o in overlay)
        if ((o['cycle_day'] as num) >= lo && (o['cycle_day'] as num) <= hi) '${o['date']}'
    ];
    double? a(Map<String, double> m) => avgOf([for (final d in days) if (m[d] != null) m[d]!]);
    double? ov(String k) => avgOf([
          for (final o in overlay)
            if ((o['cycle_day'] as num) >= lo && (o['cycle_day'] as num) <= hi && o[k] is num)
              (o[k] as num).toDouble()
        ]);
    final r = a(rec), s = a(sleep), st = a(strain), rhr = ov('resting_hr'), hrv = ov('hrv_rmssd');
    out.add(Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(c, 'Zyklustag $lo–${hi == 99 ? 'Ende' : hi}', 'Cycle day $lo–${hi == 99 ? 'end' : hi}'),
              style: F.head.copyWith(color: P.of(c).ink)),
          const SizedBox(height: S.x1),
          Text(
              days.isEmpty
                  ? tr(c, 'Noch keine Tage.', 'No days yet.')
                  : 'Recovery ${_n(r)} % · ${tr(c, 'Schlaf', 'Sleep')} ${s == null ? '—' : hmText(s)} · Strain ${_n(st, 1)}\n'
                      '${tr(c, 'Ruhepuls', 'Resting HR')} ${_n(rhr)} · HRV ${_n(hrv)} ms · ${days.length} ${tr(c, 'Tage', 'days')}',
              style: F.body.copyWith(color: P.of(c).ink2)),
        ]),
      ),
    ));
  }
  return [
    ...out,
    xpNote(c, tr(c, 'Durchschnitt deiner Werte nach Zyklustag, aus deinen eigenen Einträgen. Ein Vergleich, keine Vorhersage und keine Korrektur deiner Recovery.',
        'Your averages by cycle day, from your own logs. A comparison, not a prediction or a correction of your recovery.')),
  ];
}

// ═══ 13 · Arbeitsmodus ═══════════════════════════════════════════════════════

/// Buzzes the band every 45 minutes while on: stand up, drink something.
///
/// The band's own buzz, never a phone notification.
// ponytail: an in-process timer, so it only runs while the app process lives
// (the Android sync service keeps it alive; iOS may pause it). The upgrade is
// arming the band's own alarm for each slot.
class WorkMode {
  static const every = Duration(minutes: 45);
  static const maxOn = Duration(hours: 10);
  static Timer? _timer;
  static final changed = ValueNotifier<int>(0);

  static bool get on => Prefs.getBool('xp.workmode.on', false);
  static DateTime get since => DateTime.fromMillisecondsSinceEpoch(
      Prefs.getInt('xp.workmode.since', 0));
  static DateTime get lastBuzz => DateTime.fromMillisecondsSinceEpoch(
      Prefs.getInt('xp.workmode.last', 0));
  static DateTime get next => lastBuzz.add(every);

  static void set(AppState app, bool value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    Prefs.setBool('xp.workmode.on', value);
    if (value) {
      Prefs.setInt('xp.workmode.since', now);
      Prefs.setInt('xp.workmode.last', now);
    }
    resume(app);
    changed.value++;
  }

  /// Start the ticker if work mode is on; safe to call any number of times.
  static void resume(AppState app) {
    _timer?.cancel();
    _timer = null;
    if (!on) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick(app));
  }

  static Future<void> _tick(AppState app) async {
    final now = DateTime.now();
    if (!on || now.difference(since) > maxOn) {
      Prefs.setBool('xp.workmode.on', false);
      _timer?.cancel();
      changed.value++;
      return;
    }
    if (now.isBefore(next)) return;
    if (!app.isConnected) return; // try again next minute
    Prefs.setInt('xp.workmode.last', now.millisecondsSinceEpoch);
    await app.buzzBand();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await app.buzzBand();
    changed.value++;
  }
}

class WorkModeTile extends StatelessWidget {
  const WorkModeTile({super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return ValueListenableBuilder<int>(
      valueListenable: WorkMode.changed,
      builder: (c, _, _) {
        final on = WorkMode.on;
        final mins = WorkMode.next.difference(DateTime.now()).inMinutes;
        return Surface(
          child: Row(children: [
            Icon(LucideIcons.briefcase, color: p.on(C.teal)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(c, 'Arbeitsmodus', 'Work mode'), style: F.head.copyWith(color: p.ink)),
                Text(
                    on
                        ? tr(c, 'Band vibriert in ${math.max(0, mins)} min: aufstehen und trinken.',
                            'Band buzzes in ${math.max(0, mins)} min: stand up and drink.')
                        : tr(c, 'Alle 45 min vibriert das Band: aufstehen und etwas trinken.',
                            'Every 45 min the band buzzes: stand up and drink.'),
                    style: F.cap.copyWith(color: p.ink2)),
              ]),
            ),
            Switch(
              value: on,
              onChanged: (v) => WorkMode.set(c.read<AppState>(), v),
            ),
          ]),
        );
      },
    );
  }
}

// ── the list ─────────────────────────────────────────────────────────────────

class XpFeature {
  final IconData icon;
  final Color color;
  final String Function(BuildContext) title, sub;
  final XpLoader load;
  const XpFeature(this.icon, this.color, this.title, this.sub, this.load);
}

final xpFeatures = <XpFeature>[
  XpFeature(LucideIcons.dumbbell, C.green, (c) => tr(c, 'Trainingsempfehlung', 'Training advice'),
      (c) => tr(c, 'Was heute zu deiner Recovery passt', 'What fits your recovery today'), loadTrainingAdvice),
  XpFeature(LucideIcons.sunset, C.orange, (c) => tr(c, 'Tagesrückblick', 'Day in review'),
      (c) => tr(c, 'Dein Tag auf einen Blick', 'Your day at a glance'), loadDayReview),
  XpFeature(LucideIcons.bedDouble, C.indigo, (c) => tr(c, 'Schlafplaner', 'Sleep planner'),
      (c) => tr(c, 'Wann du heute ins Bett solltest', 'When to go to bed tonight'), loadSleepPlanner),
  XpFeature(LucideIcons.moonStar, C.indigo, (c) => tr(c, 'Schlaf-Stress', 'Sleep stress'),
      (c) => tr(c, 'Wie unruhig die letzte Nacht war', 'How restless last night was'), loadSleepStress),
  XpFeature(LucideIcons.activity, C.red, (c) => tr(c, 'Stress jetzt', 'Stress now'),
      (c) => tr(c, 'Stress im Tagesverlauf, 0–3', 'Stress through the day, 0–3'), loadStressNow),
  XpFeature(LucideIcons.bicepsFlexed, C.purple, (c) => tr(c, 'Muskuläre Belastung', 'Muscular load'),
      (c) => tr(c, 'Belastung pro Muskel aus deinen Sätzen', 'Load per muscle from your sets'), loadMuscleLoad),
  XpFeature(LucideIcons.target, C.green, (c) => tr(c, 'Ziele', 'Goals'),
      (c) => tr(c, 'Schritte, Schlaf, Trainings, Strain', 'Steps, sleep, workouts, strain'), loadGoals),
  XpFeature(LucideIcons.calendarDays, C.blue, (c) => tr(c, 'Wochenplan', 'Weekly plan'),
      (c) => tr(c, 'Harte und lockere Tage planen', 'Plan hard and easy days'), loadWeekPlan),
  XpFeature(LucideIcons.flame, C.orange, (c) => tr(c, 'Serien', 'Streaks'),
      (c) => tr(c, 'Tage am Stück mit Ziel erreicht', 'Days in a row on target'), loadStreaks),
  XpFeature(LucideIcons.hourglass, C.teal, (c) => tr(c, 'Biologisches Alter', 'Biological age'),
      (c) => tr(c, 'Und wie schnell es sich ändert', 'And how fast it moves'), loadBioAge),
  XpFeature(LucideIcons.fileText, C.blue, (c) => tr(c, 'Gesundheitsbericht', 'Health report'),
      (c) => tr(c, '90 Tage als Datei zum Teilen', '90 days as a file to share'), loadReport),
  XpFeature(LucideIcons.flower2, C.pink, (c) => tr(c, 'Zyklus-Analysen', 'Cycle analysis'),
      (c) => tr(c, 'Recovery, Schlaf und Strain nach Zyklustag', 'Recovery, sleep and strain by cycle day'), loadCycleAnalysis),
];

/// The "Experimentell" block for the bottom of Home.
class ExperimentalSection extends StatefulWidget {
  const ExperimentalSection({super.key});

  @override
  State<ExperimentalSection> createState() => _ExperimentalSectionState();
}

class _ExperimentalSectionState extends State<ExperimentalSection> {
  @override
  void initState() {
    super.initState();
    // Pick work mode back up after a restart.
    try {
      WorkMode.resume(context.read<AppState>());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Section(
      tr(c, 'Experimentell', 'Experimental'),
      Column(children: [
        const WorkModeTile(),
        const SizedBox(height: S.x3),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
          child: Column(children: [
            for (final f in xpFeatures)
              Pressable(
                onTap: () => Navigator.of(c).push(MaterialPageRoute<void>(
                    builder: (_) => XpScreen(f.title(c), f.load))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x2),
                  child: Row(children: [
                    Icon(f.icon, color: p.on(f.color), size: 20),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.title(c), style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                        Text(f.sub(c), style: F.cap.copyWith(color: p.ink2)),
                      ]),
                    ),
                    Icon(LucideIcons.chevronRight, color: p.ink3, size: 18),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: S.x2),
        Text(
            tr(c, 'In Entwicklung. Die Werte sind Schätzungen und können sich noch ändern.',
                'In development. Values are estimates and may still change.'),
            style: F.cap.copyWith(color: p.ink2)),
      ]),
    );
  }
}
