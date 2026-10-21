import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:duoscene/features/catalog/providers/whisklet_codec.dart';
import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:duoscene/features/catalog/media_provider.dart';

void main() {
  test('navigation options and filtered pages preserve the five-field source response', () async {
    final provider = WhiskletProvider(
      client: WhiskletClient(
        transport: MockClient((request) async {
          final payload = WhiskletCodec().decryptRequest(request.body);
          if (payload['method'] == 'nav') {
            return http.Response(
              jsonEncode({
                'code': 1,
                'data': [
                  {
                    'type_id': 1,
                    'type_name': '电影',
                    'type_extend': {'class': '喜剧,动作,喜剧', 'year': '2026,2025'},
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(payload['data'], {
            'tid': 1,
            'pg': 2,
            'limit': 20,
            'class': '喜剧',
            'year': '2026',
          });
          return http.Response(
            jsonEncode({
              'code': 1,
              'page': 2,
              'pagecount': 18,
              'data': [
                {
                  'vod_id': 600493,
                  'vod_name': '北狮南虎闯江湖',
                  'type_id': 1,
                  'vod_remarks': 'HD中字',
                  'vod_pic': 'https://example.com/poster.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    addTearDown(provider.close);
    final navigation = await provider.categories();
    expect(navigation.single.filters['class'], ['喜剧', '动作']);
    final page = await provider.browseFiltered(
      1,
      const CatalogFilter(genre: '喜剧', year: '2026'),
      page: 2,
    );
    expect(page.items.single.genre, isEmpty);
    expect(page.items.single.title, '北狮南虎闯江湖');
    expect(page.hasMore, isTrue);
  });
  test(
    'verified category filters are sent without account credentials',
    () async {
      Map<String, dynamic>? sent;
      final client = WhiskletClient(
        transport: MockClient((request) async {
          sent =
              WhiskletCodec().decryptRequest(request.body)['data']
                  as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'code': 1, 'data': <dynamic>[]}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      await client.call(WhiskletMethod.videoList, {
        'tid': 1,
        'pg': 1,
        'limit': 20,
        'class': '喜剧',
        'area': '美国',
        'lang': '英语',
        'year': '2026',
      });
      expect(sent?['class'], '喜剧');
      expect(sent?['year'], '2026');
      expect(sent?.containsKey('token'), isFalse);
      for (final extra in [
        {'sort': 'hits'},
        {'class': ''},
        {'year': 2026},
        {'area': 'a' * 201},
      ]) {
        await expectLater(
          client.call(WhiskletMethod.videoList, {
            'tid': 1,
            'pg': 1,
            'limit': 20,
            ...extra,
          }),
          throwsA(isA<ProviderException>()),
        );
      }
    },
  );
  test(
    'zero parent category falls back to actual category from detail',
    () async {
      final provider = WhiskletProvider(
        client: WhiskletClient(
          transport: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'code': 1,
                'data': {
                  'vod_info': {
                    'vod_id': 42,
                    'vod_name': 'Sample',
                    'type_id': 2,
                    'type_id_1': 0,
                    'vod_url_with_player': <dynamic>[],
                  },
                },
              }),
              200,
            ),
          ),
        ),
      );
      addTearDown(provider.close);
      expect((await provider.detail('whisklet:42')).film.kind, '电视剧');
    },
  );
  test(
    'all 17 enum methods use one encrypted endpoint and dedicated headers',
    () async {
      final codec = WhiskletCodec();
      final seen = <String>{};
      final input = <WhiskletMethod, Map<String, dynamic>>{
        WhiskletMethod.videoList: {'tid': 2, 'pg': 1, 'limit': 20},
        WhiskletMethod.search: {'text': 'sample', 'pg': 1, 'token': ''},
        WhiskletMethod.detail: {'id': 42},
        WhiskletMethod.advertDetail: {'id': 1},
        WhiskletMethod.noticeDetail: {},
        WhiskletMethod.ranks: {},
        WhiskletMethod.comments: {'vid': 42, 'token': ''},
        WhiskletMethod.danmaku: {'group_key': 'a' * 20, 'token': ''},
        WhiskletMethod.secretParse: {
          'url': 'opaque',
          'player_code': 'BBA',
          'token': '',
        },
        WhiskletMethod.heat: {'id': 42, 'token': ''},
      };
      final client = WhiskletClient(
        transport: MockClient((request) async {
          expect(request.url, WhiskletClient.endpoint);
          expect(request.headers['pk-id'], WhiskletProfile.packageId);
          expect(request.headers.containsKey('authorization'), isFalse);
          final body = codec.decryptRequest(request.body);
          seen.add(body['method'] as String);
          expect(body['csrf'], isA<int>());
          final method = WhiskletMethod.values.firstWhere(
            (method) => method.wireName == body['method'],
          );
          final Object? data = switch (method) {
            WhiskletMethod.appConfig ||
            WhiskletMethod.advert ||
            WhiskletMethod.recommend ||
            WhiskletMethod.detail ||
            WhiskletMethod.topNotice => <String, dynamic>{},
            WhiskletMethod.noticeDetail ||
            WhiskletMethod.advertDetail => '<p>sample</p>',
            WhiskletMethod.secretParse => 'A' * 800,
            WhiskletMethod.heat => null,
            _ => <dynamic>[],
          };
          return http.Response(jsonEncode({'code': 1, 'data': data}), 200);
        }),
      );
      addTearDown(client.close);
      for (final method in WhiskletMethod.values) {
        await client.call(method, input[method] ?? {'token': ''});
      }
      expect(seen.length, 17);
    },
  );
  test(
    'invalid request keys and account tokens never reach upstream',
    () async {
      var calls = 0;
      final client = WhiskletClient(
        transport: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.call(WhiskletMethod.nav, {'token': 'duoscene-account-token'}),
        throwsA(isA<ProviderException>()),
      );
      await expectLater(
        client.call(WhiskletMethod.videoList, {
          'tid': -1,
          'pg': 1,
          'limit': 20,
        }),
        throwsA(isA<ProviderException>()),
      );
      await expectLater(
        client.call(WhiskletMethod.nav, {'unsafe': 'field'}),
        throwsA(isA<ProviderException>()),
      );
      expect(calls, 0);
    },
  );
  test('request matches independent Python SDK vector', () {
    final codec = WhiskletCodec(
      key: Uint8List.fromList(List.generate(16, (index) => index)),
    );
    final wire = codec.encrypt({
      'method': 'nav',
      'data': {'token': ''},
      'csrf': 1,
    }, iv: Uint8List.fromList(List.filled(16, 34)));
    expect(
      wire,
      'IiIiIiIiIiIiIiIiIiIiIp_yhbyIp-wUY_CKbY6nPd9XVQD2RD-7AOhjuWLzu-FfoVtUP5FRDTXg_1I6iNaGpQ',
    );
    expect(codec.decryptRequest(wire)['method'], 'nav');
    expect(wire.contains('='), isFalse);
  });

  test('plaintext business errors are not reconstructed as success', () async {
    final client = WhiskletClient(
      transport: MockClient(
        (request) async => http.Response('{"code":999,"msg":"bad"}', 200),
      ),
    );
    addTearDown(client.close);
    await expectLater(client.nav(), throwsA(isA<ProviderException>()));
  });

  test('parser null data fails despite success business code', () async {
    final client = WhiskletClient(
      transport: MockClient(
        (request) async => http.Response('{"code":1,"data":null}', 200),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.secretParse('token', 'BBA'),
      throwsA(isA<ProviderException>()),
    );
  });

  test('pagination uses pagecount rather than requested page size', () async {
    final codec = WhiskletCodec();
    final provider = WhiskletProvider(
      client: WhiskletClient(
        transport: MockClient((request) async {
          final body = codec.decryptRequest(request.body);
          expect(body['method'], 'video_list');
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'code': 1,
              'page': 1,
              'pagecount': 3,
              'data': [
                {
                  'vod_id': 42,
                  'vod_name': 'Sample',
                  'type_id': 2,
                  'vod_pic': 'https://example.com/a.jpg',
                  'vod_remarks': '全5集',
                },
                {'vod_id': 42, 'vod_name': 'Sample', 'type_id': 2},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    addTearDown(provider.close);
    final page = await provider.browse(2);
    expect(page.items.single.id, 'whisklet:42');
    expect(page.hasMore, isTrue);
    expect(page.items.single.episodes, 5);
  });

  test('http token still uses parser when parse_api is present', () {
    final line = WhiskletProvider.parseLine({
      'code': 'youku',
      'name': 'Line',
      'parse_api': 'http://198.16.39.44:27264/ajiami/?url=',
      'url': '第1集\$https://example.com/page#第2集\$opaque',
    });
    expect(line.direct, isFalse);
    expect(line.episodes.length, 2);
    expect(line.episodes.first.token, 'https://example.com/page');
  });

  test('untrusted player params and credential headers are not adopted', () {
    final line = WhiskletProvider.parseLine({
      'code': 'direct',
      'name': 'Line',
      'url': '正片\$https://example.com/a.m3u8',
      'headers': {
        'Authorization': 'private',
        'Cookie': 'private',
        'Referer': 'https://example.com/',
      },
      'core_params': ['script: evil'],
    });
    expect(line.headers, {'Referer': 'https://example.com/'});
  });

  test('invalid media URL and missing detail never become playable', () async {
    final client = WhiskletClient(
      transport: MockClient(
        (request) async => http.Response('{"code":1,"data":{}}', 200),
      ),
    );
    final provider = WhiskletProvider(client: client);
    addTearDown(provider.close);
    await expectLater(
      provider.detail('whisklet:42'),
      throwsA(isA<ProviderException>()),
    );
    expect(
      () => WhiskletProvider.parseLine({
        'code': 'x',
        'url': 'one\$javascript:bad',
      }),
      throwsA(isA<ProviderException>()),
    );
  });

  test('platform retries truncated params at most eight times with selected player code', () async {
    var params = 0;
    final codec = WhiskletCodec();
    final provider = WhiskletProvider(
      client: WhiskletClient(
        transport: MockClient((request) async {
          final body = codec.decryptRequest(request.body);
          if (body['method'] == 'video_detail') {
            return http.Response(
              jsonEncode({
                'code': 1,
                'data': {
                  'vod_info': {
                    'vod_id': 42,
                    'vod_name': 'Sample',
                    'vod_url_with_player': [
                      {
                        'code': 'co',
                        'name': 'Line',
                        'parse_api': 'http://198.16.39.44:27264/ajiami/?url=',
                        'url': 'one\$opaque',
                      },
                    ],
                  },
                },
              }),
              200,
            );
          }
          expect(body['data']['player_code'], 'co');
          params++;
          return http.Response(jsonEncode({'code': 1, 'data': 'A' * 80}), 200);
        }),
      ),
    );
    addTearDown(provider.close);
    await expectLater(
      provider.resolve('whisklet:42', episode: 1, lineCode: 'co'),
      throwsA(isA<ProviderException>()),
    );
    expect(params, 8);
  });

  test(
    'stable media identity does not inherit signed URL or account headers',
    () async {
      final provider = WhiskletProvider(
        client: WhiskletClient(
          transport: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'code': 1,
                'data': {
                  'vod_info': {
                    'vod_id': 42,
                    'vod_name': 'Sample',
                    'vod_url_with_player': [
                      {
                        'code': 'direct',
                        'name': 'Line',
                        'url':
                            'one\$https://example.com/a.m3u8?signature=private',
                      },
                    ],
                  },
                },
              }),
              200,
            ),
          ),
        ),
      );
      addTearDown(provider.close);
      final source = await provider.resolve('whisklet:42', episode: 1);
      expect(source.identity, 'whisklet:42:direct:1');
      expect(source.headers, isEmpty);
      expect(source.isHls, isTrue);
    },
  );
}
