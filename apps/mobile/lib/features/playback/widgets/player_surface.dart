import 'dart:async';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import '../../../design/tokens.dart';

import '../playback_session.dart';
import '../playra/player_support.dart';
import '../playra/widgets/player_transport_bar.dart';
import '../playra/widgets/player_gesture_detector.dart';
import '../playra/widgets/player_adjustment_hud.dart';
import '../playra/widgets/player_buffering_overlay.dart';
import '../playra/widgets/player_screenshot_controls.dart';

/// 保留 Playra 的视频/控件/HUD 叠层；业务导航通过回调传入。
class PlayerSurface extends StatefulWidget {
  const PlayerSurface({
    super.key,
    required this.session,
    required this.fullscreen,
    required this.onFullscreen,
    required this.onBack,
    required this.onSettings,
    required this.onScreenshots,
    required this.onPip,
    required this.onToggle,
    required this.onSeek,
    required this.onRate,
    this.pictureInPicture = false,
    this.title,
    this.subtitle,
    this.onMore,
  });
  final PlaybackSession session;
  final bool fullscreen;
  final bool pictureInPicture;
  final String? title;
  final String? subtitle;
  final VoidCallback? onMore;
  final VoidCallback onFullscreen;
  final VoidCallback onBack;
  final Future<void> Function() onSettings;
  final Future<void> Function() onScreenshots;
  final Future<void> Function() onPip;
  final Future<void> Function() onToggle;
  final Future<void> Function(Duration) onSeek;
  final Future<void> Function(double) onRate;
  @override
  State<PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<PlayerSurface> {
  PlaybackSession get s => widget.session;
  Timer? _hide;
  Timer? _hud;
  bool _visible = true;
  bool _locked = false;
  bool _menu = false;
  bool _dragging = false;
  Duration _preview = Duration.zero;
  Duration _dragStart = Duration.zero;
  bool _cancelSeek = false;
  int? _seekGeneration;
  int? _boostGeneration;
  double _brightness = .5;
  double _volume = 50;
  PlayerAdjustmentHudType? _adjustment;
  double? _boost;
  bool _boostShown = false;
  @override
  void initState() {
    super.initState();
    _reveal();
    unawaited(_deviceValues());
  }

  Future<void> _deviceValues() async {
    try {
      final volume = await FlutterVolumeController.getVolume();
      final brightness = await ScreenBrightnessPlatform.instance.application;
      if (mounted)
        setState(() {
          _volume = (volume ?? .5) * 100;
          _brightness = brightness;
        });
    } on PlatformException {
      /* 手势首次操作仍可显式设置设备值。 */
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _hud?.cancel();
    super.dispose();
  }

  void _reveal() {
    _hide?.cancel();
    if (mounted) setState(() => _visible = true);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && !_menu && !_dragging) setState(() => _visible = false);
    });
  }

  Future<void> _hold(Future<void> Function() action) async {
    _menu = true;
    _hide?.cancel();
    try {
      await action();
    } finally {
      _menu = false;
      if (mounted) _reveal();
    }
  }

  void _startSeek() {
    _seekGeneration = s.generation;
    _hide?.cancel();
    setState(() {
      _dragging = true;
      _cancelSeek = false;
      _dragStart = s.core.playerPosition;
      _preview = _dragStart;
    });
  }

  Future<void> _endSeek(bool cancel) async {
    if (!_dragging) return;
    final target = _preview;
    setState(() => _dragging = false);
    if (!cancel &&
        !_cancelSeek &&
        _seekGeneration == s.generation &&
        !s.loading) {
      await widget.onSeek(target);
    }
    _seekGeneration = null;
    if (mounted) _reveal();
  }

  void _previewSeek(Duration target) {
    final total = s.core.playerDuration.inMilliseconds;
    setState(
      () => _preview = Duration(
        milliseconds: target.inMilliseconds.clamp(0, total),
      ),
    );
  }

  Future<void> _vertical(DragUpdateDetails details, double width) async {
    if (_locked) return;
    final left = details.localPosition.dx < width / 2;
    final delta = -(details.primaryDelta ?? 0) / 250;
    try {
      if (left) {
        _brightness = (_brightness + delta).clamp(0, 1);
        await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
          _brightness,
        );
      } else {
        _volume = (_volume + delta * 100).clamp(0, 100);
        await s.core.setVolume(_volume);
      }
      if (!mounted) return;
      setState(
        () => _adjustment = left
            ? PlayerAdjustmentHudType.brightness
            : PlayerAdjustmentHudType.volume,
      );
      _hud?.cancel();
      _hud = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _adjustment = null);
      });
    } on PlatformException {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('此设备暂不支持调整亮度或音量。')));
    }
  }

  IconButton _icon(String label, IconData icon, VoidCallback? action) =>
      IconButton(
        tooltip: label,
        onPressed: action,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
        ),
      );

  Widget _fade(bool visible, Widget child) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: DSMotion.duration(context, DSMotion.fast),
        curve: DSMotion.curve,
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([s, s.stateTick]),
    builder: (context, _) {
      final core = s.core;
      final controller = core.videoController;
      final enabled = controller != null && !s.loading;
      final show = _visible && !widget.pictureInPicture;
      final ratio = s.panel.aspectRatioMode;
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 580;
          final picture = controller == null
              ? const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      size: 64,
                      color: Colors.white38,
                    ),
                  ),
                )
              : Video(
                  key: ValueKey(controller),
                  controller: controller,
                  controls: null,
                  pauseUponEnteringBackgroundMode: false,
                  fit: ratio.fit,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      backgroundColor: Colors.black54,
                    ),
                    padding: EdgeInsets.all(16),
                  ),
                );
          return ColoredBox(
            color: Colors.black,
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent || _locked || !enabled)
                  return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.space) {
                  unawaited(widget.onToggle());
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight ||
                    key == LogicalKeyboardKey.arrowLeft) {
                  unawaited(
                    widget.onSeek(
                      core.playerPosition +
                          Duration(
                            seconds: key == LogicalKeyboardKey.arrowRight
                                ? 10
                                : -10,
                          ),
                    ),
                  );
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.escape && widget.fullscreen) {
                  widget.onFullscreen();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ratio.frameAspectRatio case final double aspect)
                    Center(
                      child: AspectRatio(aspectRatio: aspect, child: picture),
                    )
                  else
                    picture,
                  if (!widget.pictureInPicture)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_visible) {
                          setState(() => _visible = false);
                        } else {
                          _reveal();
                        }
                      },
                      onDoubleTap: enabled && !_locked
                          ? () {
                              unawaited(widget.onToggle());
                              _reveal();
                            }
                          : null,
                      onLongPressStart: enabled && !_locked
                          ? (_) {
                              _boost = core.playerSpeed;
                              _boostGeneration = s.generation;
                              setState(() => _boostShown = true);
                              unawaited(s.setRate(2, persist: false));
                            }
                          : null,
                      onLongPressEnd: (_) {
                        final original = _boost;
                        _boost = null;
                        setState(() => _boostShown = false);
                        if (original != null &&
                            _boostGeneration == s.generation &&
                            !s.loading)
                          unawaited(s.setRate(original, persist: false));
                      },
                      onLongPressCancel: () {
                        final original = _boost;
                        _boost = null;
                        setState(() => _boostShown = false);
                        if (original != null &&
                            _boostGeneration == s.generation &&
                            !s.loading)
                          unawaited(s.setRate(original, persist: false));
                      },
                      child: enabled && !_locked
                          ? PlayerGestureDetector(
                              onSeekStart: _startSeek,
                              onSeekUpdate: (delta, cancel) {
                                _cancelSeek = cancel;
                                _previewSeek(
                                  _preview +
                                      Duration(
                                        milliseconds:
                                            (delta /
                                                    constraints.maxWidth *
                                                    core
                                                        .playerDuration
                                                        .inMilliseconds)
                                                .round(),
                                      ),
                                );
                              },
                              onSeekEnd: (cancel) =>
                                  unawaited(_endSeek(cancel)),
                              onVerticalDragUpdate: (details) => unawaited(
                                _vertical(details, constraints.maxWidth),
                              ),
                            )
                          : const SizedBox.expand(),
                    ),
                  if (s.loading || (enabled && core.playerBuffering))
                    PlayerBufferingOverlay(
                      player: core.mediaPlayer,
                      buffering: core.playerBuffering,
                      resolving: s.loading,
                    ),
                  if (s.error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                            TextButton(
                              onPressed: s.source == null
                                  ? null
                                  : () => unawaited(s.load(s.source!)),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_locked)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _fade(
                        show,
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xCC000000),
                                Color(0x66000000),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: SafeArea(
                            top: widget.fullscreen,
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                children: [
                                  _icon(
                                    '返回',
                                    Icons.arrow_back_ios_new_rounded,
                                    widget.onBack,
                                  ),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (s.source?.title != null &&
                                                  s.source!.title.isNotEmpty)
                                              ? s.source!.title
                                              : (widget.title ??
                                                  'Duoscene 播放器'),
                                          key: const Key('watch-header-title'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            shadows: [
                                              Shadow(
                                                offset: Offset(0, 1),
                                                blurRadius: 3,
                                                color: Colors.black54,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (widget.subtitle != null &&
                                            widget.subtitle!.isNotEmpty) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            widget.subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.8),
                                              fontSize: 11,
                                              shadows: const [
                                                Shadow(
                                                  offset: Offset(0, 1),
                                                  blurRadius: 3,
                                                  color: Colors.black54,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (!compact)
                                    PlayerScreenshotControls(
                                      controller: s.screenshots,
                                      onCapture: () => unawaited(s.capture()),
                                      onReview: () => unawaited(
                                        _hold(widget.onScreenshots),
                                      ),
                                    ),
                                  if (widget.onMore != null)
                                    _icon(
                                      '播放器更多功能',
                                      Icons.more_horiz_rounded,
                                      widget.onMore!,
                                    )
                                  else
                                    _icon(
                                      '播放设置',
                                      Icons.tune_rounded,
                                      () => unawaited(_hold(widget.onSettings)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (enabled && !_locked && !core.playerBuffering)
                    Center(
                      child: _fade(
                        show,
                        IconButton.filled(
                          tooltip: core.playerPlaying ? '暂停' : '播放',
                          onPressed: () => unawaited(widget.onToggle()),
                          iconSize: compact ? 36 : 48,
                          style: IconButton.styleFrom(
                            backgroundColor: DSPalette.of(context).primary
                                .withValues(alpha: .8),
                            foregroundColor: DSPalette.of(context).bg,
                            minimumSize: const Size(56, 56),
                          ),
                          icon: Icon(
                            core.playerPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ),
                    ),
                  if (show)
                    Positioned(
                      left: 0,
                      top: constraints.maxHeight / 2 - 24,
                      child: _icon(
                        _locked ? '解锁控件' : '锁定控件',
                        _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        () {
                          setState(() => _locked = !_locked);
                          _reveal();
                        },
                      ),
                    ),
                  if (!_locked)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _fade(
                        show,
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: PlayerTransportBar(
                                compact: compact,
                                playPause: _icon(
                                  core.playerPlaying ? '暂停' : '播放',
                                  core.playerPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  enabled
                                      ? () => unawaited(widget.onToggle())
                                      : null,
                                ),
                                nextEpisode: _icon(
                                  '下一项',
                                  Icons.skip_next_rounded,
                                  s.playlistIndex + 1 < s.playlist.length
                                      ? () => unawaited(s.next())
                                      : null,
                                ),
                                progressBuilder: (placement) => _LiveProgress(
                                  session: s,
                                  dragging: _dragging,
                                  preview: _preview,
                                  placement: placement,
                                  enabled: enabled,
                                  onDragStart: enabled ? (_) => _startSeek() : null,
                                  onDragUpdate: (details) =>
                                      _previewSeek(details.timeStamp),
                                  onDragEnd: _reveal,
                                  onSeek: enabled
                                      ? (target) {
                                          if (_dragging) {
                                            _previewSeek(target);
                                            unawaited(_endSeek(false));
                                          } else {
                                            unawaited(widget.onSeek(target));
                                          }
                                        }
                                      : null,
                                ),
                                timeLabel: _LiveTimeLabel(
                                  session: s,
                                  dragging: _dragging,
                                  preview: _preview,
                                ),
                                timePlacement:
                                    PlayerTimeLabelPlacement.forViewport(
                                      Size(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      ),
                                      desktop: false,
                                    ),
                                controls: Row(
                                  children: [
                                    TextButton(
                                      onPressed: enabled
                                          ? () => unawaited(
                                              _hold(() => _rateMenu(context)),
                                            )
                                          : null,
                                      child: Text(
                                        '${core.playerSpeed.toStringAsFixed(2)}×',
                                      ),
                                    ),
                                    _icon(
                                      '画中画',
                                      Icons.picture_in_picture_alt_rounded,
                                      enabled
                                          ? () => unawaited(widget.onPip())
                                          : null,
                                    ),
                                    _icon(
                                      '跳过片头',
                                      Icons.fast_forward_rounded,
                                      enabled
                                          ? () => unawaited(
                                              widget.onSeek(
                                                core.playerPosition +
                                                    Duration(
                                                      seconds: s.preferences
                                                          .getSetting<int>(
                                                            SettingsKeys
                                                                .skipSeconds,
                                                          ),
                                                    ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                                fullscreen: _icon(
                                  widget.fullscreen ? '退出全屏' : '全屏',
                                  widget.fullscreen
                                      ? Icons.fullscreen_exit_rounded
                                      : Icons.fullscreen_rounded,
                                  widget.onFullscreen,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_dragging)
                    Center(
                      child: PlayerSeekHud(
                        visible: true,
                        currentPosition: _preview,
                        playerPosition: _dragStart,
                        duration: core.playerDuration,
                        direction: _preview >= _dragStart ? 1 : -1,
                        cancelPending: _cancelSeek,
                      ),
                    ),
                  if (_adjustment case final PlayerAdjustmentHudType type)
                    Center(
                      child: PlayerAdjustmentHud(
                        visible: true,
                        type: type,
                        value: type == PlayerAdjustmentHudType.brightness
                            ? _brightness
                            : _volume,
                      ),
                    ),
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: PlayerSpeedHud(visible: _boostShown, speed: 2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  Future<void> _rateMenu(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          for (final rate in [
            .25,
            .5,
            .75,
            1.0,
            1.25,
            1.5,
            1.75,
            2.0,
            3.0,
            4.0,
            8.0,
          ])
            ListTile(
              title: Text('$rate×'),
              selected: s.core.playerSpeed == rate,
              onTap: () {
                Navigator.pop(context);
                unawaited(widget.onRate(rate));
              },
            ),
        ],
      ),
    ),
  );
}

/// 进度条只订阅会话的轻量 position/buffer 通道：200ms 一拍仅重建进度条本体
/// （外层 RepaintBoundary 钉住重绘范围），不再随整页状态走。
class _LiveProgress extends StatelessWidget {
  const _LiveProgress({
    required this.session,
    required this.dragging,
    required this.preview,
    required this.placement,
    required this.enabled,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onSeek,
  });
  final PlaybackSession session;
  final bool dragging;
  final Duration preview;
  final TimeLabelLocation placement;
  final bool enabled;
  final ValueChanged<ThumbDragDetails>? onDragStart;
  final ValueChanged<ThumbDragDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: session.positionTick,
        builder: (context, position, _) => ValueListenableBuilder<Duration>(
          valueListenable: session.bufferTick,
          builder: (context, buffer, __) {
            final core = session.core;
            return ProgressBar(
              progress: dragging ? preview : position,
              buffered: dragging ? core.playerBuffer : buffer,
              total: core.playerDuration,
              barHeight: 3,
              thumbRadius: 6,
              timeLabelLocation: placement,
              timeLabelTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
              progressBarColor: DSPalette.of(context).primary,
              thumbColor: DSPalette.of(context).primary,
              baseBarColor: Colors.white24,
              bufferedBarColor: Colors.white38,
              onDragStart: onDragStart,
              onDragUpdate: onDragUpdate,
              onDragEnd: onDragEnd,
              onSeek: onSeek,
            );
          },
        ),
      ),
    );
  }
}

/// 时间标签与进度条同通道：拖动中显示预览值。
class _LiveTimeLabel extends StatelessWidget {
  const _LiveTimeLabel({
    required this.session,
    required this.dragging,
    required this.preview,
  });
  final PlaybackSession session;
  final bool dragging;
  final Duration preview;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: session.positionTick,
        builder: (context, position, _) {
          final core = session.core;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${durationToString(dragging ? preview : position)} / ${durationToString(core.playerDuration)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          );
        },
      ),
    );
  }
}
