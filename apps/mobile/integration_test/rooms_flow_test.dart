import 'dart:io';

import 'package:duoscene/app/duoscene_app.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/auth/token_store.dart';
import 'package:duoscene/features/rooms/room_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android login, secure restore, create and invitation join with real MySQL',
    (tester) async {
      const base = String.fromEnvironment('API_BASE_URL');
      const ownerName = String.fromEnvironment('TEST_OWNER');
      const guestName = String.fromEnvironment('TEST_GUEST');
      const password = String.fromEnvironment('TEST_PASSWORD');
      expect(
        ownerName,
        isNotEmpty,
        reason: 'Use scripts/test-mobile-backend.mjs --native',
      );
      final origin = Uri.parse(base);
      Future<void> waitFor(Finder finder) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          if (finder.evaluate().isNotEmpty) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          finder,
          findsOneWidget,
          reason: 'UI did not complete the backend operation',
        );
      }

      Future<void> tapVisible(Finder finder) async {
        // 原生 IME 的视口变化不受 Flutter 动画计数控制；先收起键盘并等待实际命中。
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        for (var attempt = 0; attempt < 30; attempt++) {
          await tester.ensureVisible(finder);
          await tester.pump(const Duration(milliseconds: 200));
          if (finder.hitTestable().evaluate().isNotEmpty) {
            await tester.tap(finder.hitTestable());
            return;
          }
        }
        fail('Control did not become tappable');
      }

      final store = SecureTokenStore(origin);
      await store.clear();
      final owner = Session(ApiClient(origin), store);
      final guest = Session(ApiClient(origin), _VolatileStore());
      addTearDown(() async {
        await store.clear();
        guest.dispose();
        owner.dispose();
      });
      await tester.pumpWidget(DuosceneApp(session: owner));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      Future<void> screenshot(String name) async {
        final bytes = await binding.takeScreenshot(name);
        await File('${Directory.systemTemp.path}/duoscene-$name.png')
            .writeAsBytes(bytes);
      }

      await screenshot('login');
      await tester.enterText(find.byKey(const Key('username')), ownerName);
      await tester.enterText(find.byKey(const Key('password')), password);
      await tapVisible(find.text('登录'));
      await waitFor(find.byKey(const Key('tab-3')));
      await tester.tap(find.byKey(const Key('tab-3')));
      await tester.pumpAndSettle();
      await tapVisible(find.text('观影邀请'));
      await tapVisible(find.text('邀请与房间'));
      await waitFor(find.text('我们的房间'));
      await tester.pumpAndSettle();
      expect(find.text('我们的房间'), findsOneWidget);
      final saved = await store.read();
      expect(saved, isNotNull);
      await tester.tap(find.text('创建房间'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('room-name')), '两个人的周末');
      await tapVisible(find.text('创建并进入'));
      await waitFor(find.text('1 / 2 席'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2 席'), findsOneWidget);
      await tester.ensureVisible(find.text('生成一次性邀请'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成一次性邀请'));
      await waitFor(find.text('复制邀请码'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('复制邀请码'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制邀请码'));
      await tester.pumpAndSettle();
      final clipboard = await Clipboard.getData('text/plain');
      expect(clipboard?.text?.length, 43);
      await guest.login(guestName, password);
      final joined = await RoomRepository(guest).join(clipboard!.text!);
      expect(joined.members.length, 2);
      await tester.tap(find.byTooltip('刷新成员'));
      await waitFor(find.text('2 / 2 席'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2 席'), findsOneWidget);
      expect(find.text('测试成员'), findsOneWidget);
      await screenshot('room');
      // 销毁 app 后创建新 Session，实际调用 Android 安全存储恢复并轮换凭据。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final restored = Session(ApiClient(origin), store);
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.user?.id, owner.user?.id);
      expect(await store.read(), isNot(saved));
      await restored.logout();
      expect(await store.read(), isNull);

      // 第二位成员通过实际表单粘贴邀请；重复加入保持两席，不重复消费邀请。
      await guest.logout();
      final second = Session(ApiClient(origin), _VolatileStore());
      addTearDown(second.dispose);
      await tester.pumpWidget(DuosceneApp(session: second));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('username')), guestName);
      await tester.enterText(find.byKey(const Key('password')), password);
      // 第二次登录覆盖软键盘完成键路径，避免原生 IME 改变视口期间按旧坐标点击。
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(find.byKey(const Key('tab-3')));
      await tester.tap(find.byKey(const Key('tab-3')));
      await tester.pumpAndSettle();
      await tapVisible(find.text('观影邀请'));
      await tapVisible(find.text('邀请与房间'));
      await waitFor(find.text('我们的房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('邀请加入'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite-token')),
        clipboard.text!,
      );
      await tapVisible(find.text('加入房间'));
      await waitFor(find.text('2 / 2 席'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2 席'), findsOneWidget);
      await second.logout();
      await Clipboard.setData(const ClipboardData(text: ''));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _VolatileStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
