import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoscene/app/duoscene_app.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'session_test.dart' show MemoryTokenStore, credentials, ok, unauthorized;

Map<String, Object?> roomJson({bool joined = false}) => {
  'id': 'room-1',
  'name': '周末放映室',
  'ownerUserId': 'owner',
  'status': 'OPEN',
  'controlMode': 'BOTH',
  'createdAt': '2026-10-19T00:00:00.000Z',
  'members': [
    {
      'userId': 'owner',
      'displayName': '房主',
      'seatNo': 1,
      'joinedAt': '2026-10-19T00:00:00.000Z',
    },
    if (joined)
      {
        'userId': 'guest',
        'displayName': '另一位',
        'seatNo': 2,
        'joinedAt': '2026-10-19T00:00:00.000Z',
      },
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late Session session;
  late List<http.Request> requests;
  var roomExists = false;
  var failList = false;
  void createSession() {
    requests = [];
    roomExists = false;
    failList = false;
    session = Session(
      ApiClient(
        Uri.parse('http://127.0.0.1:3000'),
        client: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/auth/login')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return body['password'] == 'correct-password'
                ? ok(credentials('access', 'refresh'))
                : unauthorized();
          }
          if (path.endsWith('/auth/logout')) return ok({'ok': true});
          if (path.endsWith('/rooms') && request.method == 'GET') {
            if (failList)
              return http.Response(
                '{"error":{"code":"DATABASE_UNAVAILABLE"},"requestId":"down"}',
                503,
              );
            return ok({
              'items': roomExists ? [roomJson()] : <Map<String, Object?>>[],
              'nextCursor': null,
            });
          }
          if (path.endsWith('/rooms') && request.method == 'POST') {
            roomExists = true;
            return ok(roomJson());
          }
          if (path.endsWith('/rooms/join')) {
            roomExists = true;
            return ok(roomJson(joined: true));
          }
          if (path.endsWith('/rooms/room-1/invites'))
            return ok({
              'id': 'invite-1',
              'token': 'A' * 43,
              'expiresAt': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .toUtc()
                  .toIso8601String(),
              'maxUses': 1,
            });
          if (path.endsWith('/rooms/room-1')) return ok(roomJson());
          return ok({'ok': true});
        }),
      ),
      MemoryTokenStore(),
    );
  }

  tearDown(() => session.dispose());

  Future<void> login(WidgetTester tester, {bool unavailable = false}) async {
    createSession();
    failList = unavailable;
    await tester.pumpWidget(DuosceneApp(session: session));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('username')), 'owner');
    await tester.enterText(
      find.byKey(const Key('password')),
      'correct-password',
    );
    await tester.ensureVisible(find.text('登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-3')));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('观影邀请')),
      alignment: .3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('观影邀请'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请与房间'));
    await tester.pumpAndSettle();
  }

  testWidgets('login validation, unauthorized response and recovery', (
    tester,
  ) async {
    createSession();
    await tester.pumpWidget(DuosceneApp(session: session));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('登录'));
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('请输入密码'), findsNWidgets(2));
    expect(requests, isEmpty);
    await tester.enterText(find.byKey(const Key('username')), 'owner');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tester.ensureVisible(find.text('登录'));
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('登录信息无效'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('password')),
      'correct-password',
    );
    await tester.ensureVisible(find.text('登录'));
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tab-0')), findsOneWidget);
    expect(find.text('搜索影片、剧集'), findsOneWidget);
  });

  testWidgets(
    'login has registration and recovery actions and password visibility preserves input',
    (tester) async {
      createSession();
      await tester.pumpWidget(DuosceneApp(session: session));
      await tester.pumpAndSettle();
      expect(find.textContaining('账户由管理员创建'), findsNothing);
      expect(find.textContaining('开发预览'), findsNothing);
      expect(find.textContaining('收到邀请'), findsNothing);
      expect(find.text('注册账号'), findsOneWidget);
      expect(find.text('忘记密码？'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('username')), 'owner');
      await tester.enterText(
        find.byKey(const Key('password')),
        'correct-password',
      );
      await tester.ensureVisible(find.byTooltip('显示密码'));
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pump();
      final password = tester.widget<TextFormField>(
        find.byKey(const Key('password')),
      );
      expect(password.controller!.text, 'correct-password');
      final edit = find.descendant(
        of: find.byKey(const Key('password')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(edit).obscureText, isFalse);
      await tester.tap(find.byTooltip('隐藏密码'));
      await tester.pump();
      expect(tester.widget<EditableText>(edit).obscureText, isTrue);
      expect(requests, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-0')), findsOneWidget);
    },
  );

  testWidgets('create a room, generate and revoke an invite, then logout', (
    tester,
  ) async {
    await login(tester);
    await tester.tap(find.text('创建房间'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('room-name')), '周末放映室');
    await tester.tap(find.text('创建并进入'));
    await tester.pumpAndSettle();
    expect(find.text('周末放映室'), findsOneWidget);
    expect(find.text('1 / 2 席'), findsOneWidget);
    await tester.ensureVisible(find.text('生成一次性邀请'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成一次性邀请'));
    await tester.pumpAndSettle();
    expect(find.text('A' * 43), findsOneWidget);
    await tester.ensureVisible(find.text('撤销这份邀请'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销这份邀请'));
    await tester.pumpAndSettle();
    expect(find.text('A' * 43), findsNothing);
    expect(
      requests.any(
        (r) => r.method == 'DELETE' && r.url.path.endsWith('/invites/invite-1'),
      ),
      isTrue,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('我们的房间'), findsNothing);
    expect((session.store as MemoryTokenStore).value, isNull);
  });

  testWidgets('join validates full invite and sends trimmed token', (
    tester,
  ) async {
    await login(tester);
    await tester.tap(find.text('邀请加入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('invite-token')), 'too-short');
    await tester.tap(find.text('加入房间'));
    await tester.pumpAndSettle();
    expect(find.text('请粘贴完整的 43 位邀请码'), findsOneWidget);
    expect(requests.where((r) => r.url.path.endsWith('/rooms/join')), isEmpty);
    await tester.enterText(
      find.byKey(const Key('invite-token')),
      '  ${'B' * 43}\n',
    );
    await tester.tap(find.text('加入房间'));
    await tester.pumpAndSettle();
    final join = requests.singleWhere(
      (r) => r.url.path.endsWith('/rooms/join'),
    );
    expect((jsonDecode(join.body) as Map<String, dynamic>)['token'], 'B' * 43);
    expect(find.text('周末放映室'), findsOneWidget);
  });

  testWidgets('room list reports unavailable service and can recover', (
    tester,
  ) async {
    await login(tester, unavailable: true);
    expect(find.textContaining('服务暂时不可用'), findsOneWidget);
    failList = false;
    await tester.tap(find.text('重新加载房间'));
    await tester.pumpAndSettle();
    expect(find.text('第一场，从这里开始。'), findsOneWidget);
  });

  testWidgets(
    'small screen with large text stays scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await login(tester);
      await tester.tap(find.text('邀请加入'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
