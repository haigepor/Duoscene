import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/theme.dart';
import 'design/palette.dart';
import 'design/theme_preferences.dart';
import 'features/experience/preview_gallery.dart';

/// 独立样式入口复用正式页面；预览身份不请求真实账户或房间。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StylePreview());
}

class StylePreview extends StatefulWidget {
  const StylePreview({super.key});
  @override
  State<StylePreview> createState() => _StylePreviewState();
}

class _StylePreviewState extends State<StylePreview> {
  final appearance = ThemePreferences();
  final semantics = WidgetsBinding.instance.ensureSemantics();
  int page = 0;
  double width = 390;
  @override
  void initState() {
    super.initState();
    unawaited(appearance.restore());
  }

  @override
  void dispose() {
    appearance.dispose();
    semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ThemePreferencesScope(
    preferences: appearance,
    child: ListenableBuilder(
      listenable: appearance,
      builder: (context, _) {
        final forest = appearance.selected == DSTheme.forest;
        final theme = buildDuosceneTheme(
          forest ? DSPalette.woodland : DSPalette.light,
        );
        final dark = buildDuosceneTheme(
          forest ? DSPalette.woodland : DSPalette.dark,
        );
        return MaterialApp(
          title: 'Duoscene · 样式预览',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: dark,
          themeMode: appearance.mode,
          home: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Duoscene · 样式预览'),
                        DropdownButton<int>(
                          value: page,
                          items: List.generate(
                            previewPages.length,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text('${i + 1} · ${previewPages[i]}'),
                            ),
                          ),
                          onChanged: (value) {
                            if (value != null) setState(() => page = value);
                          },
                        ),
                        DropdownButton<String>(
                          value: forest ? 'forest' : appearance.mode.name,
                          items: const [
                            DropdownMenuItem(
                              value: 'light',
                              child: Text('晴空 · 浅色'),
                            ),
                            DropdownMenuItem(
                              value: 'dark',
                              child: Text('晴空 · 深色'),
                            ),
                            DropdownMenuItem(
                              value: 'system',
                              child: Text('跟随系统'),
                            ),
                            DropdownMenuItem(
                              value: 'forest',
                              child: Text('森林'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null)
                              unawaited(
                                appearance.change(
                                  theme: value == 'forest'
                                      ? DSTheme.forest
                                      : DSTheme.sky,
                                  brightness: switch (value) {
                                    'dark' => ThemeMode.dark,
                                    'system' => ThemeMode.system,
                                    _ => ThemeMode.light,
                                  },
                                ),
                              );
                          },
                        ),
                        DropdownButton<double>(
                          value: width,
                          items: [320.0, 390.0, 430.0]
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('${v.toInt()}dp'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => width = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: width,
                        child: MaterialApp(
                          // 只换预览页面时重置路由；换主题保留当前交互。
                          key: ValueKey(page),
              builder: (context, child) => LayoutBuilder(
                builder: (context, constraints) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                  child: child!,
                ),
              ),
                          debugShowCheckedModeBanner: false,
                          theme: theme,
                          darkTheme: dark,
                          themeMode: appearance.mode,
                          locale: const Locale('zh', 'CN'),
                          supportedLocales: const [Locale('zh', 'CN')],
                          localizationsDelegates:
                              GlobalMaterialLocalizations.delegates,
                          home: PreviewHost(page: page),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
