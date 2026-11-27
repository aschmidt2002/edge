// Turns an AlertEvent into something the body notices.
//
// Today: a local notification with vibration on the phone (and, on iPhone,
// mirrored to an Apple Watch if one is paired — the watch then taps the
// wrist). Tomorrow: a [BandBuzzer] that makes the WHOOP itself vibrate over
// the direct protocol link. The interface is here so that link can be
// plugged in without touching the pacing logic.

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/alerts.dart';

/// Something on the body that can vibrate. Implemented later by the WHOOP
/// direct link (OpenStrap protocol: haptic opcode).
abstract class BandBuzzer {
  Future<bool> buzz(AlertLevel level);
}

class Alerter {
  Alerter({this.band});
  BandBuzzer? band;
  final _n = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await _n.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<void> requestPermission() async {
    await init();
    await _n
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
    await _n
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Int64List _pattern(AlertLevel l) => Int64List.fromList(switch (l) {
        AlertLevel.nudge => [0, 150],
        AlertLevel.warn => [0, 250, 150, 250],
        _ => [0, 500, 200, 500, 200, 500],
      });

  Future<void> fire(AlertEvent e) async {
    await init();
    final bandOk = await band?.buzz(e.level) ?? false;
    HapticFeedback.heavyImpact();
    await _n.show(
      id: e.level.index,
      title: e.title,
      body: e.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'pacing_${e.level.name}',
          switch (e.level) {
            AlertLevel.nudge => 'Hinweise nahe der Grenze',
            AlertLevel.warn => 'Akku niedrig',
            _ => 'Grenze überschritten',
          },
          importance: e.level == AlertLevel.nudge
              ? Importance.defaultImportance
              : Importance.high,
          priority: Priority.high,
          enableVibration: !bandOk,
          vibrationPattern: bandOk ? null : _pattern(e.level),
          playSound: false,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: false,
          interruptionLevel: e.level == AlertLevel.stop
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
    );
  }
}
