// The Sleep tab.
//
// Sleep used to be spread over the Home ring, a Health row that opened a
// generic chart, Wellness's "Recovery" sub-tab (need, debt, bedtime), Health's
// Body clock and the alarm in Settings. This tab is the Sleep screen itself,
// with those pieces under the night. The screens are the same ones; only
// where they live changed.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../profile/alarm.dart';
import '../experimental/xp_features.dart'
    show SleepPlannerCard, XpScreen, loadSleepStress;
import '../ui2.dart';
import '../../sleep_audio/sleep_audio.dart';
import '../../stress/winddown_log.dart';
import 'calm_breathing.dart';
import 'circadian_detail.dart';
import 'metric_detail.dart' show detailLinkRow;
import 'sleep_detail.dart';
import 'wellness_screen.dart';
import 'winddown_screen.dart';

class SleepTab extends StatelessWidget {
  const SleepTab({super.key});

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    void push(Widget w) => Navigator.of(c)
        .push(MaterialPageRoute<void>(builder: (_) => w));
    final stress = tr(c, 'Schlaf-Stress', 'Sleep stress');
    return SleepDetail(
      embedded: true,
      // Edge+: one heading for tonight, the planner first (it is the one
      // with something to set), the coach's figures under it.
      todayFooter: [
        Section(
          tr(c, 'Heute Nacht', 'Tonight'),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SleepPlannerCard(),
              SizedBox(height: S.x3),
              WellnessScreen(sleepPlanOnly: true),
            ],
          ),
        ),
      ],
      // Edge+: three doors in one row, no heading and no subtitles — the
      // icon and the word say what is behind each.
      footer: [
        // Edge+: falling asleep — the breathing exercises (moved here from
        // Health) and the sleep sounds and stories.
        const SizedBox(height: S.x5),
        const _Winddown(),
        const SizedBox(height: S.x5),
        _Doors([
          (
            LucideIcons.alarmClock,
            l?.settingsAlarmRowTitle ?? 'Alarm',
            () => push(const AlarmScreen()),
          ),
          (
            LucideIcons.sunMoon,
            l?.healthBodyClockTitle ?? 'Body clock',
            () => push(const CircadianDetail()),
          ),
          (
            LucideIcons.moonStar,
            stress,
            () => push(XpScreen(stress, loadSleepStress)),
          ),
        ]),
      ],
    );
  }
}

/// Small square doors side by side; stacked as rows at big text, where three
/// across would leave each word a letter wide.
class _Doors extends StatelessWidget {
  final List<(IconData, String, VoidCallback)> doors;
  const _Doors(this.doors);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget door((IconData, String, VoidCallback) d, {required bool row}) =>
        Pressable(
          onTap: d.$3,
          semanticLabel: d.$2,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: S.x3, vertical: S.x4),
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
            child: Flex(
              direction: row ? Axis.horizontal : Axis.vertical,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(d.$1, size: 20, color: p.ink2),
                SizedBox(width: row ? S.x3 : 0, height: row ? 0 : S.x2),
                if (row)
                  Expanded(child: _label(p, d.$2))
                else
                  _label(p, d.$2, center: true),
              ],
            ),
          ),
        );
    if (bigText(c)) {
      return Column(children: [
        for (var i = 0; i < doors.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x2),
          door(doors[i], row: true),
        ],
      ]);
    }
    // Equal thirds AND equal height: a one-line word ("Wecker") used to
    // leave its tile shorter than the two-line ones beside it.
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < doors.length; i++) ...[
          if (i > 0) const SizedBox(width: S.x2),
          Expanded(child: door(doors[i], row: false)),
        ],
      ]),
    );
  }

  static Widget _label(P p, String s, {bool center = false}) => Text(s,
      textAlign: center ? TextAlign.center : TextAlign.start,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600));
}

/// Edge+: Einschlafen — two doors, each saying what is new behind it.
class _Winddown extends StatelessWidget {
  const _Winddown();

  @override
  Widget build(BuildContext c) {
    void push(Widget w) =>
        Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));
    final audio = SleepAudio.instance;
    return Section(
      tr(c, 'Einschlafen', 'Falling asleep'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ValueListenableBuilder<int>(
          valueListenable: WinddownLog.changed,
          builder: (c, _, _) => FutureBuilder<List<WinddownEntry>>(
            future: WinddownLog.load(),
            builder: (c, s) {
              final best = rankWinddown(s.data ?? const []).firstOrNull;
              final hr = best?.hr;
              return detailLinkRow(
                c,
                LucideIcons.wind,
                tr(c, 'Atemübungen', 'Breathing exercises'),
                best == null || hr == null || hr >= 0
                    ? tr(c, 'Mit Puls vorher und nachher',
                        'With heart rate before and after')
                    : tr(c,
                        'Am ruhigsten: ${winddownLabel(c, best.key, best.label)} '
                            '(Puls ${hr.toStringAsFixed(0)})',
                        'Calms you most: ${winddownLabel(c, best.key, best.label)} '
                            '(HR ${hr.toStringAsFixed(0)})'),
                () => push(const CalmBreathing()),
              );
            },
          ),
        ),
        const SizedBox(height: S.x2),
        ListenableBuilder(
          listenable: audio,
          builder: (c, _) => detailLinkRow(
            c,
            LucideIcons.headphones,
            tr(c, 'Klänge & Geschichten', 'Sounds & stories'),
            audio.now != null
                ? tr(c, 'Läuft: ${audio.now!.title}',
                    'Playing: ${audio.now!.title}')
                : tr(c, 'Regen, Meer, Rauschen, Hörspiele',
                    'Rain, sea, noise, radio plays'),
            () => push(const WinddownScreen()),
          ),
        ),
      ]),
    );
  }
}
