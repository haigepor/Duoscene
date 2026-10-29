import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_source.dart';
import 'playra/player_support.dart';
import 'playra/controller/player_debug_controller.dart';
import 'playra/controller/player_playback_controller.dart';
import 'playra/controller/player_panel_controller.dart';
import 'playra/controller/player_seek_controller.dart';
import 'playra/controller/player_screenshot_controller.dart';

/// Duoscene 持有 Playra 控制器；原生加载/切换/销毁串行，UI 只通过此入口操作。
class PlaybackSession extends ChangeNotifier {
  PlaybackSession({PlaybackPreferences? preferences})
    : preferences = preferences ?? PlaybackPreferences();
  final PlaybackPreferences preferences;
  final shaders = ShaderAssetService();
  final debug = PlayerDebugController();
  final panel = PlayerPanelController();
  final screenshots = PlayerScreenshotController();
  final _operations = AsyncSerialQueue();
  final _presentationChanges = ChangeNotifier();
  Listenable get presentationChanges => _presentationChanges;
  Object? _lastState, _lastPresentation;
  late final core = PlayerPlaybackController(
    shaderAssetService: shaders,
    debug: debug,
    preferences: preferences,
    videoUrl: () => _openingSource!.uri.toString(),
    isLocalPlayback: () => _openingSource?.uri.scheme == 'file',
    onNotice: (message) {
      if (!_disposed) {
        notice = message;
        _changed();
      }
    },
  );
  late final seeking = PlayerSeekController(
    playback: core,
    clearOverlays: () {},
    pause: ({bool enableSync = true}) => pause(),
    play: ({bool enableSync = true}) => play(),
    onSeekCompleted: (_) async {},
  );
  PlaybackSource? _openingSource;
  PlaybackSource? source;
  List<PlaybackSource> playlist = [];
  int playlistIndex = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _prepared = false;
  Future<void>? _preparing;
  int get generation => _generation;
  bool loading = false;
  String? error;
  String? notice;
  Timer? _poll;
  Timer? _sleep;
  DateTime? sleepAt;
  StreamSubscription<String>? _errors;
  Future<void>? _closing;

  /// 房间会话把用户意图送往服务端；远端目标只通过 applyTarget/load(synchronized) 落地。
  Future<void> Function(String, Map<String, dynamic>)? remoteCommand;
  Object get _presentationState => (
    source,
    generation,
    loading,
    error,
    notice,
    core.mediaPlayer,
    core.videoController,
    core.playerPlaying,
    core.playerBuffering,
    core.playerCompleted,
    core.playerDuration,
    core.playerSpeed,
    panel.aspectRatioMode,
    screenshots.candidates.length,
    sleepAt,
  );
  Object _stateFor(Object presentation) => (
    presentation,
    core.playerPosition,
    core.playerBuffer,
    core.playerVolume,
    core.superResolutionMode,
    core.mediaPlayer?.state.track,
    core.mediaPlayer?.state.tracks,
  );

  void _changed() {
    if (_disposed) return;
    _lastPresentation = _presentationState;
    _lastState = _stateFor(_lastPresentation!);
    _presentationChanges.notifyListeners();
    notifyListeners();
  }

  Future<void> prepare() {
    if (_disposed) return Future.error(StateError('Playback session closed'));
    if (_prepared) return Future.value();
    return _preparing ??= _prepare().whenComplete(() => _preparing = null);
  }

  Future<void> _prepare() async {
    MediaKit.ensureInitialized();
    await preferences.load();
    await shaders.prepare();
    if (_disposed) return;
    _prepared = true;
    _poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      refreshState();
    });
  }

  /// 同步原生状态；独立入口供确定性测试复现 200ms 轮询。
  @visibleForTesting
  void refreshState() {
    if (_disposed) return;
    core.syncPlaybackState();
    final presentation = _presentationState;
    final state = _stateFor(presentation);
    if (state == _lastState) return;
    _lastState = state;
    // 进度/缓冲只更新媒体控件；页面业务树仅随媒体、错误、时长等结构状态变化。
    // https://docs.flutter.dev/perf/best-practices#control-build-cost
    if (presentation != _lastPresentation) {
      _lastPresentation = presentation;
      _presentationChanges.notifyListeners();
    }
    notifyListeners();
  }

  Future<void> load(
    PlaybackSource target, {
    bool play = false,
    bool synchronized = false,
  }) {
    if (remoteCommand != null && !synchronized) {
      return remoteCommand!('media', {'media': target.toRoomMedia()});
    }
    final generation = ++_generation;
    source = target;
    loading = true;
    error = null;
    notice = null;
    seeking.invalidateInteractiveSeek();
    _changed();
    return _operations.run(() async {
      if (_disposed || generation != _generation) return;
      try {
        await prepare();
        if (_disposed || generation != _generation) return;
        await _errors?.cancel();
        await core.stop();
        _openingSource = target;
        core.resetForInit();
        bool current() => !_disposed && generation == _generation;
        core.onMediaError = (message) {
          if (current()) {
            // mpv 探测硬解失败后仍可能回落软解，不能把这条诊断当成媒体终止。
            if (message.trim() == 'Could not open codec.') return;
            error = '视频加载或解码失败，请检查媒体地址、格式和网络。';
            _changed();
          }
        };
        final player = await core
            .createVideoController(
              target.headers,
              false,
              canInstall: current,
              videoSourceFormat: target.isHls
                  ? VideoSourceFormat.hls
                  : VideoSourceFormat.auto,
            )
            .timeout(const Duration(seconds: 30));
        if (!current() || player == null) return;
        _errors = player.stream.error.listen((message) {
          if (current()) {
            if (message.trim() == 'Could not open codec.') return;
            error = '媒体播放失败，请重试或更换来源。';
            _changed();
          }
        });
        await player.setRate(
          preferences.getSetting<double>(SettingsKeys.defaultPlaySpeed),
        );
        if (play && current()) await player.play();
        core.loading = false;
      } catch (_) {
        if (!_disposed && generation == _generation) {
          error = '无法打开视频，请检查地址、请求头或解码设置后重试。';
          await core.stop();
        }
      } finally {
        if (!_disposed && generation == _generation) {
          loading = false;
          _changed();
        }
      }
    });
  }

  Future<void> _control(Future<void> Function(Player player) action) {
    final generation = _generation;
    return _operations.run(() async {
      final player = core.mediaPlayer;
      if (_disposed || player == null || generation != _generation) return;
      try {
        await action(player);
      } catch (_) {
        if (!_disposed) notice = '播放器操作失败，请重试。';
      }
      core.syncPlaybackState();
      _changed();
    });
  }

  Future<void> play() =>
      remoteCommand?.call('play', {}) ?? _control((player) => player.play());
  Future<void> pause() =>
      remoteCommand?.call('pause', {}) ?? _control((player) => player.pause());
  Future<void> toggle() => core.playerPlaying ? pause() : play();
  Future<void> seek(Duration position) =>
      remoteCommand?.call('seek', {'positionMs': position.inMilliseconds}) ??
      _control(
        (player) => player.seek(
          Duration(
            milliseconds: position.inMilliseconds.clamp(
              0,
              core.playerDuration.inMilliseconds,
            ),
          ),
        ),
      );
  Future<void> setRate(double rate, {bool persist = true}) async {
    if (!rate.isFinite || rate < 0.25 || rate > 8)
      throw ArgumentError('Invalid playback rate');
    if (remoteCommand != null) {
      await remoteCommand!('rate', {'rate': rate});
      return;
    }
    final generation = _generation;
    await _control((player) => player.setRate(rate));
    if (_disposed || generation != _generation) return;
    core.playerSpeed = rate;
    if (persist)
      await preferences.putSetting(SettingsKeys.defaultPlaySpeed, rate);
  }

  Future<void> applyTarget({
    required Duration position,
    required bool playing,
    required double rate,
    bool forceSeek = false,
  }) => _control((player) async {
    await player.setRate(rate);
    // Playra 的轮询不回写 playerSpeed；远端目标必须同时更新显示与长按恢复的基准。
    core.playerSpeed = rate;
    if (forceSeek ||
        (player.state.position - position).abs() >
            const Duration(milliseconds: 1200))
      await player.seek(position);
    if (playing) {
      await player.play();
    } else {
      await player.pause();
    }
  });
  Future<void> capture() async {
    final player = core.mediaPlayer;
    final generation = _generation;
    final current = source;
    if (current == null || player == null || loading) return;
    await screenshots.capture(
      capturePng: core.screenshotPng,
      title: current.title,
      episode: '',
      position: core.playerPosition,
      isCurrent: () =>
          !_disposed &&
          generation == _generation &&
          identical(core.mediaPlayer, player),
    );
    _changed();
  }

  void setSleep(Duration? remaining) {
    _sleep?.cancel();
    sleepAt = remaining == null ? null : DateTime.now().add(remaining);
    if (remaining != null)
      _sleep = Timer(remaining, () {
        sleepAt = null;
        unawaited(pause());
        _changed();
      });
    _changed();
  }

  Future<void> setPlaylist(List<PlaybackSource> items, {int index = 0}) async {
    if (items.isEmpty || index < 0 || index >= items.length)
      throw ArgumentError('Invalid playlist');
    playlist = List.unmodifiable(items);
    playlistIndex = index;
    await load(items[index]);
  }

  Future<void> next() async {
    if (playlistIndex + 1 >= playlist.length) return;
    await load(playlist[++playlistIndex]);
  }

  Future<void> close() => _closing ??= () async {
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    _sleep?.cancel();
    _presentationChanges.dispose();
    seeking.invalidateInteractiveSeek();
    await _errors?.cancel();
    await _operations.run(core.stop);
    try {
      await _preparing;
    } catch (_) {
      // 初始化失败也要释放设置订阅，不能让退出页面留下悬空异常。
    }
    screenshots.dispose();
    await preferences.dispose();
  }();
  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
