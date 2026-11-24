// Edge+: intermittent-fasting timer on the Nutrition tab.
//
// One running fast at a time: its start (epoch seconds, 0 = none) and the
// goal in hours live in Prefs. Nothing is written to the database.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/prefs.dart';
import '../ui2.dart';

const kFastStartKey = 'plus.fast_start';
const kFastGoalKey = 'plus.fast_goal_h';
const kFastGoals = [12, 14, 16, 18, 20];

/// The goal after [h] in the tap cycle 12 → 14 → 16 → 18 → 20 → 12.
int nextFastGoal(int h) {
  final i = kFastGoals.indexOf(h);
  return kFastGoals[(i + 1) % kFastGoals.length];
}

/// "14:05" for [seconds] of fasting.
String fastClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}';
}

class FastingCard extends StatefulWidget {
  const FastingCard({super.key});

  @override
  State<FastingCard> createState() => _FastingCardState();
}

class _FastingCardState extends State<FastingCard> {
  Timer? _tick;

  int get _start => Prefs.getInt(kFastStartKey, 0);
  int get _goal {
    final g = Prefs.getInt(kFastGoalKey, 16);
    return kFastGoals.contains(g) ? g : 16;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    _tick?.cancel();
    _tick = _start > 0
        ? Timer.periodic(Motion.tick, (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toggle() {
    Prefs.setInt(kFastStartKey, _start > 0 ? 0 : _now());
    setState(_sync);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final running = _start > 0;
    final elapsed = running ? _now() - _start : 0;
    final goal = _goal;
    final done = elapsed >= goal * 3600;
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.timer, size: 18, color: p.on(C.orange)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(tr(c, 'Fasten', 'Fasting'),
                style: F.body.copyWith(color: p.ink)),
          ),
          if (running)
            Text(fastClock(elapsed),
                style: F.head.copyWith(color: done ? p.on(C.green) : p.ink)),
          Pressable(
            onTap: running
                ? null
                : () {
                    Prefs.setInt(kFastGoalKey, nextFastGoal(goal));
                    setState(() {});
                  },
            semanticLabel: tr(c, 'Ziel $goal Stunden', 'Goal $goal hours'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
              child: Text(running ? '/ $goal h' : '$goal:${24 - goal}',
                  style: F.cap.copyWith(color: p.ink2)),
            ),
          ),
          Pressable(
            onTap: _toggle,
            semanticLabel: running
                ? tr(c, 'Fasten beenden', 'End fast')
                : tr(c, 'Fasten starten', 'Start fast'),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running ? p.card2 : p.fill(C.orange)),
                child: Icon(running ? LucideIcons.square : LucideIcons.play,
                    size: 14, color: running ? p.ink : p.inkOnFill),
              ),
            ),
          ),
        ]),
        if (running)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x2),
            child: ClipRRect(
              borderRadius: R.rPill,
              child: LinearProgressIndicator(
                value: (elapsed / (goal * 3600)).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: p.track,
                color: p.fill(done ? C.green : C.orange),
              ),
            ),
          ),
      ]),
    );
  }
}
