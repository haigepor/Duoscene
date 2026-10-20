import 'package:flutter/material.dart';

import 'tokens.dart';

/// 借鉴 Playra MobileTabView：缓存 Element，反向切换从当前绘制位置继续。
/// children 仍随父级更新，避免缓存旧闭包导致账户、收藏或播放 active 状态过期。
class MotionTabs extends StatefulWidget {
  const MotionTabs({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;
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
  late Map<int, double> from = {widget.index: 0}, to = {widget.index: 0};
  double offset(int i) =>
      (from[i] ?? 0) +
      ((to[i] ?? 0) - (from[i] ?? 0)) *
          DSMotion.curve.transform(controller.value);
  @override
  void didUpdateWidget(covariant MotionTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
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
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Stack(
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
                child: FractionalTranslation(
                  translation: Offset(offset(i) * .035, 0),
                  child: Opacity(
                    opacity: (1 - offset(i).abs()).clamp(0.0, 1.0),
                    child: TickerMode(
                      enabled: i == widget.index,
                      child: ExcludeFocus(
                        excluding: i != widget.index,
                        child: ExcludeSemantics(
                          excluding: i != widget.index,
                          child: IgnorePointer(
                            ignoring: i != widget.index,
                            child: RepaintBoundary(child: widget.children[i]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class DSPageTransitions extends PageTransitionsBuilder {
  const DSPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final enter = animation.drive(CurveTween(curve: DSMotion.curve));
    return SlideTransition(
      position: Tween(
        begin: const Offset(.08, 0),
        end: Offset.zero,
      ).animate(enter),
      child: FadeTransition(opacity: enter, child: child),
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
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool pill;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final height =
          (MediaQuery.textScalerOf(context).scale(DS.bodySize) * 1.4 + 24)
              .clamp(DS.touchTarget, 80.0);
      return SizedBox(
        height: height,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: DSMotion.duration(context),
              curve: DSMotion.curve,
              left:
                  c.maxWidth / labels.length * index +
                  (pill ? 3 : (c.maxWidth / labels.length - 24) / 2),
              bottom: pill ? 4 : 3,
              width: pill ? c.maxWidth / labels.length - 6 : 24,
              height: pill ? height - 8 : 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: pill
                      ? DSPalette.of(context).primary.withValues(alpha: .14)
                      : DSPalette.of(context).primary,
                  borderRadius: BorderRadius.circular(
                    pill ? DS.radiusSmall : 2,
                  ),
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
                          style: DS.label.copyWith(
                            color: index == i
                                ? DSPalette.of(context).primary
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
