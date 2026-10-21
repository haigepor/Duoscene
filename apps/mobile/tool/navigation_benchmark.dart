import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/theme_preferences.dart';
import 'package:duoscene/features/catalog/app_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 独立性能入口：复用真实页面与主题，不依赖登录或写入真实账户数据。
/// Profile 使用 AOT 观察过渡，不能为了本地 HTTP 测量放宽正式入口的 HTTPS 校验。
void main() {
  if (kReleaseMode)
    throw UnsupportedError('Use this benchmark in debug/profile.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ThemePreferencesScope(
      preferences: ThemePreferences()
        ..loaded = true
        ..mode = ThemeMode.light,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: duosceneTheme,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        builder: themeSystemBars,
        home: const AppShell(preview: true),
      ),
    ),
  );
}
