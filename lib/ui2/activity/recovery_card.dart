// Edge+: Recovery on the Activity tab — one big ring, four small bubbles
// around it (stress, sleep, heart, strain), each a door to its own screen.
//
// Reads the same `HomeData` Home's rings read, so the two tabs can never show
// different numbers for the same morning.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/decimal_text.dart';
import '../experimental/xp_core.dart' show stressColor, hmText;
import '../experimental/xp_features.dart'
    show XpScreen, xpStressToday, loadStressNow;
import '../screens/home_screen.dart' show HomeData, readinessBand, go, repoOf;
import '../screens/metric_detail.dart' show MetricDetail;
import '../screens/readiness_detail.dart' show ReadinessDetail;
import '../screens/sleep_detail.dart' show SleepDetail;
import '../ui2.dart';
import 'day_strain.dart' show DayStrainDetail;

/// Today's numbers for the card: Home's day plus the newest stress reading.
typedef RecoveryRead = ({HomeData d, double? stress});

Future<RecoveryRead?> loadRecovery(BuildContext c) async {
  final repo = repoOf(c);
  if (repo == null) return null;
  final l = AppLocalizations.of(c);
  final d = await HomeData.load(repo, l);
  double? stress;
  try {
    final s = await xpStressToday(repo);
    if (s != null && s.s.isNotEmpty) stress = s.s.last;
  } catch (_) {}
  return (d: d, stress: stress);
}

class RecoveryCard extends StatefulWidget {
  const RecoveryCard({super.key});

  @override
  State<RecoveryCard> createState() => _RecoveryCardState();
}

class _RecoveryCardState extends State<RecoveryCard> with RevisionReload {
  Future<RecoveryRead?>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= loadRecovery(context);
  }

  @override
  void reload() {
    setState(() {
      _load = loadRecovery(context);
    });
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<RecoveryRead?>(
    future: _load,
    builder: (c, snap) {
      final r = snap.data;
      if (r == null) return const SizedBox.shrink();
      return RecoveryRing(d: r.d, stress: r.stress);
    },
  );
}

class RecoveryRing extends StatelessWidget {
  final HomeData d;
  final double? stress;
  const RecoveryRing({super.key, required this.d, this.stress});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final v = d.readiness.value;
    final band = readinessBand(v, l);
    final sleep = d.sleepMin.value, rhr = d.rhr.value, strain = d.strain.value;
    final s = stress;
    return Surface(
      elevation: 2,
      semanticLabel: 'Recovery',
      child: SizedBox(
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The faint orbit the bubbles sit on.
            Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.track, width: 1),
              ),
            ),
            Pressable(
              onTap: () => go(c, const ReadinessDetail()),
              semanticLabel: 'Recovery ${v?.round() ?? ''} ${band.label}',
              child: SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: Ring(
                          ((v ?? 0) / 100).clamp(0.0, 1.0),
                          p.on(band.color),
                          p.track,
                          stroke: 10,
                          t: animate(c, 1),
                          solid: v != null,
                          background: p.card,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('RECOVERY', style: F.over.copyWith(color: p.ink3)),
                        Text(
                          v == null ? '–' : '${v.round()}%',
                          style: F.n34.copyWith(color: p.ink),
                        ),
                        Text(
                          band.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.cap.copyWith(
                            color: p.on(band.color),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.topLeft,
              child: _Bubble(
                LucideIcons.activity,
                s == null ? C.n400 : stressColor(s),
                'Stress',
                s == null ? '–' : displayFixed(s, 1),
                () => go(c, XpScreen('Stress', loadStressNow)),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: _Bubble(
                LucideIcons.moon,
                C.blue,
                tr(c, 'Schlaf', 'Sleep'),
                sleep == null ? '–' : hmText(sleep),
                () => go(c, const SleepDetail()),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: _Bubble(
                LucideIcons.heart,
                C.red,
                tr(c, 'Herz', 'Heart'),
                rhr == null ? '–' : '${rhr.round()}',
                () => go(c, const MetricDetail('resting_hr')),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: _Bubble(
                LucideIcons.zap,
                C.purple,
                'Strain',
                strain == null ? '–' : displayFixed(strain, 1),
                () => go(c, const DayStrainDetail()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  final VoidCallback onTap;
  const _Bubble(this.icon, this.color, this.label, this.value, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label $value',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 150),
        padding: const EdgeInsets.fromLTRB(4, 4, S.x3, 4),
        decoration: BoxDecoration(
          color: p.card2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: p.on(color).withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: p.on(color)),
            ),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.cap.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: S.x1),
            Text(value, style: F.cap.copyWith(color: p.ink2)),
          ],
        ),
      ),
    );
  }
}
