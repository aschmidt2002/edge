// Edge+: today's weather for the morning check-in.
//
// Open-Meteo (free, no key) at the phone's coarse location. Nothing is stored;
// a failed permission, fix or request simply means no weather box.

import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../state/prefs.dart';

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

  /// The WMO weather code in words, German when [de], else English.
  String description({bool de = true}) => switch (code) {
        0 => de ? 'Klar' : 'Clear',
        1 || 2 => de ? 'Leicht bewölkt' : 'Partly cloudy',
        3 => de ? 'Bewölkt' : 'Cloudy',
        45 || 48 => de ? 'Nebel' : 'Fog',
        51 || 53 || 55 || 56 || 57 => de ? 'Nieselregen' : 'Drizzle',
        61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => de ? 'Regen' : 'Rain',
        71 || 73 || 75 || 77 || 85 || 86 => de ? 'Schnee' : 'Snow',
        95 || 96 || 99 => de ? 'Gewitter' : 'Thunderstorm',
        _ => de ? 'Wechselhaft' : 'Changeable',
      };
}

/// The short tips under the weather, German when [de], else English. Empty
/// on an ordinary day.
List<String> weatherHints(TodayWeather w, {bool de = true}) => [
      if (w.uvMax >= 5)
        de
            ? 'Creme dich ein – UV-Index bis ${w.uvMax.round()}.'
            : 'Put on sunscreen – UV index up to ${w.uvMax.round()}.',
      if (w.min <= 1 && (w.rainMm > 0 || w.snowCm > 0))
        de
            ? 'Heute kann es glatt und rutschig werden.'
            : 'It may get icy and slippery today.'
      else if (w.snowCm > 0)
        de ? 'Heute schneit es.' : 'Snow today.',
      if (w.rainChance >= 50 || w.rainMm >= 1)
        de ? 'Nimm einen Regenschirm mit.' : 'Take an umbrella.',
      if (w.max <= 8 || w.feelsLike <= 3)
        de ? 'Zieh dich warm an.' : 'Dress warmly.',
      if (w.gustKmh >= 50) de ? 'Heute wird es windig.' : 'Windy today.',
    ];

/// Today's weather here, or null when location or network say no.
///
/// One fetch per app run, so the morning sheet finds it ready when the shell
/// started it early. A fix that fails falls back to the last place a fix
/// worked, so a slow GPS no longer means no weather.
Future<TodayWeather?> fetchTodayWeather() {
  final day = DateTime.now().day;
  if (_memo == null || _memoDay != day) {
    _memoDay = day;
    _memo = _fetch().then((w) {
      if (w == null) _memo = null; // try again next time
      return w;
    });
  }
  return _memo!;
}

Future<TodayWeather?>? _memo;
int? _memoDay;

const _kLat = 'plus.weather_lat', _kLon = 'plus.weather_lon';

Future<(double, double)?> _position() async {
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
    Position? pos;
    try {
      pos = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    pos ??= await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
    );
    Prefs.setString(_kLat, pos.latitude.toStringAsFixed(2));
    Prefs.setString(_kLon, pos.longitude.toStringAsFixed(2));
    return (pos.latitude, pos.longitude);
  } catch (_) {
    final lat = double.tryParse(Prefs.getString(_kLat, ''));
    final lon = double.tryParse(Prefs.getString(_kLon, ''));
    return lat == null || lon == null ? null : (lat, lon);
  }
}

Future<TodayWeather?> _fetch() async {
  try {
    final pos = await _position();
    if (pos == null) return null;
    // Two decimals (~1 km) is plenty for a forecast and sends no more.
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': pos.$1.toStringAsFixed(2),
      'longitude': pos.$2.toStringAsFixed(2),
      'current': 'temperature_2m,apparent_temperature,weather_code',
      'daily': 'temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,precipitation_sum,snowfall_sum,'
          'uv_index_max,wind_gusts_10m_max',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    return j is Map<String, dynamic> ? TodayWeather.fromOpenMeteo(j) : null;
  } catch (_) {
    return null;
  }
}

/// Starts [fetchTodayWeather] and waits for it at most [seconds], so a sheet
/// can open with the weather already in it instead of popping in later.
Future<void> warmTodayWeather({int seconds = 4}) => Future.any<void>([
      fetchTodayWeather(),
      Future<void>.delayed(Duration(seconds: seconds)),
    ]);
