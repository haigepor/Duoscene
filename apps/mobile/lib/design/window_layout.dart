import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 窗口决定导航形态，局部约束决定内容尺寸；分屏时沿用同一份业务状态。
abstract final class WindowLayout {
  static const railBreakpoint = 600.0;
  static const railWidth = 80.0;
  static const browseWidth = 1200.0;
  static const readingWidth = 720.0;
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= railBreakpoint;

  static int posterColumns(double width, TextScaler text) {
    final target = 144 * text.scale(1).clamp(1, 1.4);
    return ((width + 16) / (target + 16)).round().clamp(2, 10);
  }

  static double shelfWidth(BuildContext context, {double compact = 108}) =>
      isWide(context) ? 144 : compact;
}

/// 约束变化只更新尺寸，不通过窄/宽两套子树重建页面和控制器。
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = WindowLayout.browseWidth,
    this.wideInset = 8,
  });
  final Widget child;
  final double maxWidth, wideInset;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: WindowLayout.isWide(context) ? maxWidth : double.infinity,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: WindowLayout.isWide(context) ? wideInset : 0,
        ),
        child: child,
      ),
    ),
  );
}

class PortraitMediaFrame extends StatelessWidget {
  const PortraitMediaFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Align(
      child: SizedBox(
        key: const Key('short-portrait-stage'),
        width: WindowLayout.isWide(context)
            ? math.min(bounds.maxWidth, bounds.maxHeight * 9 / 16)
            : bounds.maxWidth,
        height: bounds.maxHeight,
        child: child,
      ),
    ),
  );
}
