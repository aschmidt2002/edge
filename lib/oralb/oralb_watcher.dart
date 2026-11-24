// Edge+: listens for the paired Oral-B brush and records what it hears.
//
// Same shape as `scale_presence.dart`: while the app process lives (Android
// keeps it with the foreground service), a short low-power scan filtered to
// the brush's address runs every [gap]. Once the brush is heard brushing, the
// scan keeps running in [window]-long stretches until [BrushTracker] closes
// the session, which then lands in [OralBStore]. Nothing connects: the brush
// broadcasts everything this reads.
//
// ponytail: a fixed duty cycle, so up to [gap] + [window] of the first
// seconds of a session can go unheard; the brush's own timer still gives the
// full length, so only an early pressure warning can be missed. A brush that
// is never awake while the app runs records nothing: its history behind the
// Oral-B app's GATT protocol is not readable.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/ble_state.dart' show withScanLock;
import 'oralb.dart';

class OralBWatcher {
  OralBWatcher._();
  static final instance = OralBWatcher._();

  static const window = Duration(seconds: 10);
  static const gap = Duration(seconds: 30);

  /// The brush's live advert while a session is open, else null.
  final live = ValueNotifier<OralBAdvert?>(null);

  final _tracker = BrushTracker();
  bool _stop = true;
  Future<void>? _loop;
  Completer<void>? _nap;

  void start() {
    if (!_stop) return;
    _stop = false;
    _loop ??= _run().whenComplete(() => _loop = null);
  }

  Future<void> stop() async {
    _stop = true;
    if (_nap case final n? when !n.isCompleted) n.complete();
    await _loop;
  }

  /// Wake the loop now (a brush was just paired).
  void poke() {
    if (_nap case final n? when !n.isCompleted) n.complete();
  }

  Future<void> _run() async {
    while (!_stop) {
      var wait = gap;
      final id = OralBStore.deviceId;
      try {
        if (id.isNotEmpty) {
          await _listen(id, busy: _tracker.open);
          final s = _tracker.flush(DateTime.now().millisecondsSinceEpoch);
          if (s != null) OralBStore.add(s);
          if (_tracker.open) wait = Duration.zero;
        }
      } catch (e) {
        // No permission or the radio is off: back off, never spin.
        debugPrint('[oralb] cycle failed: $e');
      }
      if (!_tracker.open) live.value = null;
      if (_stop) break;
      final nap = _nap = Completer<void>();
      await Future.any([Future<void>.delayed(wait), nap.future]);
    }
  }

  Future<void> _listen(String id, {required bool busy}) => withScanLock(() async {
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (r.device.remoteId.str.toLowerCase() != id.toLowerCase()) continue;
        final raw = r.advertisementData.manufacturerData[kOralBCompanyId];
        final a = raw == null ? null : parseOralB(raw);
        if (a == null) continue;
        final s = _tracker.feed(a, r.timeStamp.millisecondsSinceEpoch);
        if (s != null) OralBStore.add(s);
        live.value = _tracker.open ? a : null;
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withRemoteIds: [id],
        timeout: window,
        oneByOne: true,
        androidScanMode:
            busy ? AndroidScanMode.lowLatency : AndroidScanMode.lowPower,
      ).timeout(const Duration(seconds: 10));
      await FlutterBluePlus.isScanning
          .where((on) => !on)
          .first
          .timeout(window + const Duration(seconds: 5));
    } on TimeoutException {
      await FlutterBluePlus.stopScan().catchError((Object _) {});
    } finally {
      await sub.cancel();
    }
  });
}

/// A one-off scan for any nearby Oral-B brush (the connect screen).
/// Reports each brush once per update, keyed by remote id.
Future<void> scanForBrushes(
  void Function(Map<String, ({String name, int rssi})>) onResults, {
  Duration timeout = const Duration(seconds: 15),
}) => withScanLock(() async {
  final found = <String, ({String name, int rssi})>{};
  final sub = FlutterBluePlus.onScanResults.listen((results) {
    for (final r in results) {
      final raw = r.advertisementData.manufacturerData[kOralBCompanyId];
      final a = raw == null ? null : parseOralB(raw);
      if (a == null) continue;
      found[r.device.remoteId.str] = (name: oralBModelName(a.modelId), rssi: r.rssi);
    }
    onResults(Map.of(found));
  });
  try {
    await FlutterBluePlus.startScan(
      withMsd: [MsdFilter(kOralBCompanyId)],
      timeout: timeout,
    );
    await FlutterBluePlus.isScanning
        .where((on) => !on)
        .first
        .timeout(timeout + const Duration(seconds: 5));
  } on TimeoutException {
    await FlutterBluePlus.stopScan().catchError((Object _) {});
  } finally {
    await sub.cancel();
  }
});
