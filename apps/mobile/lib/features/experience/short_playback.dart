import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../playback/player_page.dart';
import '../catalog/media_provider.dart';

MediaLine? preferredShortLine(Iterable<MediaLine> lines) =>
    lines.where((line) => line.episodes.length > 1).firstOrNull ??
    lines
        .where((line) => line.direct && line.episodes.isNotEmpty)
        .firstOrNull ??
    lines.where((line) => line.episodes.isNotEmpty).firstOrNull;

class ShortVideoSurface extends StatelessWidget {
  const ShortVideoSurface({
    super.key,
    required this.player,
    required this.onRetry,
  });
  final PlayerPresentation player;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final session = player.session;
    final core = session.core;
    final controller = core.videoController;
    final error = player.error ?? session.error;
    final busy = session.loading || core.playerBuffering;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            Video(
              controller: controller,
              controls: null,
              fit: BoxFit.contain,
              pauseUponEnteringBackgroundMode: false,
            ),
          // 不注册纵向拖动，切集手势只交给外层 PageView。
          Positioned.fill(
            child: Semantics(
              button: true,
              label: core.playerPlaying ? '暂停短剧' : '播放短剧',
              child: GestureDetector(
                key: const Key('short-playback-toggle'),
                behavior: HitTestBehavior.opaque,
                onTap: error != null || busy
                    ? null
                    : () => unawaited(player.toggle()),
                child: Center(
                  child: error != null
                      ? TextButton(
                          onPressed: onRetry,
                          child: const Text(
                            '播放失败，点击重试',
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      : busy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : core.playerPlaying
                      ? const SizedBox.shrink()
                      : const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white70,
                          size: 64,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShortPlaybackControls extends StatefulWidget {
  const ShortPlaybackControls({super.key, required this.player});
  final PlayerPresentation player;
  @override
  State<ShortPlaybackControls> createState() => _ShortPlaybackControlsState();
}

class _ShortPlaybackControlsState extends State<ShortPlaybackControls> {
  double? preview;
  int? seekGeneration;
  static String time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.player.session,
    builder: (context, _) => controls(context),
  );

  Widget controls(BuildContext context) {
    final session = widget.player.session;
    final core = session.core;
    final total = core.playerDuration.inMilliseconds;
    final ready =
        total > 0 &&
        !session.loading &&
        session.error == null &&
        widget.player.error == null;
    if (seekGeneration != session.generation) preview = null;
    final progress = (preview ?? core.playerPosition.inMilliseconds.toDouble())
        .clamp(0.0, total > 0 ? total.toDouble() : 1.0);
    final toggle = IconButton(
      key: const Key('short-transport-toggle'),
      tooltip: core.playerPlaying ? '暂停' : '播放',
      onPressed: ready ? () => unawaited(widget.player.toggle()) : null,
      icon: Icon(
        core.playerPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: Colors.white,
      ),
    );
    final timeline = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),
      child: Slider(
        key: const Key('short-seek'),
        label: ready
            ? '${time(progress ~/ 1000)} / ${time(total ~/ 1000)}'
            : '正在准备',
        activeColor: Colors.white,
        inactiveColor: Colors.white30,
        min: 0,
        max: total > 0 ? total.toDouble() : 1,
        value: progress,
        onChangeStart: ready
            ? (_) => seekGeneration = session.generation
            : null,
        onChanged: ready ? (value) => setState(() => preview = value) : null,
        onChangeEnd: ready
            ? (value) {
                final valid = seekGeneration == session.generation;
                setState(() => preview = null);
                if (valid)
                  unawaited(
                    session.seek(Duration(milliseconds: value.round())),
                  );
              }
            : null,
      ),
    );
    final timestamp = Text(
      ready ? '${time(progress ~/ 1000)} / ${time(total ~/ 1000)}' : '准备中',
      style: const TextStyle(fontSize: 11, color: Colors.white70),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 240 ||
            MediaQuery.textScalerOf(context).scale(11) > 16) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  toggle,
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: timestamp,
                    ),
                  ),
                ],
              ),
              timeline,
            ],
          );
        }
        return Row(
          children: [
            toggle,
            Expanded(child: timeline),
            timestamp,
          ],
        );
      },
    );
  }
}
