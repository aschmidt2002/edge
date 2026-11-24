// Edge+: stories and radio plays for falling asleep, from free podcast feeds.
//
// Why podcasts and not YouTube: playing YouTube audio with the screen off is
// against YouTube's terms (that is YouTube Premium), and there is no official
// way to do it. Podcast feeds are published to be downloaded and played in
// any player, which includes the ARD's radio plays and the German sleep
// podcasts. Apple's podcast directory (the iTunes Search API, free, no key)
// turns a name into the feed address, so nothing here hard-codes a URL that
// can move.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class PodcastShow {
  const PodcastShow({
    required this.title,
    required this.author,
    required this.feedUrl,
    this.artwork,
  });
  final String title;
  final String author;
  final String feedUrl;
  final String? artwork;

  Map<String, Object?> toJson() =>
      {'t': title, 'a': author, 'f': feedUrl, 'i': artwork};

  static PodcastShow? fromJson(Object? j) => j is Map && j['f'] is String
      ? PodcastShow(
          title: (j['t'] as String?) ?? '',
          author: (j['a'] as String?) ?? '',
          feedUrl: j['f'] as String,
          artwork: j['i'] as String?,
        )
      : null;
}

class PodcastEpisode {
  const PodcastEpisode({
    required this.title,
    required this.url,
    this.duration,
    this.published,
    this.artwork,
  });
  final String title;
  final String url;
  final Duration? duration;
  final DateTime? published;
  final String? artwork;
}

/// A shelf on the screen: a German heading and the directory search behind it.
class PodcastShelf {
  const PodcastShelf(this.de, this.en, this.query);
  final String de, en, query;
}

/// What the screen offers before anyone searches. Searches, not URLs: the
/// directory resolves each to whatever the show's feed is today.
const kPodcastShelves = <PodcastShelf>[
  PodcastShelf('Einschlafen', 'Falling asleep', 'Einschlafen'),
  PodcastShelf('Hörspiele', 'Radio plays', 'ARD Hörspiel'),
  PodcastShelf('Gute-Nacht-Geschichten', 'Bedtime stories', 'Gute Nacht Geschichte'),
  PodcastShelf('Hörbücher', 'Audiobooks', 'Hörbuch gelesen'),
];

/// Shows matching [term] in the German directory. Empty on any failure.
Future<List<PodcastShow>> searchPodcasts(String term,
    {http.Client? client}) async {
  final uri = Uri.https('itunes.apple.com', '/search', {
    'term': term,
    'media': 'podcast',
    'country': 'DE',
    'limit': '25',
  });
  try {
    final res = await (client?.get(uri) ?? http.get(uri))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];
    return parseItunesSearch(utf8.decode(res.bodyBytes));
  } catch (_) {
    return const [];
  }
}

List<PodcastShow> parseItunesSearch(String body) {
  final j = jsonDecode(body);
  final results = j is Map ? j['results'] : null;
  if (results is! List) return const [];
  return [
    for (final r in results)
      if (r is Map && r['feedUrl'] is String)
        PodcastShow(
          title: (r['collectionName'] ?? r['trackName'] ?? '').toString(),
          author: (r['artistName'] ?? '').toString(),
          feedUrl: r['feedUrl'] as String,
          artwork: (r['artworkUrl600'] ?? r['artworkUrl100']) as String?,
        ),
  ];
}

/// The episodes in a show's feed, newest first as the feed lists them.
Future<List<PodcastEpisode>> loadEpisodes(String feedUrl,
    {http.Client? client}) async {
  final uri = Uri.parse(feedUrl);
  final res = await (client?.get(uri) ?? http.get(uri))
      .timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', uri);
  }
  return parseFeed(utf8.decode(res.bodyBytes, allowMalformed: true));
}

List<PodcastEpisode> parseFeed(String xml) {
  final doc = XmlDocument.parse(xml);
  final channelArt = doc
      .findAllElements('itunes:image')
      .firstOrNull
      ?.getAttribute('href');
  final out = <PodcastEpisode>[];
  for (final item in doc.findAllElements('item')) {
    final enc = item.findElements('enclosure').firstOrNull;
    var url = enc?.getAttribute('url');
    final type = enc?.getAttribute('type') ?? 'audio/';
    if (url == null || !type.startsWith('audio')) continue;
    // Android refuses cleartext by default; almost every host serves both.
    if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
    out.add(PodcastEpisode(
      title: item.findElements('title').firstOrNull?.innerText.trim() ?? '',
      url: url,
      duration: parseItunesDuration(
          item.findElements('itunes:duration').firstOrNull?.innerText),
      published: _rfc822(item.findElements('pubDate').firstOrNull?.innerText),
      artwork: item.findElements('itunes:image').firstOrNull?.getAttribute('href') ??
          channelArt,
    ));
  }
  return out;
}

/// `3600`, `59:30` or `1:02:03`.
Duration? parseItunesDuration(String? s) {
  if (s == null) return null;
  final parts = s.trim().split(':').map(int.tryParse).toList();
  if (parts.isEmpty || parts.any((p) => p == null)) return null;
  var secs = 0;
  for (final p in parts) {
    secs = secs * 60 + p!;
  }
  return secs > 0 ? Duration(seconds: secs) : null;
}

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// `Tue, 05 Nov 2024 18:00:00 +0100` → the day; the time is not shown.
DateTime? _rfc822(String? s) {
  final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4})').firstMatch(s ?? '');
  final mon = _months[m?.group(2)];
  if (m == null || mon == null) return null;
  return DateTime(int.parse(m.group(3)!), mon, int.parse(m.group(1)!));
}
