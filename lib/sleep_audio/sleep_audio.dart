// Edge+: the player behind Sleep → Einschlafen → Klänge & Geschichten.
//
// just_audio plays; audio_service wraps it in a media session with its own
// foreground service, so playback carries on with the phone locked and the
// lock screen shows play/pause. The app's long-lived engine is shared with
// audio_service (EdgeApplication sets its engine id), so there is still one
// Dart isolate.
//
// ponytail: one player, one item at a time, no queue. A sleep sound or one
// episode is all anyone plays at bedtime.

import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'noise.dart';
import 'podcasts.dart';

/// What is loaded in the player.
class NowPlaying {
  const NowPlaying(this.id, this.title, this.subtitle, {this.sound});
  final String id;
  final String title;
  final String subtitle;

  /// Set for a looping sleep sound, null for an episode.
  final SleepSound? sound;
}

class _Handler extends BaseAudioHandler with SeekHandler {
  _Handler() {
    player.playbackEventStream.listen(_broadcast, onError: (_) {});
    player.playingStream.listen((_) => _broadcast(player.playbackEvent));
  }

  final player = AudioPlayer();

  void _broadcast(PlaybackEvent e) {
    final playing = player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1],
      processingState: switch (player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
    ));
  }

  @override
  Future<void> play() async => unawaited(player.play());

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    SleepAudio.instance._savePosition();
    await player.stop();
    SleepAudio.instance._stopped();
    await super.stop();
  }
}

class SleepAudio extends ChangeNotifier {
  SleepAudio._();
  static final instance = SleepAudio._();

  Future<_Handler>? _handler;
  _Handler? _h;

  NowPlaying? now;
  bool playing = false;
  bool loading = false;
  String? error;

  /// When the sleep timer ends playback, or null with no timer.
  DateTime? timerEnd;
  Timer? _tick;
  int _saveCountdown = 0;

  /// The fade at the end of the timer.
  static const _fade = Duration(seconds: 30);

  Future<_Handler> _ready() => _handler ??= _init();

  Future<_Handler> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    final h = await AudioService.init(
      builder: _Handler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'wtf.openstrap.openstrap_edge.sleep_audio',
        androidNotificationChannelName: 'Einschlafen',
        androidNotificationIcon: 'drawable/ic_widget_sleep',
        // A media button after the app was closed must not cold-start the
        // engine through audio_service: the app's own engine comes up with its
        // platform channels only through EdgeApplication.ensureEngine.
        androidResumeOnClick: false,
      ),
    );
    _h = h;
    h.player.playingStream.listen((p) {
      playing = p;
      notifyListeners();
    });
    h.player.processingStateStream.listen((s) {
      loading = s == ProcessingState.loading || s == ProcessingState.buffering;
      if (s == ProcessingState.completed && now?.sound == null) {
        _clearPosition(now?.id);
      }
      notifyListeners();
    });
    return h;
  }

  Stream<Duration> get positionStream =>
      _h?.player.positionStream ?? const Stream.empty();
  Duration? get duration => _h?.player.duration;

  Future<void> playSound(SleepSound s, String title, String subtitle) async {
    if (now?.sound == s) return toggle();
    await _load(NowPlaying('sound:${s.name}', title, subtitle, sound: s),
        (p) async {
      final f = await sleepSoundFile(s);
      await p.setLoopMode(LoopMode.one);
      return p.setFilePath(f.path);
    });
  }

  Future<void> playEpisode(PodcastEpisode e, String show, {String? art}) async {
    if (now?.id == e.url) return toggle();
    await _load(NowPlaying(e.url, e.title, show), (p) async {
      await p.setLoopMode(LoopMode.off);
      final d = await p.setUrl(e.url);
      final at = await _savedPosition(e.url);
      if (at != null && (d == null || at < d - const Duration(minutes: 1))) {
        await p.seek(at);
      }
      return d;
    }, art: e.artwork ?? art);
  }

  Future<void> _load(NowPlaying item,
      Future<Duration?> Function(AudioPlayer) open, {String? art}) async {
    _savePosition();
    error = null;
    now = item;
    loading = true;
    notifyListeners();
    try {
      final h = await _ready();
      await h.player.stop();
      await h.player.setVolume(1);
      final d = await open(h.player);
      h.mediaItem.add(MediaItem(
        id: item.id,
        title: item.title,
        album: item.subtitle,
        duration: item.sound == null ? d : null,
        artUri: art == null ? null : Uri.tryParse(art),
      ));
      unawaited(h.play());
      _arm();
    } catch (e) {
      // A failed init would otherwise stay cached and fail every later tap.
      if (_h == null) _handler = null;
      error = '$e';
      now = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    final h = _h;
    if (h == null || now == null) return;
    if (h.player.playing) {
      _savePosition();
      await h.pause();
    } else {
      await h.player.setVolume(1);
      await h.play();
    }
  }

  Future<void> skip(Duration by) async {
    final p = _h?.player;
    if (p == null || now?.sound != null) return;
    var to = p.position + by;
    if (to < Duration.zero) to = Duration.zero;
    await p.seek(to);
  }

  Future<void> stop() async => _h?.stop();

  void _stopped() {
    now = null;
    timerEnd = null;
    _tick?.cancel();
    _tick = null;
    notifyListeners();
  }

  /// [d] null turns the timer off.
  void setTimer(Duration? d) {
    timerEnd = d == null ? null : DateTime.now().add(d);
    _h?.player.setVolume(1);
    _arm();
    notifyListeners();
  }

  Duration? get timerLeft {
    final e = timerEnd;
    if (e == null) return null;
    final left = e.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// One second tick while something is loaded: the timer's fade and the
  /// saved place in a long episode.
  void _arm() {
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final h = _h;
    if (h == null || now == null) return;
    final left = timerLeft;
    if (left != null) {
      if (left == Duration.zero) {
        timerEnd = null;
        unawaited(h.stop());
        return;
      }
      if (left < _fade) {
        h.player.setVolume(left.inMilliseconds / _fade.inMilliseconds);
      }
      notifyListeners();
    }
    if (h.player.playing && ++_saveCountdown >= 15) {
      _saveCountdown = 0;
      _savePosition();
    }
  }

  // ── where an episode was left ─────────────────────────────────────────────

  static const _posKey = 'edge_plus_sleep_audio_positions';

  void _savePosition() {
    final h = _h;
    final item = now;
    if (h == null || item == null || item.sound != null) return;
    final at = h.player.position;
    unawaited(_writePosition(item.id, at));
  }

  Future<Map<String, int>> _positions(SharedPreferences prefs) async {
    try {
      final j = jsonDecode(prefs.getString(_posKey) ?? '{}');
      return {
        if (j is Map)
          for (final MapEntry(:key, :value) in j.entries)
            if (key is String && value is int) key: value,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writePosition(String id, Duration at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = await _positions(prefs)
        ..remove(id);
      if (at > const Duration(seconds: 30)) m[id] = at.inMilliseconds;
      // Newest last; keep the last 50 episodes.
      final kept = m.entries.toList();
      final trimmed = kept.length > 50 ? kept.sublist(kept.length - 50) : kept;
      await prefs.setString(_posKey, jsonEncode(Map.fromEntries(trimmed)));
    } catch (_) {}
  }

  void _clearPosition(String? id) {
    if (id != null) unawaited(_writePosition(id, Duration.zero));
  }

  Future<Duration?> _savedPosition(String id) async {
    try {
      final m = await _positions(await SharedPreferences.getInstance());
      final ms = m[id];
      return ms == null ? null : Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  // ── remembered shows ──────────────────────────────────────────────────────

  static const _showsKey = 'edge_plus_sleep_audio_shows';

  Future<List<PodcastShow>> savedShows() async {
    try {
      final j = jsonDecode(
          (await SharedPreferences.getInstance()).getString(_showsKey) ?? '[]');
      return [if (j is List) for (final s in j) ?PodcastShow.fromJson(s)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setSaved(PodcastShow show, bool saved) async {
    final all = [
      for (final s in await savedShows())
        if (s.feedUrl != show.feedUrl) s,
      if (saved) show,
    ];
    try {
      await (await SharedPreferences.getInstance())
          .setString(_showsKey, jsonEncode([for (final s in all) s.toJson()]));
    } catch (_) {}
    notifyListeners();
  }
}
