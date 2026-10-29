import 'dart:convert';

import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;

// 仅手动运行；读取真实元数据，不输出片目、请求头或媒体 URL，不打开媒体。
void main() {
  test('read-only live source timing probe', () async {
    expect(
      const bool.fromEnvironment('LIVE_PROVIDER_PROBE'),
      isTrue,
      reason: 'Pass --dart-define=LIVE_PROVIDER_PROBE=true explicitly',
    );
    final samples = <Map<String, Object>>[];
    for (var run = 0; run < 3; run++) {
      final provider = WhiskletProvider();
      final watch = Stopwatch()..start();
      final result = <String, Object>{'run': run + 1};
      var stage = 'recommendations';
      try {
        final recommendations = await provider.recommendations();
        result['recommendationsMs'] = watch.elapsedMicroseconds / 1000;
        result['recommendationCount'] = recommendations.length;
        stage = 'browse';
        watch.reset();
        final page = await provider.browse(1);
        result['browseMs'] = watch.elapsedMicroseconds / 1000;
        result['pageCount'] = page.items.length;
        if (page.items.isEmpty) throw StateError('No source data');
        stage = 'detailCold';
        watch.reset();
        final detail = await provider.detail(page.items.first.id);
        result['detailColdMs'] = watch.elapsedMicroseconds / 1000;
        result['lineCount'] = detail.lines.length;
        stage = 'detailWarm';
        watch.reset();
        final cached = await provider.detail(page.items.first.id);
        expect(identical(detail, cached), isTrue);
        result['detailWarmMs'] = watch.elapsedMicroseconds / 1000;
        result['status'] = 'ok';
      } catch (error) {
        result['status'] = 'failed';
        result['stage'] = stage;
        result['elapsedMs'] = watch.elapsedMicroseconds / 1000;
        result['errorCode'] = error is ProviderException
            ? error.code
            : error.runtimeType.toString();
      } finally {
        provider.close();
      }
      samples.add(result);
    }
      debugPrintSynchronously(
      'PERF_RESULT:${jsonEncode({'kind': 'live-metadata-not-media', 'samples': samples})}',
    );
    expect(
      samples.every((sample) => sample['status'] == 'ok'),
      isTrue,
      reason: 'Live upstream failures must remain visible in the report',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
