// When to vibrate. Alert fatigue is the enemy: an alarm that fires all day is
// switched off by day three. So there are only three levels, each fires once
// per episode, a level has to clear before it can fire again, and nothing
// fires in quiet hours except the hard "over the ceiling" alarm.

enum AlertLevel { none, nudge, warn, stop }

class AlertInput {
  const AlertInput({
    required this.now,
    required this.batteryShare,
    this.hr,
    this.ceiling,
    this.secondsOverCeiling = 0,
  });
  final DateTime now;
  final double batteryShare; // 0..1
  final double? hr;
  final int? ceiling;

  /// Seconds the heart rate has been at or over the ceiling, continuously.
  final int secondsOverCeiling;
}

class AlertEvent {
  const AlertEvent(this.level, this.title, this.body);
  final AlertLevel level;
  final String title;
  final String body;
}

class AlertPolicy {
  AlertPolicy({
    this.batteryWarnShare = 0.2,
    this.quietStart = 22,
    this.quietEnd = 8,
    this.overCeilingSeconds = 30,
    this.minGap = const Duration(minutes: 10),
  });

  double batteryWarnShare;
  int quietStart;
  int quietEnd;
  int overCeilingSeconds;
  Duration minGap;

  bool _hrArmed = true;
  bool _nudgeArmed = true;
  bool _batteryArmed = true;
  bool _emptyArmed = true;
  DateTime? _lastFired;

  bool _quiet(DateTime t) => quietStart > quietEnd
      ? (t.hour >= quietStart || t.hour < quietEnd)
      : (t.hour >= quietStart && t.hour < quietEnd);

  /// Call once per heart-rate sample or battery change. Returns what to fire
  /// now, or null.
  AlertEvent? evaluate(AlertInput i) {
    final c = i.ceiling;
    final hr = i.hr;

    // Re-arm once the condition has cleared with some margin.
    if (c != null && hr != null && hr < c - 8) {
      _hrArmed = true;
      _nudgeArmed = true;
    }
    if (i.batteryShare > batteryWarnShare + 0.05) _batteryArmed = true;
    if (i.batteryShare > 0.05) _emptyArmed = true;

    AlertEvent? e;
    if (c != null && hr != null && _hrArmed &&
        i.secondsOverCeiling >= overCeilingSeconds) {
      _hrArmed = false;
      _nudgeArmed = false;
      e = AlertEvent(AlertLevel.stop, 'Über deiner Grenze',
          'Puls ${hr.round()} liegt über $c. Wenn möglich: hinsetzen oder hinlegen und abwarten.');
      // The ceiling alarm ignores quiet hours and the gap: it is the one that
      // matters most.
      _lastFired = i.now;
      return e;
    }
    if (_quiet(i.now)) return null;
    if (_lastFired != null && i.now.difference(_lastFired!) < minGap) {
      return null;
    }

    if (_emptyArmed && i.batteryShare <= 0.05) {
      _emptyArmed = false;
      _batteryArmed = false;
      e = const AlertEvent(AlertLevel.stop, 'Akku leer',
          'Dein geschätzter Rahmen für heute ist aufgebraucht. Zeit für echte Ruhe.');
    } else if (_batteryArmed && i.batteryShare <= batteryWarnShare) {
      _batteryArmed = false;
      e = AlertEvent(AlertLevel.warn, 'Akku niedrig',
          'Noch etwa ${(i.batteryShare * 100).round()} %. Plane jetzt eine Pause ein, nicht erst später.');
    } else if (c != null && hr != null && _nudgeArmed && hr >= c - 5 && hr < c) {
      _nudgeArmed = false;
      e = AlertEvent(AlertLevel.nudge, 'Nah an der Grenze',
          'Puls ${hr.round()}, Grenze $c. Etwas langsamer machen?');
    }
    if (e != null) _lastFired = i.now;
    return e;
  }
}
