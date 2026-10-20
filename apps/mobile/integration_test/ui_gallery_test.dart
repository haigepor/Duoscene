import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/palette.dart';
import 'package:duoscene/features/experience/preview_gallery.dart';
import 'package:duoscene/features/catalog/app_shell.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:duoscene/design/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '18 original-design pages render on Android with real modal routes',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final propagate = binding.shouldPropagateDevicePointerEvents;
      binding.shouldPropagateDevicePointerEvents = false;
      addTearDown(() => binding.shouldPropagateDevicePointerEvents = propagate);
      const base = String.fromEnvironment('UI_CAPTURE_BASE');
      expect(base, isNotEmpty, reason: 'Run tool/ui-native.mjs');
      var converted = false;
      final cases = <({int page, String state, String name})>[
        for (var i = 0; i < 18; i++)
          (
            page: i,
            state: 'normal',
            name: '${(i + 1).toString().padLeft(2, '0')}',
          ),
        for (final entry in <String, int>{
          'home-loading': 0,
          'home-source-error': 0,
          'history-empty': 2,
          'favorites-empty': 12,
          'private-chat-empty': 5,
          'peer-buffering': 5,
          'peer-offline': 5,
          'manual-pause': 5,
          'message-send-failed': 6,
          'chat-keyboard': 6,
          'mic-denied': 10,
          'invite-busy': 7,
          'invite-expired-sender': 7,
          'invite-expired-receiver': 13,
          'room-full': 13,
          'room-closed': 13,
          'invite-revoked': 13,
          'shared-episode': 9,
          'short-unread': 1,
          'clear-history': 14,
          'logout': 15,
          'login-invalid': 11,
          'search-empty': 8,
          'media-unavailable': 4,
        }.entries)
          (page: entry.value, state: entry.key, name: 'state-${entry.key}'),
      ];
      Future<void> settle() async {
        for (var frame = 0; frame < 15; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      for (final example in cases) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(example.name),
            theme: duosceneTheme,
            builder: themeSystemBars,
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: PreviewHost(page: example.page, scenario: example.state),
          ),
        );
        await settle();
        if (example.state == 'clear-history' || example.state == 'logout') {
          final button = find.text(
            example.state == 'logout' ? '退出登录' : '清理我的本机观看记录',
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await settle();
          expect(find.text('取消'), findsOneWidget);
        } else if (example.state == 'shared-episode') {
          await tester.tap(find.text('09'));
          await settle();
          expect(find.text('请求换集'), findsOneWidget);
        } else if (example.state == 'chat-keyboard') {
          final field = find.byKey(const Key('chat-input'));
          expect(field, findsOneWidget);
          await tester.tap(field);
          await settle();
          final element = tester.element(field);
          final media = MediaQuery.of(element);
          expect(
            tester.getBottomLeft(find.byKey(const Key('chat-send'))).dy,
            lessThanOrEqualTo(media.size.height - media.viewInsets.bottom),
          );
        }
        expect(tester.takeException(), isNull, reason: example.name);
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump();
        }
        final name = example.name;
        final png = await binding.takeScreenshot('ui-$name');
        final response = await http.post(
          Uri.parse('$base/capture/$name.png'),
          headers: {'Content-Type': 'image/png'},
          body: png,
        );
        expect(response.statusCode, 204);
        if (example.state == 'home-source-error') {
          await tester.tap(find.text('重试'));
          await settle();
          expect(find.text('暂时无法加载片库'), findsNothing);
        } else if (example.state == 'message-send-failed') {
          await tester.tap(find.text('发送失败，点击重试'));
          await settle();
          expect(find.text('发送失败，点击重试'), findsNothing);
          expect(find.text('这一段好好看'), findsOneWidget);
        } else if (example.state == 'clear-history' ||
            example.state == 'logout' ||
            example.state == 'shared-episode') {
          await tester.tap(find.text('取消'));
          await settle();
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${example.name} interaction',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 300));
        // 不保留前一页的播放器或抽屉，下一页使用独立的预览作用域。
        await tester.pumpWidget(const SizedBox.shrink());
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      for (final theme in {
        'dark': DSPalette.dark,
        'forest': DSPalette.woodland,
      }.entries) {
        for (var page = 0; page < 18; page++) {
          final name = 'state-${theme.key}-${page + 1}';
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(name),
              theme: buildDuosceneTheme(theme.value),
              builder: themeSystemBars,
              debugShowCheckedModeBanner: false,
              home: PreviewHost(page: page),
            ),
          );
          await settle();
          expect(tester.takeException(), isNull, reason: name);
          final png = await binding.takeScreenshot(name);
          expect(
            (await http.post(
              Uri.parse('$base/capture/$name.png'),
              headers: {'Content-Type': 'image/png'},
              body: png,
            )).statusCode,
            204,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await settle();
        }
      }
      // 补充真实入口和滚动/快速切换证据，不能仅用静态预览代替导航验收。
      Future<void> capture(String name) async {
        await settle();
        expect(tester.takeException(), isNull, reason: name);
        final png = await binding.takeScreenshot(name);
        expect(
          (await http.post(
            Uri.parse('$base/capture/$name.png'),
            headers: {'Content-Type': 'image/png'},
            body: png,
          )).statusCode,
          204,
        );
      }

      final library = LibraryState(accountId: 'motion-preview', preview: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
            builder: themeSystemBars,
          debugShowCheckedModeBanner: false,
          home: AppShell(preview: true, library: library),
        ),
      );
      await settle();
      await tester.drag(
        find.byKey(const PageStorageKey('watch-home')),
        const Offset(0, -220),
      );
      await capture('state-home-scrolled');
      final chrome = find.descendant(
        of: find.byType(ScrollChrome).first,
        matching: find.byKey(const Key('scroll-chrome')),
      );
      expect(
        (tester.widget<DecoratedBox>(chrome).decoration as BoxDecoration)
            .color!
            .a,
        greaterThan(.9),
      );
      for (final tab in [1, 2, 3, 0, 3]) {
        await tester.tap(find.byKey(Key('tab-$tab')));
        await tester.pump(const Duration(milliseconds: 70));
      }
      await settle();
      await tester.drag(
        find.byKey(const PageStorageKey('profile')),
        const Offset(0, -100),
      );
      await capture('state-profile-scrolled');
      await tester.ensureVisible(find.text('播放与音频'));
      await tester.tap(find.text('播放与音频'));
      await settle();
      await tester.tap(find.text('打开播放器'));
      await capture('state-player-library');
      expect(find.text('你的播放空间'), findsOneWidget);
      expect(find.text('视频地址'), findsOneWidget);
      // 重建独立 Navigator；仅替换 home 会保留上一次测试压入的播放器路由。
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('stars-composition'),
          theme: duosceneTheme,
            builder: themeSystemBars,
          debugShowCheckedModeBanner: false,
          home: ExperiencePlayer(film: films[2], library: library),
        ),
      );
      await capture('state-player-stars');
      final assetNames = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .whereType<AssetImage>()
          .map((i) => i.assetName);
      expect(assetNames, contains(films[2].image));
      await tester.tap(find.text('简介'));
      await settle();
      expect(find.text('全部设置 ›'), findsOneWidget);
      await tester.tap(find.text('交流'));
      await settle();
      expect(find.byKey(const Key('chat-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle();
      library.dispose();
    },
    timeout: const Timeout(Duration(minutes: 9)),
  );
}
