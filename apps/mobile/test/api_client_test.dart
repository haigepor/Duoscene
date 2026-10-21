import 'dart:async';

import 'package:duoscene/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

void main() {
  test(
    'login timeout describes connectivity without room instructions',
    () async {
      var requests = 0;
      final api = ApiClient(
        Uri.parse('http://127.0.0.1:3000'),
        client: MockClient((_) async {
          requests++;
          throw TimeoutException('connection timed out');
        }),
      );
      addTearDown(api.close);

      await expectLater(
        api.request('POST', '/auth/login'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'NETWORK_ERROR')
              .having((error) => error.message, 'message', contains('服务地址'))
              .having(
                (error) => error.message,
                'message',
                isNot(contains('房间')),
              ),
        ),
      );
      expect(requests, 1);
    },
  );

  test(
    'room write timeout preserves uncertain outcome and never retries',
    () async {
      var requests = 0;
      final api = ApiClient(
        Uri.parse('http://127.0.0.1:3000'),
        client: MockClient((_) async {
          requests++;
          throw TimeoutException('response lost');
        }),
      );
      addTearDown(api.close);

      await expectLater(
        api.request('POST', '/rooms', body: {'name': 'test'}),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('刷新房间确认结果'),
          ),
        ),
      );
      expect(requests, 1);
    },
  );
}
