import 'dart:async';
import 'dart:convert';

import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStore implements TokenStore {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('unavailable');
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

Map<String, Object?> credentials(String access, String refresh) => {
  'accessToken': access,
  'refreshToken': refresh,
  'tokenType': 'Bearer',
  'expiresIn': 900,
  'user': {'id': 'owner', 'username': 'owner', 'displayName': '房主'},
};
http.Response ok(Object? data) => http.Response(
  jsonEncode({'data': data, 'requestId': 'test'}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response unauthorized() => http.Response(
  jsonEncode({
    'error': {'code': 'UNAUTHORIZED', 'message': 'Authentication required'},
    'requestId': 'test',
  }),
  401,
);

void main() {
  test(
    'late old-token 401 uses the new access without another refresh',
    () async {
      final late = Completer<http.Response>();
      var refreshes = 0;
      final session = Session(
        ApiClient(
          Uri.parse('http://127.0.0.1:3000'),
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login'))
              return ok(credentials('old', 'refresh-old'));
            if (request.url.path.endsWith('/refresh')) {
              refreshes++;
              return ok(credentials('new', 'refresh-new'));
            }
            if (request.headers['authorization'] == 'Bearer new')
              return ok({'ok': true});
            if (request.url.path.endsWith('/late')) return late.future;
            return unauthorized();
          }),
        ),
        MemoryTokenStore(),
      );
      await session.login('owner', 'password');
      final pending = session.request('GET', '/late');
      await session.request('GET', '/first');
      late.complete(unauthorized());
      expect((await pending)['ok'], isTrue);
      expect(refreshes, 1);
      session.dispose();
    },
  );

  test(
    'logout during refresh does not restore or persist the old session',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final store = MemoryTokenStore();
      var revokedFresh = false;
      final session = Session(
        ApiClient(
          Uri.parse('http://127.0.0.1:3000'),
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login'))
              return ok(credentials('old', 'refresh-old'));
            if (request.url.path.endsWith('/refresh')) {
              started.complete();
              return response.future;
            }
            if (request.url.path.endsWith('/logout') &&
                request.headers['authorization'] == 'Bearer new') {
              revokedFresh = true;
              return ok({'ok': true});
            }
            return unauthorized();
          }),
        ),
        store,
      );
      await session.login('owner', 'password');
      final pending = expectLater(
        session.request('GET', '/rooms'),
        throwsA(isA<ApiException>()),
      );
      await started.future;
      final logout = session.logout();
      response.complete(ok(credentials('new', 'refresh-new')));
      await Future.wait([pending, logout]);
      expect(session.user, isNull);
      expect(store.value, isNull);
      expect(revokedFresh, isTrue);
      session.dispose();
    },
  );

  test('ambiguous room write is never automatically retried', () async {
    var writes = 0;
    final session = Session(
      ApiClient(
        Uri.parse('http://127.0.0.1:3000'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login'))
            return ok(credentials('access', 'refresh'));
          writes++;
          throw TimeoutException('response lost');
        }),
      ),
      MemoryTokenStore(),
    );
    await session.login('owner', 'password');
    await expectLater(
      session.request('POST', '/rooms', body: {'name': 'room'}),
      throwsA(isA<ApiException>()),
    );
    expect(writes, 1);
    expect(session.user, isNotNull);
    session.dispose();
  });

  test('logout with expired access revokes the rotated session too', () async {
    final store = MemoryTokenStore();
    var revoked = false;
    var refreshes = 0;
    final session = Session(
      ApiClient(
        Uri.parse('http://127.0.0.1:3000'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login'))
            return ok(credentials('expired', 'refresh-old'));
          if (request.url.path.endsWith('/refresh')) {
            refreshes++;
            return ok(credentials('fresh', 'refresh-new'));
          }
          if (request.headers['authorization'] == 'Bearer fresh') {
            revoked = true;
            return ok({'ok': true});
          }
          return unauthorized();
        }),
      ),
      store,
    );
    await session.login('owner', 'password');
    await session.logout();
    expect(revoked, isTrue);
    expect(refreshes, 1);
    expect(store.value, isNull);
    expect(session.user, isNull);
    session.dispose();
  });

  test(
    'parallel unauthorized requests rotate once and persist the new refresh token',
    () async {
      var refreshes = 0;
      final store = MemoryTokenStore();
      final session = Session(
        ApiClient(
          Uri.parse('http://127.0.0.1:3000'),
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login'))
              return ok(credentials('old', 'refresh-old'));
            if (request.url.path.endsWith('/refresh')) {
              refreshes++;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return ok(credentials('new', 'refresh-new'));
            }
            return request.headers['authorization'] == 'Bearer new'
                ? ok({'ok': true})
                : unauthorized();
          }),
        ),
        store,
      );
      await session.login('owner', 'password');
      await Future.wait([
        session.request('GET', '/rooms'),
        session.request('GET', '/rooms'),
      ]);
      expect(refreshes, 1);
      expect(store.value, 'refresh-new');
      expect(session.user?.username, 'owner');
      session.dispose();
    },
  );

  test(
    'ambiguous refresh timeout clears saved token and does not retry it',
    () async {
      var refreshes = 0;
      final store = MemoryTokenStore()..value = 'old';
      final session = Session(
        ApiClient(
          Uri.parse('http://127.0.0.1:3000'),
          client: MockClient((_) async {
            refreshes++;
            throw TimeoutException('lost response');
          }),
        ),
        store,
      );
      await session.restore();
      expect(refreshes, 1);
      expect(store.value, isNull);
      expect(session.user, isNull);
      expect(session.notice, isNotNull);
      session.dispose();
    },
  );

  test('storage failure never publishes a logged in session', () async {
    final store = MemoryTokenStore()..failWrite = true;
    final session = Session(
      ApiClient(
        Uri.parse('http://127.0.0.1:3000'),
        client: MockClient(
          (request) async => request.url.path.endsWith('/login')
              ? ok(credentials('a', 'r'))
              : ok({'ok': true}),
        ),
      ),
      store,
    );
    await expectLater(
      session.login('owner', 'password'),
      throwsA(isA<ApiException>()),
    );
    expect(session.user, isNull);
    expect(store.value, isNull);
    session.dispose();
  });
}
