// Edge+: Schlaf → Einschlafen → Klänge & Geschichten.
//
// Sleep sounds made on the phone, and stories / radio plays from free podcast
// feeds. Everything plays on with the phone locked (lib/sleep_audio). Kept to
// one screen and one player: pick, set a timer, put the phone away.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../sleep_audio/noise.dart';
import '../../sleep_audio/podcasts.dart';
import '../../sleep_audio/sleep_audio.dart';
import '../ui2.dart';
import 'metric_detail.dart' show detailScaffold;

String soundName(BuildContext c, SleepSound s) => switch (s) {
  SleepSound.rain => tr(c, 'Regen', 'Rain'),
  SleepSound.waves => tr(c, 'Meer', 'Sea'),
  SleepSound.brown => tr(c, 'Braunes Rauschen', 'Brown noise'),
  SleepSound.pink => tr(c, 'Rosa Rauschen', 'Pink noise'),
  SleepSound.white => tr(c, 'Weißes Rauschen', 'White noise'),
};

IconData _soundIcon(SleepSound s) => switch (s) {
  SleepSound.rain => LucideIcons.cloudRain,
  SleepSound.waves => LucideIcons.waves,
  SleepSound.brown => LucideIcons.audioWaveform,
  SleepSound.pink => LucideIcons.audioLines,
  SleepSound.white => LucideIcons.wind,
};

class WinddownScreen extends StatefulWidget {
  const WinddownScreen({super.key});

  @override
  State<WinddownScreen> createState() => _WinddownScreenState();
}

class _WinddownScreenState extends State<WinddownScreen> {
  final _q = TextEditingController();
  List<PodcastShow> _saved = const [];
  List<PodcastShow>? _results;
  String? _shelf;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    SleepAudio.instance.addListener(_reloadSaved);
    _reloadSaved();
  }

  @override
  void dispose() {
    SleepAudio.instance.removeListener(_reloadSaved);
    _q.dispose();
    super.dispose();
  }

  Future<void> _reloadSaved() async {
    final s = await SleepAudio.instance.savedShows();
    if (mounted && s.length != _saved.length) setState(() => _saved = s);
  }

  Future<void> _search(String term, {String? shelf}) async {
    if (term.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _shelf = shelf;
    });
    final r = await searchPodcasts(term.trim());
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = r;
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final audio = SleepAudio.instance;
    return ListenableBuilder(
      listenable: audio,
      builder: (c, _) => detailScaffold(
        c,
        tr(c, 'Klänge & Geschichten', 'Sounds & stories'),
        [
          if (audio.now != null) ...[
            const PlayerCard(),
            const SizedBox(height: S.x2),
          ],
          if (audio.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: Text(
                tr(c, 'Konnte nicht abgespielt werden.', 'Could not play that.'),
                style: F.cap.copyWith(color: p.on(C.red)),
              ),
            ),
          Section(tr(c, 'Klänge', 'Sounds'), _sounds(c, audio)),
          Section(
            tr(c, 'Geschichten & Hörspiele', 'Stories & radio plays'),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _searchBox(c, p),
              const SizedBox(height: S.x3),
              Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                for (final s in kPodcastShelves)
                  _Chip(
                    tr(c, s.de, s.en),
                    on: _shelf == s.query,
                    onTap: () {
                      _q.clear();
                      _search(s.query, shelf: s.query);
                    },
                  ),
              ]),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.all(S.x5),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_results != null) ...[
                const SizedBox(height: S.x3),
                if (_results!.isEmpty)
                  Text(
                    tr(c, 'Nichts gefunden, oder keine Verbindung.',
                        'Nothing found, or no connection.'),
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                for (final s in _results!) _ShowRow(s),
              ],
              if (_saved.isNotEmpty) ...[
                const SizedBox(height: S.x4),
                Text(tr(c, 'GEMERKT', 'SAVED'),
                    style: F.over.copyWith(color: p.ink3)),
                for (final s in _saved) _ShowRow(s),
              ],
              const SizedBox(height: S.x3),
              Text(
                tr(
                  c,
                  'Aus frei verfügbaren Podcast-Feeds, z. B. ARD-Hörspielen. '
                      'Läuft auch bei gesperrtem Handy weiter.',
                  'From freely available podcast feeds such as the ARD\'s '
                      'radio plays. Keeps playing with the phone locked.',
                ),
                style: F.over.copyWith(color: p.ink3, height: 1.5),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sounds(BuildContext c, SleepAudio audio) {
    final p = P.of(c);
    Widget tile(SleepSound s) {
      final on = audio.now?.sound == s;
      return Pressable(
        onTap: () => audio.playSound(
            s, soundName(c, s), tr(c, 'Einschlafen', 'Falling asleep')),
        semanticLabel: soundName(c, s),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: S.x4, horizontal: S.x2),
          decoration: BoxDecoration(
            color: on ? p.wash(C.domMind) : p.card2,
            borderRadius: R.rMd,
          ),
          child: Column(children: [
            Icon(_soundIcon(s), size: 20, color: on ? p.on(C.domMind) : p.ink2),
            const SizedBox(height: S.x2),
            Text(soundName(c, s),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }

    const all = SleepSound.values;
    return Column(children: [
      for (var r = 0; r < all.length; r += 3) ...[
        if (r > 0) const SizedBox(height: S.x2),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = r; i < r + 3; i++) ...[
              if (i > r) const SizedBox(width: S.x2),
              Expanded(child: i < all.length ? tile(all[i]) : const SizedBox()),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _searchBox(BuildContext c, P p) => Container(
    constraints: const BoxConstraints(minHeight: S.tap),
    padding: const EdgeInsets.symmetric(horizontal: S.x4),
    decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
    child: Row(children: [
      Icon(LucideIcons.search, size: 17, color: p.ink3),
      const SizedBox(width: S.x2),
      Expanded(
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => _search(v),
          style: F.body.copyWith(color: p.ink),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            hintText: tr(c, 'Podcast oder Hörspiel suchen', 'Search podcasts'),
            hintStyle: F.body.copyWith(color: p.ink3),
          ),
        ),
      ),
    ]),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
        decoration: BoxDecoration(
          color: on ? p.fill(C.domMind) : p.card2,
          borderRadius: R.rMd,
        ),
        child: Text(label,
            style: F.cap.copyWith(color: on ? p.inkOnFill : p.ink2)),
      ),
    );
  }
}

class _ShowRow extends StatelessWidget {
  const _ShowRow(this.show);
  final PodcastShow show;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.only(top: S.x2),
      child: Surface(
        onTap: () => Navigator.of(c).push(MaterialPageRoute<void>(
            builder: (_) => EpisodesScreen(show))),
        child: Row(children: [
          if (show.artwork != null) ...[
            ClipRRect(
              borderRadius: R.rMd,
              child: Image.network(show.artwork!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(width: 40)),
            ),
            const SizedBox(width: S.x3),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(show.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              if (show.author.isNotEmpty)
                Text(show.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ]),
      ),
    );
  }
}

/// One show's episodes. A tap plays; the bookmark keeps the show on the
/// first screen.
class EpisodesScreen extends StatefulWidget {
  const EpisodesScreen(this.show, {super.key});
  final PodcastShow show;

  @override
  State<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends State<EpisodesScreen> {
  List<PodcastEpisode>? _eps;
  bool _failed = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final saved = await SleepAudio.instance.savedShows();
    _saved = saved.any((s) => s.feedUrl == widget.show.feedUrl);
    try {
      final e = await loadEpisodes(widget.show.feedUrl);
      if (mounted) setState(() => _eps = e);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final audio = SleepAudio.instance;
    return ListenableBuilder(
      listenable: audio,
      builder: (c, _) => detailScaffold(
        c,
        widget.show.title,
        sub: widget.show.author,
        trailing: Pressable(
          onTap: () async {
            setState(() => _saved = !_saved);
            await audio.setSaved(widget.show, _saved);
          },
          semanticLabel: tr(c, 'Merken', 'Save'),
          child: Icon(
            _saved ? LucideIcons.bookmarkCheck : LucideIcons.bookmark,
            size: 20,
            color: _saved ? p.on(C.domMind) : p.ink2,
          ),
        ),
        [
          if (audio.now != null) ...[
            const PlayerCard(),
            const SizedBox(height: S.x3),
          ],
          if (_failed)
            StatusCard(
              tr(c, 'Feed nicht erreichbar', 'Feed unavailable'),
              tr(c, 'Keine Verbindung, oder der Podcast gibt seinen Feed nicht frei.',
                  'No connection, or the show does not share its feed.'),
              icon: LucideIcons.wifiOff,
            )
          else if (_eps == null)
            const Padding(
              padding: EdgeInsets.all(S.x6),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final e in _eps!.take(100))
              Padding(
                padding: const EdgeInsets.only(bottom: S.x2),
                child: Surface(
                  onTap: () => audio.playEpisode(e, widget.show.title,
                      art: widget.show.artwork),
                  color: audio.now?.id == e.url ? p.wash(C.domMind) : null,
                  child: Row(children: [
                    Icon(
                      audio.now?.id == e.url && audio.playing
                          ? LucideIcons.pause
                          : LucideIcons.play,
                      size: 18,
                      color: p.on(C.domMind),
                    ),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: F.body.copyWith(color: p.ink)),
                            if (_meta(e).isNotEmpty)
                              Text(_meta(e),
                                  style: F.cap.copyWith(color: p.ink3)),
                          ]),
                    ),
                  ]),
                ),
              ),
        ],
      ),
    );
  }

  static String _meta(PodcastEpisode e) => [
    if (e.published case final d?)
      '${d.day}.${d.month}.${d.year}',
    if (e.duration case final d?) clockMinutes(d),
  ].join(' · ');
}

String clockMinutes(Duration d) => d.inHours > 0
    ? '${d.inHours} h ${d.inMinutes % 60} min'
    : '${d.inMinutes} min';

/// What is playing, its controls and the sleep timer.
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key});

  static const _timers = [15, 30, 45, 60];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final a = SleepAudio.instance;
    final now = a.now;
    if (now == null) return const SizedBox.shrink();
    final left = a.timerLeft;
    Widget btn(IconData i, String label, VoidCallback onTap, {bool big = false}) =>
        Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Container(
            width: big ? 52 : 40,
            height: big ? 52 : 40,
            decoration: BoxDecoration(
              color: big ? p.fill(C.domMind) : p.card2,
              shape: BoxShape.circle,
            ),
            child: Icon(i, size: big ? 22 : 17, color: big ? p.inkOnFill : p.ink2),
          ),
        );
    return Surface(
      color: p.wash(C.domMind),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(now.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        Text(now.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: F.cap.copyWith(color: p.ink3)),
        if (now.sound == null)
          StreamBuilder<Duration>(
            stream: a.positionStream,
            builder: (c, s) {
              final d = a.duration;
              final at = s.data ?? Duration.zero;
              return Padding(
                padding: const EdgeInsets.only(top: S.x2),
                child: Text(
                  d == null ? clockMinutes(at) : '${clockMinutes(at)} / ${clockMinutes(d)}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              );
            },
          ),
        const SizedBox(height: S.x3),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (now.sound == null) ...[
            btn(LucideIcons.rotateCcw, tr(c, '15 s zurück', 'Back 15 s'),
                () => a.skip(const Duration(seconds: -15))),
            const SizedBox(width: S.x4),
          ],
          a.loading
              ? const SizedBox(
                  width: 52,
                  height: 52,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : btn(a.playing ? LucideIcons.pause : LucideIcons.play,
                  a.playing ? tr(c, 'Pause', 'Pause') : tr(c, 'Abspielen', 'Play'),
                  a.toggle,
                  big: true),
          const SizedBox(width: S.x4),
          if (now.sound == null) ...[
            btn(LucideIcons.rotateCw, tr(c, '30 s vor', 'Forward 30 s'),
                () => a.skip(const Duration(seconds: 30))),
            const SizedBox(width: S.x4),
          ],
          btn(LucideIcons.square, tr(c, 'Stopp', 'Stop'), a.stop),
        ]),
        const SizedBox(height: S.x3),
        Row(children: [
          Icon(LucideIcons.timer, size: 16, color: p.ink3),
          const SizedBox(width: S.x2),
          Expanded(
            child: Wrap(spacing: S.x2, runSpacing: S.x2, children: [
              _Chip(tr(c, 'Aus', 'Off'),
                  on: left == null, onTap: () => a.setTimer(null)),
              for (final m in _timers)
                _Chip('$m min',
                    on: false, onTap: () => a.setTimer(Duration(minutes: m))),
            ]),
          ),
        ]),
        if (left != null)
          Padding(
            padding: const EdgeInsets.only(top: S.x2),
            child: Text(
              tr(c, 'Leiser werden und aus in ${_mmss(left)}',
                  'Fades out and stops in ${_mmss(left)}'),
              style: F.cap.copyWith(color: p.ink2),
            ),
          ),
      ]),
    );
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
