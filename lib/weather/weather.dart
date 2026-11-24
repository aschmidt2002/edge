// Edge+: today's weather for the morning check-in.
//
// Open-Meteo (free, no key) at the phone's coarse location. Nothing is stored;
// a failed permission, fix or request simply means no weather box.

import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class TodayWeather {
  final double temp, feelsLike, min, max;
  final int code;
  final int rainChance; // %
  final double rainMm, snowCm, uvMax, gustKmh;

  const TodayWeather({
    required this.temp,
    required this.feelsLike,
    required this.min,
    required this.max,
    required this.code,
    this.rainChance = 0,
    this.rainMm = 0,
    this.snowCm = 0,
    this.uvMax = 0,
    this.gustKmh = 0,
  });

  static TodayWeather? fromOpenMeteo(Map<String, dynamic> j) {
    final cur = j['current'];
    final day = j['daily'];
    if (cur is! Map || day is! Map) return null;
    double? first(String k) {
      final v = day[k];
      return v is List && v.isNotEmpty && v.first is num
          ? (v.first as num).toDouble()
          : null;
    }

    final t = (cur['temperature_2m'] as num?)?.toDouble();
    final min = first('temperature_2m_min'), max = first('temperature_2m_max');
    if (t == null || min == null || max == null) return null;
    return TodayWeather(
      temp: t,
      feelsLike: (cur['apparent_temperature'] as num?)?.toDouble() ?? t,
      min: min,
      max: max,
      code: (cur['weather_code'] as num?)?.toInt() ?? 0,
      rainChance: first('precipitation_probability_max')?.round() ?? 0,
      rainMm: first('precipitation_sum') ?? 0,
      snowCm: first('snowfall_sum') ?? 0,
      uvMax: first('uv_index_max') ?? 0,
      gustKmh: first('wind_gusts_10m_max') ?? 0,
    );
  }

  /// The WMO weather code in German.
  String get description => switch (code) {
        0 => 'Klar',
        1 || 2 => 'Leicht bewölkt',
        3 => 'Bewölkt',
        45 || 48 => 'Nebel',
        51 || 53 || 55 || 56 || 57 => 'Nieselregen',
        61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => 'Regen',
        71 || 73 || 75 || 77 || 85 || 86 => 'Schnee',
        95 || 96 || 99 => 'Gewitter',
        _ => 'Wechselhaft',
      };
}

/// The short tips under the weather. Empty on an ordinary day.
List<String> weatherHints(TodayWeather w) => [
      if (w.uvMax >= 5)
        'Creme dich ein – UV-Index bis ${w.uvMax.round()}.',
      if (w.min <= 1 && (w.rainMm > 0 || w.snowCm > 0))
        'Heute kann es glatt und rutschig werden.'
      else if (w.snowCm > 0)
        'Heute schneit es.',
      if (w.rainChance >= 50 || w.rainMm >= 1)
        'Nimm einen Regenschirm mit.',
      if (w.max <= 8 || w.feelsLike <= 3) 'Zieh dich warm an.',
      if (w.gustKmh >= 50) 'Heute wird es windig.',
    ];

/// Today's weather here, or null when location or network say no.
Future<TodayWeather?> fetchTodayWeather() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 10)),
        );
    // Two decimals (~1 km) is plenty for a forecast and sends no more.
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': pos.latitude.toStringAsFixed(2),
      'longitude': pos.longitude.toStringAsFixed(2),
      'current': 'temperature_2m,apparent_temperature,weather_code',
      'daily': 'temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,precipitation_sum,snowfall_sum,'
          'uv_index_max,wind_gusts_10m_max',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    return j is Map<String, dynamic> ? TodayWeather.fromOpenMeteo(j) : null;
  } catch (_) {
    return null;
  }
}
