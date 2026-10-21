import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/api_client.dart';
import '../core/api_endpoint.dart';
import '../features/auth/login_page.dart';
import '../features/auth/session.dart';
import '../features/auth/token_store.dart';
import '../features/catalog/app_shell.dart';
import 'theme.dart';
import '../design/theme_preferences.dart';

class DuosceneApp extends StatefulWidget {
  const DuosceneApp({super.key, this.session});
  final Session? session;
  @override
  State<DuosceneApp> createState() => _DuosceneAppState();
}

class _DuosceneAppState extends State<DuosceneApp> {
  Session? _session;
  final appearance = ThemePreferences();
  @override
  void initState() {
    super.initState();
    unawaited(appearance.restore());
    _session = widget.session;
    if (_session == null) {
      const configured = String.fromEnvironment('API_BASE_URL');
      final fallback = defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:3000'
          : 'http://127.0.0.1:3000';
      final origin = apiEndpoint(
        configured.isEmpty && kDebugMode ? fallback : configured,
        debug: !kReleaseMode,
        allowLanHttp: const bool.fromEnvironment('ALLOW_LAN_HTTP'),
      );
      if (origin != null) {
        try {
          _session = Session(ApiClient(origin), SecureTokenStore(origin));
        } on ArgumentError {
          /* 配置错误展示在入口，不把凭据发到未知地址。 */
        }
      }
    }
    if (_session != null) unawaited(_session!.restore());
  }

  @override
  void dispose() {
    if (widget.session == null) _session?.dispose();
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null)
      return MaterialApp(
        theme: duosceneTheme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('服务地址配置无效，请通过 API_BASE_URL 设置 HTTPS 服务地址。'),
            ),
          ),
        ),
      );
    return ThemePreferencesScope(
      preferences: appearance,
      child: ListenableBuilder(
        listenable: Listenable.merge([session, appearance]),
        builder: (context, _) => MaterialApp(
          // 身份改变时销毁旧 Navigator，房间详情与邀请码不会留在登录页背后。
          key: ValueKey(session.user?.id),
          title: 'Duoscene',
          builder: themeSystemBars,
          debugShowCheckedModeBanner: false,
          theme: duosceneTheme,
          darkTheme: duosceneDarkTheme,
          themeMode: appearance.mode,
          themeAnimationDuration: const Duration(milliseconds: 200),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: !session.initialized || !appearance.loaded
              ? const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(semanticsLabel: '正在恢复登录'),
                  ),
                )
              : session.user == null
              ? LoginPage(session: session)
              : AppShell(session: session),
        ),
      ),
    );
  }
}
