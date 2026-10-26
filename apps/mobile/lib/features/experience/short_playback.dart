import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../playback/player_page.dart';
import '../catalog/media_provider.dart';

/// 短剧信息流选线：多集正片优先；正片只有单集时保住多集线路（连播优先于
/// 线路口味），最后才落回单集正片、单集「备用」。
MediaLine? preferredShortLine(Iterable<MediaLine> lines) {
  MediaLine? pick(bool Function(MediaLine line) test) =>
      lines.where(test).firstOrNull;
  bool main(MediaLine line) => !isBackupLineName(line.name);
  return pick((line) => main(line) && line.episodes.length > 1) ??
      pick((line) => line.episodes.length > 1) ??
      pick((line) => main(line) && line.episodes.isNotEmpty) ??
      pick((line) => line.episodes.isNotEmpty);
}

class ShortVideoSurface extends StatelessWidget {
  const ShortVideoSurface({
    super.key,
    required this.player,
    required this.onRetry,
    this.onDoubleTap,
  });
  final PlayerPresentation player;
  final VoidCallback onRetry;

  /// 双击画面收藏（短视频习惯）。为空时不注册双击，单击仍立即生效。
  final VoidCallback? onDoubleTap;

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
          // 不注册纵向拖动，切剧手势只交给外层 PageView。
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
                // 有双击收藏时，单击会等到双击窗口结束才执行：这是
                // GestureDetector 的固有行为，换来的是同一点按区域支持收藏。
                onDoubleTap: onDoubleTap,
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

/// TikTok 式贴底进度线：常态 2px 细线，拖动时加粗并浮出时间气泡；
/// seek 锁定发起时的会话代，切剧换代后松手不会落到新源上。
class ShortScrubLine extends StatefulWidget {
  const ShortScrubLine({super.key, required this.player});
  final PlayerPresentation player;
  @override
  State<ShortScrubLine> createState() => _ShortScrubLineState();
}

class _ShortScrubLineState extends State<ShortScrubLine> {
  double? drag; // 拖动目标位置（毫秒），松手或换代后清空。
  int? seekGeneration;
  // 进度走会话的轻量 ValueNotifier 通道：200ms 一拍只重建这根 2px 细线，
  // 外层再包 RepaintBoundary，把失效区域钉在本层，不牵连整页 raster。
  ValueListenable<Duration>? _positionListen;

  static String time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final listen = widget.player.session.positionTick;
    if (!identical(_positionListen, listen)) {
      _positionListen = listen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.player.session;
    final core = session.core;
    final total = core.playerDuration.inMilliseconds;
    final ready =
        total > 0 &&
        !session.loading &&
        session.error == null &&
        widget.player.error == null;
    if (seekGeneration != session.generation) drag = null;
    final scrubbing = drag != null;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double valueAt(double dx) => width <= 0 || total <= 0
              ? 0.0
              : (dx.clamp(0.0, width) / width) * total;

          void startAt(Offset local) {
            seekGeneration = session.generation;
            setState(() => drag = valueAt(local.dx));
          }

          void end() {
            final value = drag;
            final valid = seekGeneration == session.generation;
            setState(() => drag = null);
            if (value != null && valid)
              unawaited(session.seek(Duration(milliseconds: value.round())));
          }

          // 常态：进度线订阅轻通道局部重绘，手势层常驻，不依赖任何整页重建。
          final line = ValueListenableBuilder<Duration>(
            valueListenable: _positionListen ?? session.positionTick,
            builder: (context, value, _) {
              final position =
                  (scrubbing ? Duration(milliseconds: drag!.round()) : value)
                      .inMilliseconds
                      .clamp(0, total > 0 ? total : 0);
              final played = position.toDouble().clamp(
                0.0,
                total > 0 ? total.toDouble() : 0.0,
              );
              final fraction = total > 0 ? played / total : 0.0;
              final clock = '${time(played ~/ 1000)} / ${time(total ~/ 1000)}';
              return Semantics(
                label: ready ? '播放进度 $clock' : '正在准备',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: ready
                      ? (details) => startAt(details.localPosition)
                      : null,
                  onTapUp: ready ? (_) => end() : null,
                  onTapCancel: ready ? () => setState(() => drag = null) : null,
                  onHorizontalDragStart: ready
                      ? (details) => startAt(details.localPosition)
                      : null,
                  onHorizontalDragUpdate: ready
                      ? (details) => setState(
                          () => drag = valueAt(details.localPosition.dx),
                        )
                      : null,
                  onHorizontalDragEnd: ready ? (_) => end() : null,
                  onHorizontalDragCancel: ready
                      ? () => setState(() => drag = null)
                      : null,
                  child: CustomPaint(
                    // 32px 命中高：视觉仍是 2px 细线，但手指不必贴着 2px 找。
                    size: const Size(double.infinity, 32),
                    painter: _HairlinePainter(
                      fraction: fraction,
                      active: scrubbing,
                    ),
                  ),
                ),
              );
            },
          );
          if (!scrubbing) return line;
          // 拖动时在线上方浮出时间气泡，跟随拇指并收在两端之内。
          final played = (drag ?? 0.0).clamp(
            0.0,
            total > 0 ? total.toDouble() : 0.0,
          );
          final fraction = total > 0 ? played / total : 0.0;
          final clock = '${time(played ~/ 1000)} / ${time(total ~/ 1000)}';
          return Stack(
            clipBehavior: Clip.none,
            children: [
              line,
              Positioned(
                left: (fraction * (width - 88)).clamp(
                  0.0,
                  width < 88 ? 0.0 : width - 88,
                ),
                bottom: 26,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    clock,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 贴底细线：常态 2px，拖动加粗到 4px 并显示拇指；无缓冲轨道，保持 TikTok 的静默观感。
class _HairlinePainter extends CustomPainter {
  const _HairlinePainter({required this.fraction, required this.active});
  final double fraction;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = active ? 4.0 : 2.0;
    final radius = Radius.circular(thickness / 2);
    final top = size.height / 2 - thickness / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width, thickness),
        radius,
      ),
      Paint()..color = const Color(0x4DFFFFFF),
    );
    final playedWidth = size.width * fraction.clamp(0.0, 1.0);
    if (playedWidth > 1)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, playedWidth, thickness),
          radius,
        ),
        Paint()..color = Colors.white,
      );
    if (active && playedWidth > 0)
      canvas.drawCircle(
        Offset(playedWidth, size.height / 2),
        5,
        Paint()..color = Colors.white,
      );
  }

  @override
  bool shouldRepaint(_HairlinePainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.active != active;
}
