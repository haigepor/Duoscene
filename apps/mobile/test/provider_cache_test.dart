import 'dart:convert';

import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:duoscene/features/catalog/providers/whisklet_codec.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Details {
  _Details({DateTime Function()? now, int capacity = 24}) {
    provider = WhiskletProvider(
      client: WhiskletClient(transport: MockClient(reply)),
      now: now,
      detailCacheCapacity: capacity,
    );
  }
  int requests = 0;
  bool fail = false;
  late final WhiskletProvider provider;

  Future<http.Response> reply(http.Request request) async {
    requests++;
    if (fail) return http.Response('{}', 503);
    final body = WhiskletCodec().decryptRequest(request.body);
    return http.Response(
      jsonEncode({
        'code': 1,
        'data': {
          'vod_info': {
            'vod_id': body['data']['id'],
            'vod_name': 'Sample',
            'vod_url_with_player': [
              {
                'code': 'direct',
                'name': 'Line',
                'url': 'one\$https://example.com/1.m3u8#two\$https://example.com/2.m3u8',
              },
            ],
          },
        },
      }),
      200,
    );
  }
}

void main() {
  test('detail then episode changes reuse one validated directory', () async {
    final source = _Details();
    addTearDown(source.provider.close);
    await source.provider.detail('whisklet:42');
    for (final episode in [1, 2, 1, 2]) {
      final result = await source.provider.resolve(
        'whisklet:42',
        episode: episode,
        lineCode: 'direct',
      );
      expect(result.identity, 'whisklet:42:direct:$episode');
      expect(result.uri.path, '/$episode.m3u8');
    }
    expect(source.requests, 1);
  });

  test('concurrent detail consumers share validated immutable data', () async {
    final source = _Details();
    addTearDown(source.provider.close);
    final details = await Future.wait([
      for (var i = 0; i < 8; i++) source.provider.detail('whisklet:42'),
    ]);
    expect(source.requests, 1);
    expect(details.every((value) => identical(value, details.first)), isTrue);
    expect(() => details.first.lines.clear(), throwsUnsupportedError);
    expect(
      () => details.first.lines.first.episodes.clear(),
      throwsUnsupportedError,
    );
  });

  test('failed requests merge but do not poison the next attempt', () async {
    final source = _Details()..fail = true;
    addTearDown(source.provider.close);
    await Future.wait([
      for (var i = 0; i < 4; i++)
        expectLater(
          source.provider.detail('whisklet:42'),
          throwsA(isA<ProviderException>()),
        ),
    ]);
    expect(source.requests, 1);
    source.fail = false;
    expect(
      (await source.provider.detail('whisklet:42')).film.id,
      'whisklet:42',
    );
    expect(source.requests, 2);
  });

  test('different content identities never share a directory', () async {
    final source = _Details();
    addTearDown(source.provider.close);
    final values = await Future.wait([
      source.provider.detail('whisklet:42'),
      source.provider.detail('whisklet:43'),
    ]);
    expect(values.map((value) => value.film.id), [
      'whisklet:42',
      'whisklet:43',
    ]);
    expect(source.requests, 2);
  });

  test('closing a provider rejects access to cached content', () async {
    final source = _Details();
    await source.provider.detail('whisklet:42');
    source.provider.close();
    await expectLater(
      source.provider.detail('whisklet:42'),
      throwsA(isA<ProviderException>()),
    );
  });

  test(
    'directory expires after thirty seconds and explicit refresh bypasses it',
    () async {
      var now = DateTime.utc(2026, 10, 23);
      final source = _Details(now: () => now);
      addTearDown(source.provider.close);
      await source.provider.detail('whisklet:42');
      now = now.add(const Duration(seconds: 29));
      await source.provider.detail('whisklet:42');
      expect(source.requests, 1);
      now = now.add(const Duration(seconds: 1));
      await source.provider.detail('whisklet:42');
      expect(source.requests, 2);
      await source.provider.detail('whisklet:42', refresh: true);
      expect(source.requests, 3);
      now = now.subtract(const Duration(minutes: 1));
      await source.provider.detail('whisklet:42');
      expect(source.requests, 4);
    },
  );

  test('bounded directory evicts least recently used content', () async {
    final source = _Details(capacity: 2);
    addTearDown(source.provider.close);
    for (final id in [42, 43, 42, 44, 43]) {
      await source.provider.detail('whisklet:$id');
    }
    expect(source.requests, 4);
  });
}
