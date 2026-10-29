import 'dart:async';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/experience/invite_pages.dart';
import 'package:duoscene/features/realtime/room_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'app_test.dart' show roomJson;
import 'session_test.dart' show MemoryTokenStore, credentials, ok;

Future<void> _settleConnection(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // StreamSubscription.cancel 的完成来自真实事件队列，须先排空再检查异步按钮状态。
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

class _HandoffConnection extends RoomConnection {
  _HandoffConnection(
    super.auth,
    super.roomId,
    this.initialized,
    this.log, {
    this.fail = false,
  });
  final Completer<void> initialized;
  final List<String> log;
  final bool fail;
  Map<String, dynamic>? selection;
  @override
  Future<void> connect() async {
    connected = true;
    snapshot = {'type': 'snapshot', 'media': null};
    events.add(snapshot!);
  }

  @override
  Future<void> command(
    String type, [
    Map<String, dynamic> values = const {},
  ]) async {
    selection = values;
    if (fail) throw StateError('not saved');
    await initialized.future;
    log.add('initialized');
    snapshot = {'media': values['media']};
  }
}

void main() {
  testWidgets(
    'share waits for media initialization and retries without another room',
    (tester) async {
      final log = <String>[];
      final session = Session(
        ApiClient(
          Uri.parse('http://localhost'),
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login'))
              return ok(credentials('a', 'r'));
            if (request.url.path.endsWith('/rooms')) {
              log.add('create');
              return ok(roomJson());
            }
            log.add('invite');
            return ok({
              'id': 'invite',
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
      await session.login('owner', 'password');
      final library = LibraryState(accountId: 'owner', session: session);
      final first = Completer<void>(), second = Completer<void>();
      final connections = <_HandoffConnection>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: InviteSheet(
                film: const Film('whisklet:7', 'Test film', '电视剧', '', 40),
                library: library,
                episode: 2,
                position: 42,
                lineCode: 'main',
                sourceIdentity: 'whisklet:7:actual:3',
                connectionFactory: (roomId) {
                  final connection = _HandoffConnection(
                    session,
                    roomId,
                    connections.isEmpty ? first : second,
                    log,
                    fail: connections.isEmpty,
                  );
                  connections.add(connection);
                  return connection;
                },
              ),
            ),
          ),
        ),
      );
      final copy = find.widgetWithText(OutlinedButton, '复制邀请');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();
      expect(log, ['create']);
      expect(find.text('进入同看房间'), findsNothing);
      first.complete();
      await _settleConnection(tester);
      expect(connections, hasLength(1));
      expect(tester.widget<OutlinedButton>(copy).onPressed, isNotNull);
      expect(
        log,
        ['create'],
        reason:
            'A failed initialization must never issue a shareable invitation.',
      );
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();
      expect(connections, hasLength(2));
      expect(log, ['create']);
      second.complete();
      await _settleConnection(tester);
      expect(log, ['create', 'initialized', 'invite']);
      expect(connections.last.selection!['positionMs'], 42000);
      expect(connections.last.selection!['media'], {
        'provider': 'whisklet',
        'filmId': 'whisklet:7',
        'episode': 3,
        'lineCode': 'actual',
        'identity': 'whisklet:7:actual:3',
        'title': 'Test film',
      });
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(log, ['create', 'initialized', 'invite']);
      expect(connections, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
      session.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
}
