import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/experience/invite_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' show roomJson;
import 'session_test.dart' show MemoryTokenStore, credentials, ok;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('invite actions remain usable dark=$dark large=$large', (
        t,
      ) async {
        t.view.physicalSize = Size(large ? 320 : 390, 780);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              SystemChannels.platform,
              (_) async => null,
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        var creates = 0, invites = 0, revokes = 0;
        final session = Session(
          ApiClient(
            Uri.parse('http://localhost:3000'),
            client: MockClient((request) async {
              if (request.url.path.endsWith('/login')) {
                return ok(credentials('access', 'refresh'));
              }
              if (request.url.path.endsWith('/rooms')) {
                creates++;
                return ok(roomJson());
              }
              if (request.method == 'DELETE') {
                revokes++;
                return ok({'ok': true});
              }
              invites++;
              return ok({
                'id': 'invite-1',
                'token': 'A' * 43,
                'expiresAt': DateTime.now()
                    .add(const Duration(minutes: 15))
                    .toUtc()
                    .toIso8601String(),
              });
            }),
          ),
          MemoryTokenStore(),
        );
        await session.login('owner', 'correct-password');
        final library = LibraryState(accountId: 'owner', session: session);
        await t.pumpWidget(
          MaterialApp(
            theme: buildDuosceneTheme(dark ? DSPalette.dark : DSPalette.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(large ? 2 : 1),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showInvite(context, film: films.first, library: library),
                  child: const Text('打开邀请'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('打开邀请'));
        await t.pumpAndSettle();
        final copy = find.widgetWithText(OutlinedButton, '复制邀请');
        await t.ensureVisible(copy);
        await t.tap(copy);
        await t.pumpAndSettle();
        expect(creates, 1);
        expect(invites, 1);
        expect(find.textContaining('仅限一次'), findsOneWidget);
        final enter = find.widgetWithText(FilledButton, '进入同看房间');
        expect(t.widget<FilledButton>(enter).onPressed, isNotNull);
        expect(t.getSize(copy).height, greaterThanOrEqualTo(DS.touchTarget));
        expect(t.getSize(enter).height, greaterThanOrEqualTo(DS.touchTarget));
        if (large) {
          expect(t.getTopLeft(enter).dy, greaterThan(t.getBottomLeft(copy).dy));
          await t.ensureVisible(enter);
          expect(enter.hitTestable(), findsOneWidget);
        } else {
          expect(t.getTopLeft(copy).dy, closeTo(t.getTopLeft(enter).dy, 1));
          expect(t.getTopLeft(enter).dx, greaterThan(t.getTopRight(copy).dx));
          expect(find.text('撤销这份邀请').hitTestable(), findsOneWidget);
          expect(
            find.text('仅房间成员可见 · 加入后选择双方可访问的视频').hitTestable(),
            findsOneWidget,
          );
        }
        await t.ensureVisible(copy);
        await t.tap(copy);
        await t.pumpAndSettle();
        expect(invites, 1, reason: '复制应复用有效邀请');
        await t.ensureVisible(find.text('撤销这份邀请'));
        await t.tap(find.text('撤销这份邀请'));
        await t.pumpAndSettle();
        expect(revokes, 1);
        expect(find.text('撤销这份邀请'), findsNothing);
        expect(find.text('一次性邀请 · 15 分钟有效'), findsOneWidget);
        expect(find.text('进入同看房间'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        library.dispose();
        session.dispose();
      });
    }
  }
}
