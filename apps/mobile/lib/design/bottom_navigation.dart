import 'dart:io' show File, Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens.dart';

/// 真机基线（docs/perf-baseline-20261023.zh.md）实测底栏实时模糊是 raster 瓶颈
/// 的主要成本（首页滚动 46.6% / 播放中 56.6% 帧超 60Hz 预算）。低内存机型的
/// GPU 撑不起逐帧背景重采样：改用更高不透明度的纯渐变（TikTok 底栏即半透明
/// 实色），桌面与高内存机型保留玻璃模糊。
final bool kLowTierGpu = _detectLowTierGpu();

bool _detectLowTierGpu() {
  if (!Platform.isAndroid) return false;
  try {
    final meminfo = File('/proc/meminfo').readAsStringSync();
    final total = RegExp(r'MemTotal:\s+(\d+) kB').firstMatch(meminfo);
    if (total == null) return false;
    return int.parse(total.group(1)!) < 5 * 1024 * 1024;
  } catch (_) {
    return false;
  }
}

class DuosceneNavigation extends StatelessWidget {
  const DuosceneNavigation({
    super.key,
    required this.index,
    required this.onSelect,
    this.notifyReselection = false,
  });
  final int index;
  final ValueChanged<int> onSelect;

  /// 主壳层需要用最新状态处理连点取消；独立预览保留当前项不重复导航的规则。
  final bool notifyReselection;

  @override
  Widget build(BuildContext context) {
    final onMedia = index == 1;
    final p = onMedia ? DSPalette.dark : DSPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = onMedia ? Colors.white : p.primary;
    final mutedColor = onMedia ? Colors.white70 : p.muted;
    final glass = !kLowTierGpu;
    // 无实时模糊时抬高面板不透明度，保住底栏文字在任意画面上的对比度。
    final panelTop = switch ((glass, onMedia, dark)) {
      (false, true, _) => .58,
      (false, false, true) => .72,
      (false, false, false) => .78,
      (_, true, _) => .28,
      (_, false, true) => .42,
      (_, false, false) => .48,
    };
    final panelBottom = switch ((glass, onMedia, dark)) {
      (false, true, _) => .44,
      (false, false, true) => .52,
      (false, false, false) => .54,
      (_, true, _) => .16,
      (_, false, true) => .24,
      (_, false, false) => .26,
    };
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          key: const Key('navigation-island'),
          borderRadius: BorderRadius.circular(28),
          // 模糊限制在底栏内且强度固定，滑块动画只改变自己的位置；低端机
          // 跳过逐帧背景重采样（真机基线 raster 超预算的主因）。
          child: _BlurGate(
            enabled: glass,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    p.panel.withValues(alpha: panelTop),
                    p.panel.withValues(alpha: panelBottom),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: (onMedia ? Colors.white : p.ink).withValues(
                    alpha: onMedia
                        ? .16
                        : dark
                        ? .12
                        : .08,
                  ),
                  width: .7,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      // 唯一选中层移动，按钮不交叉淡入背景或绘制灰色墨水。
                      AnimatedPositionedDirectional(
                        duration: DSMotion.duration(
                          context,
                          DSMotion.navigation,
                        ),
                        curve: DSMotion.curve,
                        start: constraints.maxWidth / 4 * index + 3,
                        top: 4,
                        bottom: 4,
                        width: constraints.maxWidth / 4 - 6,
                        child: DecoratedBox(
                          key: const Key('navigation-thumb'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selectedColor.withValues(alpha: .13),
                              width: .6,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                onMedia
                                    ? Colors.white.withValues(alpha: .18)
                                    : p.tint.withValues(alpha: .55),
                                onMedia
                                    ? Colors.white.withValues(alpha: .08)
                                    : p.tint.withValues(alpha: .30),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: Row(
                          children: [
                            for (var i = 0; i < 4; i++)
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: index == i,
                                  label: ['观影', '短剧', '记录', '我的'][i],
                                  excludeSemantics: true,
                                  child: TextButton(
                                    key: Key('tab-$i'),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      overlayColor: Colors.transparent,
                                      backgroundColor: Colors.transparent,
                                      splashFactory: NoSplash.splashFactory,
                                      shape: const StadiumBorder(),
                                    ),
                                    onPressed: () {
                                      // 壳层读取最新选择；同帧连续点击时，绘制索引可能仍是旧值。
                                      if (index != i || notifyReselection)
                                        onSelect(i);
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        DSIcon(
                                          [
                                            'film-reel',
                                            'list-video',
                                            'history',
                                            'user-round',
                                          ][i],
                                          size: 18,
                                          color: index == i
                                              ? selectedColor
                                              : mutedColor,
                                        ),
                                        const SizedBox(height: 2),
                                        AnimatedDefaultTextStyle(
                                          duration: DSMotion.duration(
                                            context,
                                            DSMotion.fast,
                                          ),
                                          style: TextStyle(
                                            fontSize: 10,
                                            height: 1.2,
                                            fontWeight: index == i
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: index == i
                                                ? selectedColor
                                                : mutedColor,
                                          ),
                                          child: Text(
                                            ['观影', '短剧', '记录', '我的'][i],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 背景实时模糊的开关壳：低端机不进 BackdropFilter，省掉整层的 saveLayer 重采样。
class _BlurGate extends StatelessWidget {
  const _BlurGate({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled
      ? BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: child,
        )
      : child;
}
