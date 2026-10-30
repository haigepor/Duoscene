import 'dart:convert';

import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:duoscene/features/catalog/providers/whisklet_codec.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// 两线路夹具：NBY 走平台内 ajiami 解析（受截断参数噪声影响），
// Ace 走外部解析模板。与 2026-10-23 上游实测的短剧线路结构一致。
Map<String, dynamic> _detailFixture({int aceEpisodes = 2}) => {
  'code': 1,
  'data': {
    'vod_info': {
      'vod_id': 601818,
      'vod_name': 'Auto fallback fixture',
      'type_id_1': 21,
      'vod_class': '短剧',
      'vod_duration': 0,
      'vod_pic': 'https://img.example/poster.jpg',
      'vod_remarks': '2集全',
      'vod_content': '测试简介',
      'vod_url_with_player': [
        {
          'code': 'NBY',
          'name': '独家③',
          'parse_api': 'http://198.16.39.44:27264/ajiami/xmy.php/?url=',
          'url': '第1集\$NBY-ep1#第2集\$NBY-ep2',
        },
        {
          'code': 'Ace',
          'name': '独家⑤',
          'parse_api': 'http://175.24.181.180:5000/api/jiexi/common?Key=k&url=',
          'url': [
            for (var i = 1; i <= aceEpisodes; i++) 'Ace第${i}集\$Ace-ep$i',
          ].join('#'),
        },
      ],
    },
  },
};

// http.Response 默认按 latin1 编码字符串 body；夹具含中文必须显式 utf-8。
http.Response _json(Map<String, dynamic> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  Future<WhiskletProvider> providerWith(
    Future<http.Response> Function(http.Request request) handler,
  ) async {
    final provider = WhiskletProvider(
      client: WhiskletClient(
        transport: MockClient((request) => handler(request)),
      ),
    );
    return provider;
  }

  test(
    'preferred line with a persistently truncated parse param falls back to the next playable line',
    () async {
      final secretCalls = <String>[];
      final provider = await providerWith((request) async {
        if (request.method == 'GET') {
          return _json({'code': 200, 'url': 'https://cdn.example/ace-ep1.mp4'});
        }
        final call = WhiskletCodec().decryptRequest(request.body);
        if (call['method'] == 'video_detail')
          return _json(_detailFixture());
        if (call['method'] == 'secret_parse_api_url') {
          secretCalls.add((call['data'] as Map)['player_code'] as String);
          return _json({'code': 1, 'data': 'x' * 100});
        }
        fail('unexpected whisklet call: ${call['method']}');
      });
      try {
        final source = await provider.resolve('whisklet:601818', episode: 1);
        expect(source.identity, 'whisklet:601818:Ace:1');
        expect(source.uri.toString(), 'https://cdn.example/ace-ep1.mp4');
        expect(source.title, contains('独家⑤'));
        // 外部解析模板不走 secretParse；NBY 重试 8 次后换线。
        expect(secretCalls, everyElement('NBY'));
        expect(secretCalls.length, 8);
      } finally {
        provider.close();
      }
    },
  );

  test(
    'when every playable line fails the preferred line error surfaces',
    () async {
      final provider = await providerWith((request) async {
        if (request.method == 'GET') {
          return _json({'code': 500, 'msg': 'boom'});
        }
        final call = WhiskletCodec().decryptRequest(request.body);
        if (call['method'] == 'video_detail')
          return _json(_detailFixture());
        if (call['method'] == 'secret_parse_api_url')
          return _json({'code': 1, 'data': 'x' * 100});
        fail('unexpected whisklet call: ${call['method']}');
      });
      try {
        await expectLater(
          provider.resolve('whisklet:601818', episode: 1),
          throwsA(
            isA<ProviderException>()
                .having((e) => e.code, 'code', 'incomplete')
                .having(
                  (e) => e.message,
                  'message',
                  '解析参数持续不完整，请重试或换线',
                ),
          ),
        );
      } finally {
        provider.close();
      }
    },
  );

  test('transport-level failure on the preferred line is not retried cross-line', () async {
    final secretCalls = <String>[];
    final provider = await providerWith((request) async {
      if (request.method == 'GET') fail('parser must not be reached');
      final call = WhiskletCodec().decryptRequest(request.body);
      if (call['method'] == 'video_detail')
        return _json(_detailFixture());
      if (call['method'] == 'secret_parse_api_url') {
        secretCalls.add((call['data'] as Map)['player_code'] as String);
        return http.Response('upstream exploded', 500);
      }
      fail('unexpected whisklet call: ${call['method']}');
    });
    try {
      await expectLater(
        provider.resolve('whisklet:601818', episode: 1),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.code,
            'code',
            'http',
          ),
        ),
      );
      expect(secretCalls, ['NBY']);
    } finally {
      provider.close();
    }
  });

  test(
    'a requested line without the episode hands over to a line that has it',
    () async {
      final provider = await providerWith((request) async {
        if (request.method == 'GET') {
          return _json({'code': 200, 'url': 'https://cdn.example/ace-ep3.mp4'});
        }
        final call = WhiskletCodec().decryptRequest(request.body);
        if (call['method'] == 'video_detail')
          return _json(_detailFixture(aceEpisodes: 3));
        fail('unexpected whisklet call: ${call['method']}');
      });
      try {
        final source = await provider.resolve(
          'whisklet:601818',
          episode: 3,
          lineCode: 'NBY',
        );
        expect(source.identity, 'whisklet:601818:Ace:3');
      } finally {
        provider.close();
      }
    },
  );

  test('an episode no line carries stays unavailable', () async {
    final provider = await providerWith((request) async {
      final call = WhiskletCodec().decryptRequest(request.body);
      if (call['method'] == 'video_detail')
        return _json(_detailFixture());
      fail('unexpected whisklet call: ${call['method']}');
    });
    try {
      await expectLater(
        provider.resolve('whisklet:601818', episode: 9),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.code,
            'code',
            'unavailable',
          ),
        ),
      );
    } finally {
      provider.close();
    }
  });

  test(
    'qiyi and mgtv 120-char ajiami lines resolve and empty parser url falls back to backup m3u8',
    () async {
      final provider = await providerWith((request) async {
        if (request.method == 'GET') {
          if (request.url.queryParameters['url'] == 'Q' * 120) {
            // 模拟 gj2.php 返回 code: 200 但 url 为空串的场景，应继续回退。
            return _json({'code': 200, 'url': ''});
          }
          if (request.url.queryParameters['url'] == 'M' * 120) {
            return _json({
              'code': 200,
              'url': 'https://cdn.example/mgtv-ep1.m3u8',
            });
          }
          return http.Response('gateway timeout', 504);
        }
        final call = WhiskletCodec().decryptRequest(request.body);
        if (call['method'] == 'video_detail') {
          return _json({
            'code': 1,
            'data': {
              'vod_info': {
                'vod_id': 602001,
                'vod_name': 'Qiyi Mgtv Fixture',
                'type_id_1': 1,
                'vod_url_with_player': [
                  {
                    'code': 'qiyi',
                    'name': '官方②',
                    'parse_api': 'http://198.16.39.44:27264/ajiami/gj2.php/?url=',
                    'url': '正片\$https://www.iqiyi.com/v_test.html',
                  },
                  {
                    'code': 'mgtv',
                    'name': '官方③',
                    'parse_api': 'http://198.16.39.44:27264/ajiami/gj2.php/?url=',
                    'url': '正片\$https://www.mgtv.com/b/test.html',
                  },
                ],
              },
            },
          });
        }
        if (call['method'] == 'secret_parse_api_url') {
          final code = (call['data'] as Map)['player_code'] as String;
          return _json({
            'code': 1,
            'data': (code == 'qiyi' ? 'Q' : 'M') * 120,
          });
        }
        fail('unexpected whisklet call: ${call['method']}');
      });
      try {
        final source = await provider.resolve('whisklet:602001', episode: 1);
        expect(source.identity, 'whisklet:602001:mgtv:1');
        expect(source.uri.toString(), 'https://cdn.example/mgtv-ep1.m3u8');
      } finally {
        provider.close();
      }
    },
  );

  test(
    'external parser GET HTTP failure falls back to direct backup line',
    () async {
      final provider = await providerWith((request) async {
        if (request.method == 'GET') {
          return http.Response('external parser 502', 502);
        }
        final call = WhiskletCodec().decryptRequest(request.body);
        if (call['method'] == 'video_detail') {
          return _json({
            'code': 1,
            'data': {
              'vod_info': {
                'vod_id': 602002,
                'vod_name': 'Parser HTTP Fallback Fixture',
                'type_id_1': 1,
                'vod_url_with_player': [
                  {
                    'code': 'Ace',
                    'name': '独家⑤',
                    'parse_api':
                        'http://175.24.181.180:5000/api/jiexi/common?Key=k&url=',
                    'url': '正片\$Ace-ep1',
                  },
                  {
                    'code': 'lzm3u8',
                    'name': '备用①',
                    'parse_api': '',
                    'url': '正片\$https://cdn.example/lz-ep1.m3u8',
                  },
                ],
              },
            },
          });
        }
        fail('unexpected whisklet call: ${call['method']}');
      });
      try {
        final source = await provider.resolve('whisklet:602002', episode: 1);
        expect(source.identity, 'whisklet:602002:lzm3u8:1');
        expect(source.uri.toString(), 'https://cdn.example/lz-ep1.m3u8');
      } finally {
        provider.close();
      }
    },
  );
}
