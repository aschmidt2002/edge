// Edge+: sleep sounds made on the phone. No download, no licence, no network:
// each one is a one-minute loop of shaped noise written once as a WAV file
// and looped by the player. The loop's last second is cross-faded into its
// first, so the seam does not click.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

enum SleepSound { rain, waves, brown, pink, white }

const _rate = 22050;
const _seconds = 60;
const _fade = _rate; // one second

/// Raw samples in -1..1, [n] long, for [kind]. Deterministic per seed.
Float64List noiseSamples(SleepSound kind, int n, {int seed = 7}) {
  final r = math.Random(seed);
  double w() => r.nextDouble() * 2 - 1;
  final out = Float64List(n);
  switch (kind) {
    case SleepSound.white:
      for (var i = 0; i < n; i++) {
        out[i] = w();
      }
    case SleepSound.pink:
      _pink(out, w);
    case SleepSound.brown:
      _brown(out, w);
    case SleepSound.rain:
      // Soft pink bed plus many small drops: short bursts of bright noise
      // that die away in a few milliseconds.
      _pink(out, w);
      for (var i = 0; i < n; i++) {
        out[i] *= 0.55;
      }
      final drops = (n / _rate * 45).round();
      for (var d = 0; d < drops; d++) {
        final at = r.nextInt(n);
        final amp = 0.15 + r.nextDouble() * 0.5;
        final len = 120 + r.nextInt(500);
        var lp = 0.0;
        for (var k = 0; k < len && at + k < n; k++) {
          lp += 0.6 * (w() - lp);
          out[at + k] += amp * lp * math.exp(-6 * k / len);
        }
      }
    case SleepSound.waves:
      // Brown surf that swells and falls every ten seconds, a little hiss at
      // the crest. 60 s holds six whole swells, so the loop lines up.
      final brown = Float64List(n);
      _brown(brown, w);
      final hiss = Float64List(n);
      _pink(hiss, w);
      for (var i = 0; i < n; i++) {
        final t = i / _rate;
        final swell = 0.5 - 0.5 * math.cos(2 * math.pi * t / 10);
        final env = 0.18 + 0.82 * math.pow(swell, 1.6);
        out[i] = env * (brown[i] + 0.25 * swell * hiss[i]);
      }
  }
  return out;
}

void _pink(Float64List out, double Function() w) {
  // Paul Kellet's economy pink filter.
  var b0 = 0.0, b1 = 0.0, b2 = 0.0;
  for (var i = 0; i < out.length; i++) {
    final x = w();
    b0 = 0.99765 * b0 + x * 0.0990460;
    b1 = 0.96300 * b1 + x * 0.2965164;
    b2 = 0.57000 * b2 + x * 1.0526913;
    out[i] = b0 + b1 + b2 + x * 0.1848;
  }
}

void _brown(Float64List out, double Function() w) {
  var y = 0.0;
  for (var i = 0; i < out.length; i++) {
    y = (y + 0.02 * w()) * 0.998; // leaky, so it never drifts off
    out[i] = y;
  }
}

/// A seamless one-minute 16-bit mono WAV of [kind].
Uint8List sleepSoundWav(SleepSound kind, {int seconds = _seconds}) {
  final n = seconds * _rate;
  final raw = noiseSamples(kind, n + _fade);
  // Cross-fade the tail into the head: sample i of the loop mixes the head's
  // i with the tail's n+i, so the end flows straight into the start.
  final s = Float64List(n);
  for (var i = 0; i < n; i++) {
    if (i < _fade) {
      final a = i / _fade;
      s[i] = raw[i] * a + raw[n + i] * (1 - a);
    } else {
      s[i] = raw[i];
    }
  }
  var peak = 1e-9;
  for (final v in s) {
    peak = math.max(peak, v.abs());
  }
  final gain = 0.6 / peak;
  final data = ByteData(44 + n * 2);
  void str(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      data.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, _rate, Endian.little);
  data.setUint32(28, _rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    data.setInt16(44 + i * 2, (s[i] * gain * 32767).round().clamp(-32768, 32767),
        Endian.little);
  }
  return data.buffer.asUint8List();
}

/// The file for [kind], made on first use (off the UI isolate).
Future<File> sleepSoundFile(SleepSound kind) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/sleep_sounds');
  final f = File('${dir.path}/${kind.name}_v1.wav');
  if (await f.exists()) return f;
  await dir.create(recursive: true);
  final bytes = await Isolate.run(() => sleepSoundWav(kind));
  final tmp = File('${f.path}.part');
  await tmp.writeAsBytes(bytes, flush: true);
  return tmp.rename(f.path);
}
