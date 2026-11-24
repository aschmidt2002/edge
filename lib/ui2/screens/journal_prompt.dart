// Edge+: the morning and evening check-ins.
//
// The first time Home opens on a day from 04:00, a small sheet asks how you
// feel and how you slept. The first time it opens from 20:00, the full
// journal opens instead, without sleep quality (already asked that morning).
// Each one shows at most once a day. The morning sheet also carries today's
// weather and a short tip, when there is one.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart' show todayLabel;
import '../../data/journal_fields.dart' show JournalMetricValue;
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../weather/weather.dart';
import '../ui2.dart';
import 'journal_compose.dart';

const _kMorningKey = 'plus_checkin_morning_day';
const _kEveningKey = 'plus_checkin_evening_day';

/// Which check-in is due at [now], given the days each was last shown.
/// Null when none is: before 04:00, or already shown today.
enum CheckIn { morning, evening }

CheckIn? dueCheckIn(DateTime now,
    {required String lastMorning, required String lastEvening}) {
  if (now.hour < 4) return null;
  final today = todayLabel(now);
  if (now.hour >= 20) return lastEvening == today ? null : CheckIn.evening;
  return lastMorning == today ? null : CheckIn.morning;
}

bool _open = false;

/// Shows the check-in that is due, if any. Safe to call on every resume.
Future<void> maybeShowCheckIn(BuildContext c) async {
  if (_open || !Prefs.loaded) return;
  AppState app;
  try {
    app = c.read<AppState>();
  } catch (_) {
    return; // goldens
  }
  final repo = app.repo;
  if (repo == null) return;
  final now = DateTime.now();
  final today = todayLabel(now);
  final lastMorning = Prefs.getString(_kMorningKey, '');
  final due = dueCheckIn(now,
      lastMorning: lastMorning,
      lastEvening: Prefs.getString(_kEveningKey, ''));
  if (due == null) return;
  _open = true;
  try {
    if (due == CheckIn.evening) {
      Prefs.setString(_kEveningKey, today);
      // Not asked this morning: the evening journal asks sleep quality too.
      final sleepAsked = lastMorning == today;
      Prefs.setString(_kMorningKey, today);
      await Navigator.of(c).push(MaterialPageRoute<void>(
          builder: (_) => JournalCompose(evening: true, askSleep: !sleepAsked)));
    } else {
      Prefs.setString(_kMorningKey, today);
      await warmTodayWeather();
      if (!c.mounted) return;
      final r = await showModalBottomSheet<(int?, int?)>(
        context: c,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _MorningSheet(),
      );
      if (r == null || (r.$1 == null && r.$2 == null)) return;
      await repo.editJournalMetrics(today, (m) {
        if (r.$1 case final mood?) {
          m['mood_morning'] = JournalMetricValue(mood.toDouble());
        }
        if (r.$2 case final sleep?) {
          m['sleep_quality'] = JournalMetricValue(sleep.toDouble());
        }
      });
    }
  } catch (_) {
    // A failed write leaves the journal as it was; the user can still log it
    // there by hand.
  } finally {
    _open = false;
  }
}

class _MorningSheet extends StatefulWidget {
  const _MorningSheet();

  @override
  State<_MorningSheet> createState() => _MorningSheetState();
}

class _MorningSheetState extends State<_MorningSheet> {
  int? _mood, _sleep;
  final Future<TodayWeather?> _weather = fetchTodayWeather();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(c, 'Guten Morgen', 'Good morning'), style: F.t2.copyWith(color: p.ink)),
          const SizedBox(height: S.x4),
          FutureBuilder<TodayWeather?>(
            future: _weather,
            builder: (c, snap) {
              final w = snap.data;
              if (w == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: S.x3),
                child: WeatherBox(w),
              );
            },
          ),
          MoodPicker(
            value: _mood,
            onChanged: (v) => setState(() => _mood = v),
            title: tr(c, 'Wie fühlst du dich?', 'How do you feel?'),
          ),
          const SizedBox(height: S.x3),
          MoodPicker(
            value: _sleep,
            onChanged: (v) => setState(() => _sleep = v),
            title: tr(c, 'Wie hast du geschlafen?', 'How did you sleep?'),
          ),
          const SizedBox(height: S.x4),
          BigButton(
            tr(c, 'Speichern', 'Save'),
            icon: LucideIcons.check,
            color: C.domMind,
            onTap: _mood == null && _sleep == null
                ? null
                : () => Navigator.of(c).pop((_mood, _sleep)),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: Text(tr(c, 'Später', 'Later')),
          ),
        ]),
      ),
    );
  }
}

/// Edge+: today's weather in one card, with the tips under it.
class WeatherBox extends StatelessWidget {
  final TodayWeather w;
  const WeatherBox(this.w, {super.key});

  IconData get _icon => switch (w.code) {
        0 => LucideIcons.sun,
        1 || 2 => LucideIcons.cloudSun,
        3 => LucideIcons.cloud,
        45 || 48 => LucideIcons.cloudFog,
        71 || 73 || 75 || 77 || 85 || 86 => LucideIcons.cloudSnow,
        95 || 96 || 99 => LucideIcons.cloudLightning,
        >= 51 && <= 82 => LucideIcons.cloudRain,
        _ => LucideIcons.cloudSun,
      };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final de = Localizations.localeOf(c).languageCode == 'de';
    final hints = weatherHints(w, de: de);
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_icon, size: 28, color: p.on(C.blue)),
          const SizedBox(width: S.x3),
          Text('${w.temp.round()}°', style: F.n34.copyWith(color: p.ink)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.description(de: de),
                  style: F.body
                      .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              Text(
                  '${w.min.round()}° / ${w.max.round()}° · '
                  '${tr(c, 'Regen', 'Rain')} ${w.rainChance}% · UV ${w.uvMax.round()}',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
        ]),
        for (final h in hints) ...[
          const SizedBox(height: S.x2),
          Text(h, style: F.cap.copyWith(color: p.ink2)),
        ],
      ]),
    );
  }
}

/// Edge+: the temperature right now, small, beside the greeting's sun or
/// moon. With no place at all it shows a pin to type one in; a tap on the
/// temperature changes the place too.
class GreetingTemp extends StatefulWidget {
  const GreetingTemp({super.key});

  @override
  State<GreetingTemp> createState() => _GreetingTempState();
}

class _GreetingTempState extends State<GreetingTemp> {
  late Future<TodayWeather?> _w = fetchTodayWeather();

  Future<void> _askPlace() async {
    final ctl = TextEditingController(text: weatherPlace());
    var failed = false;
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr(d, 'Ort fürs Wetter', 'Place for the weather')),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: tr(d, 'z. B. Berlin', 'e.g. Berlin'),
              errorText: failed ? tr(d, 'Nicht gefunden', 'Not found') : null,
            ),
          ),
          actions: [
            if (weatherPlace().isNotEmpty)
              TextButton(
                onPressed: () async {
                  await setWeatherPlace('');
                  if (d.mounted) Navigator.pop(d);
                },
                child: Text(tr(d, 'Standort nutzen', 'Use location')),
              ),
            TextButton(
              onPressed: () async {
                final ok = await setWeatherPlace(ctl.text);
                if (!d.mounted) return;
                if (ok) {
                  Navigator.pop(d);
                } else {
                  set(() => failed = true);
                }
              },
              child: Text(tr(d, 'Speichern', 'Save')),
            ),
          ],
        ),
      ),
    );
    ctl.dispose();
    if (mounted) setState(() => _w = fetchTodayWeather());
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return FutureBuilder<TodayWeather?>(
      future: _w,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final w = snap.data;
        return Pressable(
          onTap: _askPlace,
          semanticLabel: w == null
              ? tr(c, 'Ort fürs Wetter eingeben', 'Set a place for the weather')
              : '${w.temp.round()}°',
          child: Padding(
            padding: const EdgeInsets.only(left: S.x1),
            child: w == null
                ? Icon(LucideIcons.mapPin, size: 12, color: p.ink3)
                : Text('${w.temp.round()}°', style: F.mini.copyWith(color: p.ink3)),
          ),
        );
      },
    );
  }
}
