import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/theme_preferences.dart';
import '../../design/illustrations.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = ThemePreferencesScope.of(context);
    final mode = settings?.mode ?? ThemeMode.system;
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final note = switch (mode) {
      ThemeMode.system => '随设备自动切换，当前为${systemDark ? '深色' : '浅色'}。',
      ThemeMode.light => '始终使用浅色外观。',
      ThemeMode.dark => '始终使用深色外观。',
    };
    return PageFrame(
      title: '外观',
      child: ListView(
        padding: const EdgeInsets.all(DS.pageInset),
        children: [
          const DSIntro('你的观影氛围', '统一蓝色，选择舒适的明暗。', artwork: 'appearance-glass'),
          const SizedBox(height: DS.space24),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('明暗模式', style: DS.secondarySection),
                const SizedBox(height: DS.space12),
                _BrightnessSelector(
                  selected: mode,
                  onChanged: (value) async {
                    try {
                      if (settings == null) {
                        tell(context, '请从应用设置中切换外观。');
                        return;
                      }
                      await settings.change(brightness: value);
                    } catch (_) {
                      if (context.mounted) tell(context, '外观保存失败，请重试。');
                    }
                  },
                ),
                const SizedBox(height: DS.space12),
                Semantics(
                  liveRegion: true,
                  child: Text(note, style: DS.smallFor(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: DS.space16),
          Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DSIcon(
                  'info',
                  size: DS.iconSmall,
                  color: DSPalette.of(context).muted,
                ),
                const SizedBox(width: DS.space8),
                Expanded(
                  child: Text(
                    '更改自动保存，仅在此设备生效。\n视频与全屏播放始终保持深色。',
                    style: DS.smallFor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrightnessSelector extends StatelessWidget {
  const _BrightnessSelector({required this.selected, required this.onChanged});
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // 大字号下改为纵向分段，避免缩小文字或裁剪“跟随系统”。
      final vertical =
          constraints.maxWidth < 270 ||
          MediaQuery.textScalerOf(context).scale(12) > 16.8;
      final optionHeight =
          (MediaQuery.textScalerOf(context).scale(12) * 1.3 + 20)
              .clamp(DS.touchTarget, double.infinity)
              .toDouble();
      final availableWidth = constraints.maxWidth - 8;
      final widths = [
        (availableWidth - 6) * 13 / 33,
        (availableWidth - 6) * 10 / 33,
        (availableWidth - 6) * 10 / 33,
      ];
      final starts = [0.0, widths[0] + 3, widths[0] + widths[1] + 6];
      final index = ThemeMode.values.indexOf(selected);
      final options = [
        for (final mode in ThemeMode.values)
          _ModeOption(
            mode: mode,
            selected: selected == mode,
            onTap: () => onChanged(mode),
          ),
      ];
      return Material(
        color: DSPalette.of(context).subtle,
        borderRadius: BorderRadius.circular(DS.panelRadius),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: vertical ? optionHeight * 3 + 8 : optionHeight,
            child: Stack(
              children: [
                // 单一滑块接续当前绘制位置，连点反向也不会跳回起点。
                AnimatedPositionedDirectional(
                  duration: DSMotion.duration(context),
                  curve: DSMotion.curve,
                  start: vertical ? 0 : starts[index],
                  top: vertical ? index * (optionHeight + 4) : 0,
                  width: vertical ? availableWidth : widths[index],
                  height: optionHeight,
                  child: DecoratedBox(
                    key: const Key('appearance-mode-indicator'),
                    decoration: BoxDecoration(
                      color: DSPalette.of(context).panel,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: vertical
                      ? Column(
                          children: [
                            Expanded(child: options[0]),
                            const SizedBox(height: 4),
                            Expanded(child: options[1]),
                            const SizedBox(height: 4),
                            Expanded(child: options[2]),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(flex: 13, child: options[0]),
                            const SizedBox(width: 3),
                            Expanded(flex: 10, child: options[1]),
                            const SizedBox(width: 3),
                            Expanded(flex: 10, child: options[2]),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DSPalette.of(context);
    final (label, icon) = switch (mode) {
      ThemeMode.system => ('跟随系统', Icons.desktop_windows_outlined),
      ThemeMode.light => ('浅色', Icons.light_mode_outlined),
      ThemeMode.dark => ('深色', Icons.dark_mode_outlined),
    };
    final color = selected ? palette.primary : palette.muted;
    final radius = BorderRadius.circular(10);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          focusColor: palette.primary.withValues(alpha: .12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DS.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: DS.iconSmall, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: DS.label.copyWith(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
