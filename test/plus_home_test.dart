// Edge+: the band status colour and the daily check-in timing.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/journal_prompt.dart';
import 'package:openstrap_edge/ui2/tab_header.dart';
import 'package:openstrap_edge/weather/weather.dart';

void main() {
  final now = DateTime(2026, 11, 24, 9, 0);

  test('band: green within five minutes, orange after, red when not connected',
      () {
    expect(
        bandLinkOf(
            connected: true,
            lastData: now.subtract(const Duration(minutes: 4)),
            now: now),
        BandLink.fresh);
    expect(
        bandLinkOf(
            connected: true,
            lastData: now.subtract(const Duration(minutes: 6)),
            now: now),
        BandLink.stale);
    expect(bandLinkOf(connected: true, lastData: null, now: now),
        BandLink.stale);
    expect(bandLinkOf(connected: false, lastData: now, now: now),
        BandLink.none);
  });

  test('check-in: morning from 04:00, evening from 20:00, once a day', () {
    CheckIn? at(int h, {String m = '', String e = ''}) =>
        dueCheckIn(DateTime(2026, 11, 24, h), lastMorning: m, lastEvening: e);
    expect(at(3), isNull);
    expect(at(4), CheckIn.morning);
    expect(at(12, m: '2026-11-24'), isNull);
    expect(at(12, m: '2026-11-23'), CheckIn.morning);
    expect(at(20, m: '2026-11-24'), CheckIn.evening);
    expect(at(22, e: '2026-11-24'), isNull);
  });

  test('weather tips: nothing on an ordinary day, the right ones otherwise',
      () {
    const mild = TodayWeather(temp: 15, feelsLike: 15, min: 10, max: 18, code: 1);
    expect(weatherHints(mild), isEmpty);
    const icy = TodayWeather(
        temp: -1, feelsLike: -4, min: -2, max: 3, code: 71, snowCm: 1);
    expect(weatherHints(icy),
        containsAll(['Heute kann es glatt und rutschig werden.', 'Zieh dich warm an.']));
    const summer = TodayWeather(
        temp: 26, feelsLike: 26, min: 16, max: 30, code: 0, uvMax: 7);
    expect(weatherHints(summer).single, startsWith('Creme dich ein'));
    const storm = TodayWeather(
        temp: 12, feelsLike: 10, min: 9, max: 14, code: 63,
        rainChance: 80, rainMm: 6, gustKmh: 65);
    expect(weatherHints(storm),
        ['Nimm einen Regenschirm mit.', 'Heute wird es windig.']);
    expect(
        TodayWeather.fromOpenMeteo({
          'current': {'temperature_2m': 4.2, 'apparent_temperature': 1.0, 'weather_code': 3},
          'daily': {'temperature_2m_min': [1.0], 'temperature_2m_max': [6.5], 'uv_index_max': [1.2]},
        })?.description,
        'Bewölkt');
  });
}
