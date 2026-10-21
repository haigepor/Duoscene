import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/profile_page.dart';
import 'package:duoscene/features/experience/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_test.dart' show MemoryTokenStore, credentials, ok;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'account copy and logout confirmation work at both themes and scales',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final session = Session(
        ApiClient(
          Uri.parse('http://localhost:3000'),
          client: MockClient((_) async => ok(credentials('access', 'refresh'))),
        ),
        MemoryTokenStore(),
      );
      await session.login('owner', 'correct-password');
      final library = LibraryState(accountId: 'owner', session: session);
      for (final dark in [false, true]) {
        for (final large in [false, true]) {
          t.view.physicalSize = Size(large ? 320 : 390, 780);
          await t.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: buildDuosceneTheme(
                dark ? DSPalette.dark : DSPalette.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(large ? 2 : 1),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: AccountPage(library: library),
            ),
          );
          await t.pumpAndSettle();
          final copy = find.byTooltip('复制账户名');
          await Scrollable.ensureVisible(t.element(copy), alignment: .25);
          await t.tap(copy);
          await t.pumpAndSettle();
          expect(copied, 'owner');
          final logout = find.widgetWithText(OutlinedButton, '退出登录');
          await Scrollable.ensureVisible(t.element(logout), alignment: .25);
          await t.tap(logout);
          await t.pumpAndSettle();
          expect(find.text('退出登录？'), findsOneWidget);
          await t.tap(find.text('取消'));
          await t.pumpAndSettle();
          expect(session.user, isNotNull);
          expect(t.takeException(), isNull);
        }
      }
      await t.pumpWidget(const SizedBox());
      library.dispose();
      session.dispose();
    },
  );

  testWidgets(
    'profile developer footer and audio open-player entry stay hidden',
    (t) async {
      final library = LibraryState(accountId: 'hidden-tools');
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: ProfilePage(
              library: library,
              previewTools: const Text('开发预览 · 18 页面 / 24 状态'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('开发预览'), findsNothing);
      expect(find.textContaining('片库为设计预览'), findsNothing);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: AudioSettingsPage(library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('打开播放器'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
