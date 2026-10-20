import 'package:flutter/material.dart';

import 'tokens.dart';

/// 只重绘顶部，滚动期间不重建列表或播放器。透明度直接跟随距离，回拉不跳变。
class ScrollChrome extends StatefulWidget {
  const ScrollChrome({
    super.key,
    required this.header,
    required this.child,
    this.fadeStart = 0,
    this.fadeExtent = 72,
  });
  final Widget header, child;
  final double fadeStart, fadeExtent;
  @override
  State<ScrollChrome> createState() => _ScrollChromeState();
}

class _ScrollChromeState extends State<ScrollChrome> {
  final progress = ValueNotifier(0.0);
  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
            // 短列表也应在滚动到底前完成渐变，避免可滚动距离小于默认阈值。
            final available = n.metrics.maxScrollExtent - widget.fadeStart;
            final extent = available > 0
                ? available.clamp(1.0, widget.fadeExtent)
                : widget.fadeExtent;
            progress.value = ((n.metrics.pixels - widget.fadeStart) / extent)
                .clamp(0, 1);
          }
          return false;
        },
        child: Stack(
          children: [
            Positioned.fill(child: widget.child),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: progress,
                child: widget.header,
                builder: (context, value, child) => DecoratedBox(
                  key: const Key('scroll-chrome'),
                  decoration: BoxDecoration(
                    color: DSPalette.of(context).bg
                        .withValues(alpha: value * .98),
                    border: Border(
                      bottom: BorderSide(
                        color: DSPalette.of(context).line
                            .withValues(alpha: value * .6),
                        width: .5,
                      ),
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
}
