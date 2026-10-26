import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 借鉴 Playra MobileTabView：缓存 Element，反向切换从当前绘制位置继续。
/// 前台同步父级更新，后台延迟到重新可见时更新，保留输入与滚动状态。
class MotionTabs extends StatefulWidget {
  const MotionTabs({
    super.key,
    required this.index,
    required this.children,
    this.isCovered = false,
    this.preparingIndex,
  });
  final int index;
  final List<Widget> children;
  final bool isCovered;

  /// 只预布局用户已点击的目标页；保持不可见，由 index 提交后统一启动过渡。
  final int? preparingIndex;
  @override
  State<MotionTabs> createState() => _MotionTabsState();
}

class _MotionTabsState extends State<MotionTabs>
    with SingleTickerProviderStateMixin {
  late final controller =
      AnimationController(vsync: this, duration: DSMotion.navigation)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() {
              from = {widget.index: 0};
              to = {widget.index: 0};
            });
          }
        });
  late final visited = <int>{widget.index};
  final pages = <int, Widget>{};
  late Map<int, double> from = {widget.index: 0}, to = {widget.index: 0};
  @override
  void initState() {
    super.initState();
    prepare();
  }

  void prepare() {
    final index = widget.preparingIndex;
    if (index == null) return;
    assert(index >= 0 && index < widget.children.length);
    visited.add(index);
  }

  double offset(int i) =>
      (from[i] ?? 0) +
      ((to[i] ?? 0) - (from[i] ?? 0)) *
          DSMotion.curve.transform(controller.value);
  @override
  void didUpdateWidget(covariant MotionTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    prepare();
    if (oldWidget.index == widget.index) return;
    // 离开的页面仍需接收 active=false，让轮播和短剧及时停止。
    pages[oldWidget.index] = widget.children[oldWidget.index];
    final direction = widget.index > oldWidget.index ? 1.0 : -1.0;
    final positions = {for (final i in from.keys) i: offset(i)};
    controller.stop();
    visited.add(widget.index);
    positions.putIfAbsent(widget.index, () => direction);
    from = positions;
    to = {
      for (final i in positions.keys) i: i == widget.index ? 0 : -direction,
    };
    if (MediaQuery.disableAnimationsOf(context)) {
      from = {widget.index: 0};
      to = {widget.index: 0};
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final i in visited) {
      if (from.containsKey(i) ||
          i == widget.preparingIndex ||
          !pages.containsKey(i)) {
        pages[i] = widget.children[i];
      }
    }
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final i in [
            ...visited.where((i) => i != widget.index),
            widget.index,
          ])
            Positioned.fill(
              key: ValueKey(i),
              child: Offstage(
                offstage: !from.containsKey(i),
                child: AnimatedBuilder(
                  // 逐帧仅移动可见页面，不重建整棵分页布局。
                  animation: from.containsKey(i)
                      ? controller
                      : kAlwaysDismissedAnimation,
                  child: TickerMode(
                    enabled: !widget.isCovered && i == widget.index,
                    child: ExcludeFocus(
                      excluding: widget.isCovered || i != widget.index,
                      child: ExcludeSemantics(
                        excluding: widget.isCovered || i != widget.index,
                        child: IgnorePointer(
                          ignoring: widget.isCovered || i != widget.index,
                          child: RepaintBoundary(child: pages[i]),
                        ),
                      ),
                    ),
                  ),
                  builder: (context, child) => FractionalTranslation(
                    translation: Offset(offset(i), 0),
                    child: child,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DSPageTransitions extends PageTransitionsBuilder {
  const DSPageTransitions();

  @override
  Duration get transitionDuration => DSMotion.navigation;
  @override
  Duration get reverseTransitionDuration => DSMotion.standard;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // 与 Playra 的统一平台路由一致：移动端侧滑，桌面端轻量上移。
    final transitions = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => const CupertinoPageTransitionsBuilder(),
      _ => const FadeUpwardsPageTransitionsBuilder(),
    };
    return transitions.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// 一套指示器用于片库分类、记录筛选与播放器分区，快速点击由隐式动画接续。
class DSTabs extends StatelessWidget {
  const DSTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.pill = false,
    this.ticket = false,
    this.dense = false,
  }) : assert(!ticket || pill, !dense || !pill);
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool pill;
  final bool ticket;

  /// 紧凑档（约 36 高）：嵌在播放器等内容区里的分区条，不再承担独立触控行。
  final bool dense;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final textHeight =
          MediaQuery.textScalerOf(context).scale(DS.bodySize) * 1.4;
      final height = dense
          ? (textHeight + 21).clamp(38.0, DS.touchTarget)
          : (textHeight + 24).clamp(DS.touchTarget, 80.0);
      final pillHeight =
          (textHeight + (ticket ? 8 : 10)).clamp(28.0, height - 8);
      return SizedBox(
        height: height,
        child: Stack(
          children: [
            AnimatedPositionedDirectional(
              duration: DSMotion.duration(
                context,
                pill ? DSMotion.navigation : DSMotion.standard,
              ),
              curve: DSMotion.curve,
              start:
                  c.maxWidth / labels.length * index +
                  (pill ? 4 : (c.maxWidth / labels.length - 24) / 2),
              bottom: pill ? (height - pillHeight) / 2 : dense ? 6 : DS.space8,
              width: pill ? c.maxWidth / labels.length - 8 : 24,
              height: pill ? pillHeight : DS.space2,
              child: ticket
                  ? RepaintBoundary(
                      key: const Key('tabs-pill-indicator'),
                      child: CustomPaint(
                        key: const Key('tabs-ticket-paint'),
                        painter: _TicketIndicator(DSPalette.of(context)),
                      ),
                    )
                  : DecoratedBox(
                      key: Key(
                        pill ? 'tabs-pill-indicator' : 'tabs-line-indicator',
                      ),
                      decoration: BoxDecoration(
                        color: DSPalette.of(context).primary,
                        borderRadius: BorderRadius.circular(pill ? 20 : 2),
                      ),
                    ),
            ),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: index == i,
                      button: true,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          overlayColor: Colors.transparent,
                          splashFactory: NoSplash.splashFactory,
                          backgroundColor: Colors.transparent,
                        ),
                        onPressed: () => onChanged(i),
                        child: AnimatedDefaultTextStyle(
                          duration: DSMotion.duration(context, DSMotion.fast),
                          style: (pill ? DS.body : DS.label).copyWith(
                            fontWeight: pill
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: index == i
                                ? pill
                                      ? ticket
                                            ? DSPalette.of(context).onTint
                                            : DSPalette.of(context).onPrimary
                                      : DSPalette.of(context).primary
                                : DSPalette.of(context).muted,
                          ),
                          child: Text(labels[i], maxLines: 1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// 票签与切口一次绘制；无需位图、背景遮盖或实时模糊，移动时只合成这一层。
class _TicketIndicator extends CustomPainter {
  _TicketIndicator(this.palette);
  final DSPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.5);
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(DS.radiusSmall)),
      );
    final cuts = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(0, size.height / 2), radius: DS.space4),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width, size.height / 2),
          radius: DS.space4,
        ),
      );
    final ticket = Path.combine(PathOperation.difference, outline, cuts);
    canvas.drawShadow(ticket, palette.primary.withValues(alpha: .12), 1, false);
    canvas.drawPath(
      ticket,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.panel.withValues(alpha: .85), palette.tint],
        ).createShader(rect),
    );
    canvas.drawPath(
      ticket,
      Paint()
        ..color = palette.primary.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75,
    );
    final perforation = Paint()
      ..color = palette.primary.withValues(alpha: .18)
      ..strokeWidth = .75
      ..strokeCap = StrokeCap.round;
    for (final x in [DS.space8, size.width - DS.space8]) {
      for (double y = DS.space4; y < size.height - DS.space4; y += DS.space4) {
        canvas.drawLine(Offset(x, y), Offset(x, y + DS.space2), perforation);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TicketIndicator oldDelegate) =>
      oldDelegate.palette != palette;
}
