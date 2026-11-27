// Live heart rate from any sensor that speaks the standard Bluetooth Heart
// Rate Service (0x180D / 0x2A37): WHOOP with "Heart Rate Broadcast" switched
// on in the WHOOP app, Polar Verity Sense / H10, Garmin broadcast, most chest
// straps. This is the route that works for a brand-new WHOOP too, because it
// needs no access to WHOOP's private protocol.
//
// What it cannot do: read WHOOP's overnight HRV or make the WHOOP vibrate.
// Both need the direct protocol link (see pacing/README.md, "WHOOP und iPhone").

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final Guid kHrService = Guid('180d');
final Guid kHrMeasurement = Guid('2a37');

/// Decodes one Heart Rate Measurement notification. Returns null for a
/// malformed packet instead of guessing a number.
int? parseHeartRate(List<int> v) {
  if (v.isEmpty) return null;
  final flags = v[0];
  final wide = flags & 0x01 == 0x01;
  if (wide) {
    if (v.length < 3) return null;
    return v[1] | (v[2] << 8);
  }
  if (v.length < 2) return null;
  return v[1];
}

class FoundSensor {
  const FoundSensor(this.id, this.name, this.rssi);
  final String id;
  final String name;
  final int rssi;
}

class BleHeartRate {
  final _hr = StreamController<int>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  StreamSubscription<List<int>>? _notify;
  StreamSubscription<BluetoothConnectionState>? _state;
  BluetoothDevice? _device;
  String? _wantedId;

  Stream<int> get heartRate => _hr.stream;
  Stream<bool> get connected => _connected.stream;

  /// Scans for heart-rate sensors for a few seconds.
  Stream<List<FoundSensor>> scan({Duration timeout = const Duration(seconds: 8)}) {
    FlutterBluePlus.startScan(withServices: [kHrService], timeout: timeout);
    return FlutterBluePlus.scanResults.map((rs) => [
          for (final r in rs)
            FoundSensor(
              r.device.remoteId.str,
              r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : 'Herzfrequenz-Sensor',
              r.rssi,
            ),
        ]);
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// Connects and keeps reconnecting until [disconnect]. autoConnect lets the
  /// OS reconnect when the sensor comes back in range; with the
  /// bluetooth-central background mode on iOS this keeps running while the
  /// screen is off.
  Future<void> connect(String id) async {
    await disconnect();
    _wantedId = id;
    final d = BluetoothDevice.fromId(id);
    _device = d;
    _state = d.connectionState.listen((s) async {
      final up = s == BluetoothConnectionState.connected;
      _connected.add(up);
      if (up) {
        await _subscribe(d);
      } else if (_wantedId == id) {
        _notify?.cancel();
      }
    });
    await d.connect(autoConnect: true, mtu: null);
  }

  Future<void> _subscribe(BluetoothDevice d) async {
    try {
      final services = await d.discoverServices();
      for (final s in services) {
        if (s.uuid != kHrService) continue;
        for (final c in s.characteristics) {
          if (c.uuid != kHrMeasurement) continue;
          await _notify?.cancel();
          _notify = c.onValueReceived.listen((v) {
            final hr = parseHeartRate(v);
            if (hr != null && hr > 25 && hr < 230) _hr.add(hr);
          });
          d.cancelWhenDisconnected(_notify!);
          await c.setNotifyValue(true);
          return;
        }
      }
    } catch (_) {
      // The next connect event retries.
    }
  }

  Future<void> disconnect() async {
    _wantedId = null;
    await _notify?.cancel();
    await _state?.cancel();
    _notify = null;
    _state = null;
    final d = _device;
    _device = null;
    if (d != null) await d.disconnect();
    _connected.add(false);
  }
}
