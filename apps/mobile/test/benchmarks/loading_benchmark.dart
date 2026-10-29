import 'dart:convert';

import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/catalog_data.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:duoscene/features/catalog/providers/whisklet_codec.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// 受控网络边界保留真实协议编码、解码和目录处理，不代表源站或解码首帧。
void main() {
  test('repeatable catalog and playback loading benchmark', () async {
    final playback = <Map<String, Object>>[];
    final catalog = <Map<String, Object>>[];
    for (var run = 0; run < 7; run++) {
      var requests = 0;
      final provider = WhiskletProvider(
        client: WhiskletClient(
          transport: MockClient((request) async {
            requests++;
            final payload = WhiskletCodec().decryptRequest(request.body);
            expect(payload['method'], 'video_detail');
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return http.Response(
              jsonEncode({
                'code': 1,
                'data': {
                  'vod_info': {
                    'vod_id': 42,
                    'vod_name': 'Benchmark',
                    'vod_url_with_player': [
                      {
                        'code': 'direct',
                        'name': 'Direct',
                        'url': [
                          for (var episode = 1; episode <= 6; episode++)
                            '$episode\$https://example.com/$episode.m3u8',
                        ].join('#'),
                      },
                    ],
                  },
                },
              }),
              200,
            );
          }),
        ),
      );
      final elapsed = Stopwatch()..start();
      await provider.detail('whisklet:42');
      final detailMs = elapsed.elapsedMicroseconds / 1000;
      for (var episode = 1; episode <= 6; episode++) {
        final source = await provider.resolve('whisklet:42', episode: episode);
        expect(source.identity, 'whisklet:42:direct:$episode');
      }
      final totalMs = elapsed.elapsedMicroseconds / 1000;
      final beforeConcurrent = requests;
      await Future.wait([
        for (var i = 0; i < 4; i++)
          provider
              .resolve('whisklet:43', episode: 1)
              .then<void>(
                (_) => fail('Wrong response identity must fail'),
                onError: (Object _) {},
              ),
      ]);
      playback.add({
        'detailMs': detailMs,
        'sixEpisodeMs': totalMs - detailMs,
        'totalMs': totalMs,
        'detailRequests': beforeConcurrent,
        'concurrentFailedRequests': requests - beforeConcurrent,
      });
      provider.close();

      final source = _CatalogSource();
      final data = CatalogData(source, (_) {});
      await data.load();
      catalog.add({
        'firstCategoryStartMs': source.firstCategoryStartMs!,
        'totalMs': source.elapsed.elapsedMicroseconds / 1000,
      });
      data.dispose();
    }
    debugPrintSynchronously(
      'PERF_RESULT:${jsonEncode({'kind': 'controlled-flutter-test-not-device', 'runs': 7, 'detailRttMs': 60, 'filterRttMs': 240, 'playback': playback, 'catalog': catalog})}',
    );
  });
}

class _CatalogSource implements FilteredMediaProvider {
  final elapsed = Stopwatch()..start();
  double? firstCategoryStartMs;
  @override
  Future<List<Film>> recommendations() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return const [];
  }

  @override
  Future<List<MediaCategory>> categories() async {
    await Future<void>.delayed(const Duration(milliseconds: 240));
    return const [MediaCategory(1, '电影')];
  }

  @override
  Future<CatalogPage> browse(int category, {int page = 1}) async {
    firstCategoryStartMs ??= elapsed.elapsedMicroseconds / 1000;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return CatalogPage(const [], page: page, pages: 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
