// Edge+: the falling-asleep pieces — before/after ranking, the podcast feed
// parsing and the generated sleep sounds.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/sleep_audio/noise.dart';
import 'package:openstrap_edge/sleep_audio/podcasts.dart';
import 'package:openstrap_edge/stress/breath_phases.dart';
import 'package:openstrap_edge/stress/winddown_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

WinddownEntry _e(String key, double h0, double h1, {double? r0, double? r1}) =>
    WinddownEntry(
      at: DateTime(2026, 11, 24),
      key: key,
      label: key,
      preHr: h0,
      postHr: h1,
      preRmssd: r0,
      postRmssd: r1,
    );

void main() {
  group('rankWinddown', () {
    test('biggest heart-rate drop first, averaged per exercise', () {
      final r = rankWinddown([
        _e('box', 70, 68),
        _e('cyclic_sigh', 70, 62),
        _e('cyclic_sigh', 66, 62),
        _e('resonance', 70, 65),
        _e('resonance_5_0', 70, 66),
      ]);
      expect(r.map((x) => x.key), ['cyclic_sigh', 'resonance', 'box']);
      expect(r.first.hr, -6);
      expect(r.first.count, 2);
      expect(r[1].count, 2, reason: 'a personal pace counts as resonance');
    });

    test('an entry with nothing measured is left out', () {
      final none = WinddownEntry(at: DateTime(2026), key: 'box', label: 'Box');
      expect(none.hasAny, isFalse);
      expect(rankWinddown([none]), isEmpty);
    });

    test('round-trips through the log', () async {
      SharedPreferences.setMockInitialValues({});
      await WinddownLog.add(_e('humming', 64, 60, r0: 30, r1: 41));
      final back = await WinddownLog.load();
      expect(back, hasLength(1));
      expect(back.single.key, 'humming');
      expect(back.single.hrDelta, -4);
      expect(back.single.rmssdDelta, 11);
      expect(back.single.respDelta, isNull);
    });
  });

  test('the new patterns are in the table, unscored', () {
    for (final k in ['cyclic_sigh', 'humming']) {
      final p = kBreathPatternsByKey[k]!;
      expect(p.coherenceRated, isFalse);
      expect(p.cycleSeconds, greaterThan(0));
    }
  });

  group('podcasts', () {
    test('directory search keeps only results with a feed', () {
      final shows = parseItunesSearch('{"resultCount":2,"results":['
          '{"collectionName":"Einschlafen Podcast","artistName":"Toby",'
          '"feedUrl":"https://example.org/feed","artworkUrl600":"https://example.org/a.jpg"},'
          '{"collectionName":"No feed"}]}');
      expect(shows, hasLength(1));
      expect(shows.single.title, 'Einschlafen Podcast');
      expect(shows.single.feedUrl, 'https://example.org/feed');
    });

    test('feed: audio enclosures only, https, durations and dates', () {
      final eps = parseFeed('''<?xml version="1.0"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<itunes:image href="https://example.org/show.jpg"/>
<item><title> Folge 1 </title><pubDate>Tue, 05 Nov 2024 18:00:00 +0100</pubDate>
<enclosure url="http://example.org/1.mp3" type="audio/mpeg"/><itunes:duration>1:02:03</itunes:duration></item>
<item><title>Video</title><enclosure url="https://example.org/v.mp4" type="video/mp4"/></item>
<item><title>Folge 2</title><enclosure url="https://example.org/2.mp3" type="audio/mpeg"/><itunes:duration>600</itunes:duration></item>
</channel></rss>''');
      expect(eps.map((e) => e.title), ['Folge 1', 'Folge 2']);
      expect(eps.first.url, 'https://example.org/1.mp3');
      expect(eps.first.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(eps.first.published, DateTime(2024, 11, 5));
      expect(eps.first.artwork, 'https://example.org/show.jpg');
      expect(eps.last.duration, const Duration(minutes: 10));
    });

    test('duration forms', () {
      expect(parseItunesDuration('59:30'), const Duration(minutes: 59, seconds: 30));
      expect(parseItunesDuration('abc'), isNull);
      expect(parseItunesDuration(null), isNull);
    });
  });

  group('sleep sounds', () {
    test('a valid mono 16-bit WAV of the asked length', () {
      final wav = sleepSoundWav(SleepSound.rain, seconds: 2);
      final b = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(b.getUint16(22, Endian.little), 1);
      expect(b.getUint32(24, Endian.little), 22050);
      expect(wav.length, 44 + 2 * 22050 * 2);
    });

    test('every sound has signal and stays under full scale', () {
      for (final s in SleepSound.values) {
        final wav = sleepSoundWav(s, seconds: 2);
        final b = ByteData.sublistView(wav);
        var peak = 0;
        for (var i = 44; i < wav.length; i += 2) {
          final v = b.getInt16(i, Endian.little).abs();
          if (v > peak) peak = v;
        }
        expect(peak, greaterThan(10000), reason: s.name);
        expect(peak, lessThan(32767), reason: s.name);
      }
    });

    test('the loop seam does not jump', () {
      // The last sample flows into the first: their gap is no bigger than a
      // typical step inside the loop.
      final wav = sleepSoundWav(SleepSound.brown, seconds: 3);
      final b = ByteData.sublistView(wav);
      int at(int i) => b.getInt16(44 + i * 2, Endian.little);
      final n = (wav.length - 44) ~/ 2;
      var maxStep = 0;
      for (var i = 1; i < n; i++) {
        final d = (at(i) - at(i - 1)).abs();
        if (d > maxStep) maxStep = d;
      }
      expect((at(0) - at(n - 1)).abs(), lessThanOrEqualTo(maxStep));
    });
  });
}
