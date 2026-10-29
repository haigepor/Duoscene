import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 只重排固定槽位：横竖屏和键盘变化不会重新挂载视频、聊天或输入控制器。
class AdaptiveWatchLayout extends StatelessWidget {
  const AdaptiveWatchLayout({
    super.key,
    required this.header,
    required this.media,
    required this.controls,
    required this.conversation,
    required this.showMedia,
  });
  final Widget header, media, controls, conversation;
  final bool showMedia;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => CustomMultiChildLayout(
      delegate: _WatchLayout(
        split: showMedia && bounds.maxWidth >= 1100 && bounds.maxHeight >= 600,
        showMedia: showMedia,
        conversationMinimum:
            160 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6),
      ),
      children: [
        LayoutId(id: _Slot.header, child: header),
        LayoutId(
          id: _Slot.media,
          child: Visibility(
            visible: showMedia,
            maintainState: true,
            child: media,
          ),
        ),
        LayoutId(id: _Slot.controls, child: controls),
        LayoutId(id: _Slot.conversation, child: conversation),
      ],
    ),
  );
}

enum _Slot { header, media, controls, conversation }

class _WatchLayout extends MultiChildLayoutDelegate {
  _WatchLayout({
    required this.split,
    required this.showMedia,
    required this.conversationMinimum,
  });
  final bool split, showMedia;
  final double conversationMinimum;

  @override
  void performLayout(Size size) {
    // 顶栏/控制条按自然高度布局，避免其中的 Column 扩张占满整个窗口。
    final header = layoutChild(
      _Slot.header,
      BoxConstraints(maxWidth: size.width),
    );
    positionChild(_Slot.header, Offset.zero);
    final bodyHeight = math.max(0.0, size.height - header.height);
    final panelWidth = split ? 360.0 : size.width;
    final videoWidth = split ? size.width - panelWidth - 24 : size.width;
    final controls = layoutChild(
      _Slot.controls,
      BoxConstraints(maxWidth: videoWidth),
    );
    var videoHeight = showMedia
        ? math.min(
            math.max(0.0, (videoWidth - 32) * 9 / 16),
            split
                ? math.max(0.0, bodyHeight - controls.height)
                : math.min(
                    size.height * .4,
                    math.max(
                      0.0,
                      bodyHeight - controls.height - conversationMinimum,
                    ),
                  ),
          )
        : 0.0;
    // 低高度/大字体优先给交流和输入区留空间，不保留几像素高的视频条。
    if (!split && videoHeight < 80) videoHeight = 0;
    layoutChild(
      _Slot.media,
      BoxConstraints.tight(Size(videoWidth, videoHeight)),
    );
    positionChild(_Slot.media, Offset(0, header.height));
    positionChild(_Slot.controls, Offset(0, header.height + videoHeight));
    layoutChild(
      _Slot.conversation,
      BoxConstraints.tight(
        Size(
          panelWidth,
          split
              ? bodyHeight
              : math.max(0.0, bodyHeight - videoHeight - controls.height),
        ),
      ),
    );
    positionChild(
      _Slot.conversation,
      split
          ? Offset(videoWidth + 24, header.height)
          : Offset(0, header.height + videoHeight + controls.height),
    );
  }

  @override
  bool shouldRelayout(_WatchLayout oldDelegate) =>
      split != oldDelegate.split ||
      showMedia != oldDelegate.showMedia ||
      conversationMinimum != oldDelegate.conversationMinimum;
}
