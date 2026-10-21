import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/theme_preferences.dart';
import 'package:duoscene/features/experience/preview_gallery.dart';

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
        final theme = duosceneTheme;
        final dark = duosceneDarkTheme;
        return MaterialApp(
          title: 'Duoscene',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: dark,
          themeMode: appearance.mode,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              // 桌面保留手机页面比例，窄屏占满可用宽度；弹层与页面共用边界。
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
          home: const PreviewHost(page: 0),
        );
      },
    ),
  );
}
