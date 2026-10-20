import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/theme_preferences.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = ThemePreferencesScope.of(context);
    Future<void> update({DSTheme? theme, ThemeMode? mode}) async {
      try {
        if (settings == null) {
          tell(context, '请从应用设置中切换外观。');
          return;
        }
        await settings.change(theme: theme, brightness: mode);
      } catch (_) {
        if (context.mounted) tell(context, '外观保存失败，请重试。');
      }
    }

    return PageFrame(
      title: '外观',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('选择喜欢的氛围', style: DS.section),
          const SizedBox(height: 16),
          for (final theme in DSTheme.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme == DSTheme.sky
                          ? DSPalette.light.primary
                          : DSPalette.woodland.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  title: Text(
                    theme == DSTheme.sky ? '晴空' : '森林',
                    style: DS.title,
                  ),
                  subtitle: Text(
                    theme == DSTheme.sky ? '轻盈、清晰，专注故事' : '保留山林氛围 · 深色主题',
                    style: DS.smallFor(context),
                  ),
                  trailing: settings?.selected == theme
                      ? DSIcon('check', color: DSPalette.of(context).primary)
                      : null,
                  onTap: () => update(theme: theme),
                ),
              ),
            ),
          if (settings?.selected != DSTheme.forest) ...[
            const SizedBox(height: 12),
            const Text('明暗模式', style: DS.section),
            const SizedBox(height: 12),
            Panel(
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(switch (mode) {
                        ThemeMode.system => '跟随系统',
                        ThemeMode.light => '浅色',
                        ThemeMode.dark => '深色',
                      }, style: DS.body),
                      trailing: settings?.mode == mode
                          ? DSIcon(
                              'check',
                              color: DSPalette.of(context).primary,
                            )
                          : null,
                      onTap: () => update(mode: mode),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('外观保存在这台设备，视频画面与全屏控制始终保持沉浸式深色。', style: DS.smallFor(context)),
        ],
      ),
    );
  }
}
