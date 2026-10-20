import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'playback_session.dart';

/// 通知/耳机按键复用页面的控制入口，房间同步可替换这些回调。
class PlayerAudio extends BaseAudioHandler with SeekHandler {
  static Future<PlayerAudio>? _instance;
  static Future<PlayerAudio> instance() =>
      _instance ??= AudioService.init<PlayerAudio>(
        builder: PlayerAudio.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'duoscene.playback',
          androidNotificationChannelName: 'Duoscene 播放',
          androidNotificationOngoing: true,
        ),
      );
  PlaybackSession? _session;
  int _ownership = 0;
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function(Duration)? onSeek;
  StreamSubscription<AudioInterruptionEvent>? _interruption;
  StreamSubscription<void>? _noisy;
  Future<void> attach(
    PlaybackSession session, {
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function(Duration) seek,
  }) async {
    final ownership = ++_ownership;
    await _detach();
    if (ownership != _ownership) return;
    _session = session;
    onPlay = play;
    onPause = pause;
    onSeek = seek;
    final audio = await AudioSession.instance;
    if (ownership != _ownership) return;
    await audio.configure(const AudioSessionConfiguration.music());
    if (ownership != _ownership) return;
    // 中断只暂停；不猜测中断期间用户或远端是否又发过暂停。
    _interruption = audio.interruptionEventStream.listen((event) {
      if (event.begin) unawaited(this.pause());
    });
    _noisy = audio.becomingNoisyEventStream.listen(
      (_) => unawaited(this.pause()),
    );
    session.addListener(publish);
    publish();
  }

  void publish() {
    final session = _session;
    if (session == null) return;
    final core = session.core;
    mediaItem.add(
      MediaItem(
        id: session.source?.identity ?? 'duoscene',
        title: session.source?.title ?? 'Duoscene',
        duration: core.playerDuration,
      ),
    );
    playbackState.add(
      PlaybackState(
        controls: [
          core.playerPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0],
        processingState: session.loading
            ? AudioProcessingState.loading
            : core.playerBuffering
            ? AudioProcessingState.buffering
            : core.mediaPlayer == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: core.playerPlaying,
        updatePosition: core.playerPosition,
        bufferedPosition: core.playerBuffer,
        speed: core.playerSpeed,
      ),
    );
  }

  @override
  Future<void> play() async {
    await (await AudioSession.instance).setActive(true);
    await onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await onPause?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    await onSeek?.call(position);
  }

  @override
  Future<void> stop() async {
    await pause();
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle),
    );
  }

  Future<void> detach({PlaybackSession? owner}) async {
    if (owner != null && !identical(owner, _session)) return;
    ++_ownership;
    await _detach();
  }

  Future<void> _detach() async {
    _session?.removeListener(publish);
    _session = null;
    final interruption = _interruption;
    final noisy = _noisy;
    _interruption = null;
    _noisy = null;
    onPlay = null;
    onPause = null;
    onSeek = null;
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle),
    );
    await interruption?.cancel();
    await noisy?.cancel();
  }
}
