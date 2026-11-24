// Edge+: the header Home and Sleep share.
//
// Band status on the left, the day stepper in the middle, the profile avatar
// on the right. One widget so both tabs look and behave the same.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import 'grammar.dart';
import 'profile/devices.dart' show MyDevices;
import 'profile/profile.dart' show ProfileAvatar;
import 'screens/home_screen.dart' show go, lowBattery;
import 'screens/metric_detail.dart' show DayNav, dayNavLabel;
import 'theme.dart';

/// Edge+: the Sleep tab's header, which the live guides anchor on now that
/// the tab has no title line.
const kSleepHeaderKey = ValueKey<String>('edge-plus-sleep-header');

/// How the band is doing, as one colour.
enum BandLink {
  /// Connected and the newest data is at most five minutes old.
  fresh,

  /// Connected, but the newest data is older than five minutes.
  stale,

  /// Not connected: nothing is arriving.
  none,
}

/// Green within five minutes, orange after that, red when nothing arrives.
BandLink bandLinkOf(
    {required bool connected, DateTime? lastData, required DateTime now}) {
  if (!connected) return BandLink.none;
  if (lastData != null &&
      now.difference(lastData) <= const Duration(minutes: 5)) {
    return BandLink.fresh;
  }
  return BandLink.stale;
}

typedef _BandRead = ({
  bool paired,
  bool connected,
  DateTime? lastData,
  double? pct,
  bool? charging,
});

/// A small band glyph with a status dot and the battery under it.
class BandStatusIcon extends StatefulWidget {
  const BandStatusIcon({super.key});

  @override
  State<BandStatusIcon> createState() => _BandStatusIconState();
}

class _BandStatusIconState extends State<BandStatusIcon> {
  // The five-minute line moves with the clock, not only with AppState.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  _BandRead? _read(BuildContext c) {
    try {
      return c.select<AppState, _BandRead>((a) => (
            paired: a.isPaired,
            connected: a.isConnected,
            lastData: a.lastRecordAt,
            pct: a.device.batteryPct,
            charging: a.device.charging,
          ));
    } catch (_) {
      return null; // goldens: no AppState
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = _read(c);
    final link = r == null
        ? BandLink.none
        : bandLinkOf(
            connected: r.connected, lastData: r.lastData, now: DateTime.now());
    final dot = switch (link) {
      BandLink.fresh => C.green,
      BandLink.stale => C.orange,
      BandLink.none => C.red,
    };
    final pct = r?.pct;
    final low = pct != null && lowBattery(pct, r?.charging ?? false);
    final word = switch (link) {
      BandLink.fresh => 'Band verbunden, aktuell',
      BandLink.stale => 'Band verbunden, letzte Daten älter als 5 Minuten',
      BandLink.none => 'Band empfängt keine Daten',
    };
    return Pressable(
      semanticLabel:
          pct == null ? word : '$word. Akku ${pct.round()} Prozent',
      onTap: r == null ? null : () => go(c, const MyDevices()),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 30,
          height: 28,
          child: Stack(clipBehavior: Clip.none, children: [
            Center(child: Icon(LucideIcons.watch, size: 22, color: p.ink2)),
            Positioned(
              top: 1,
              right: 1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.fill(dot),
                  border: Border.all(color: p.bg, width: 1.5),
                ),
              ),
            ),
          ]),
        ),
        if (pct != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (r?.charging == true)
              Icon(LucideIcons.zap, size: 9, color: p.ink3),
            Text('${pct.round()}%',
                style: F.mini.copyWith(color: low ? p.on(C.red) : p.ink3)),
          ]),
      ]),
    );
  }
}

/// Band status · day stepper · profile, in one row at the top of a tab.
class TabHeader extends StatelessWidget {
  final String? day;
  final List<String> days;
  final ValueChanged<String>? onDay;
  final Color accent;

  const TabHeader({
    super.key,
    required this.day,
    this.days = const [],
    this.onDay,
    this.accent = C.domHome,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final nav = onDay;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Row(children: [
        const SizedBox(width: 44, child: Center(child: BandStatusIcon())),
        const SizedBox(width: S.x2),
        Expanded(
          child: days.length >= 2 && nav != null
              ? DayNav(day: day, days: days, onDay: nav)
              : Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: p.card2, borderRadius: R.rMd),
                  child: Text(
                    dayNavLabel(day, l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.body
                        .copyWith(color: p.ink, fontWeight: FontWeight.w600),
                  ),
                ),
        ),
        const SizedBox(width: S.x2),
        SizedBox(
            width: 44, child: Center(child: ProfileAvatar(accent: accent))),
      ]),
    );
  }
}
