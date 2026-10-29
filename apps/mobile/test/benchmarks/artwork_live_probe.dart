import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoscene/features/catalog/artwork_request.dart';
import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('read-only artwork status and HTTPS compatibility probe', () async {
    expect(const bool.fromEnvironment('ARTWORK_PROBE'), true);
    final source = WhiskletClient(), rows = <Map<String, dynamic>>[];
    try {
      for (final category in [1, 2, 4]) {
        final page = await source.videoList(category, 1);
        for (final row in (page['data'] as List).take(20)) {
          if (row is Map)
            rows.add({
              'id': row['vod_id'],
              'title': row['vod_name'],
              'rawUrl': row['vod_pic'],
            });
        }
      }
      for (final query in ['彩虹镇', '你好八斤']) {
        final page = await source.search(query, 1);
        for (final row in (page['data'] as List).take(2)) {
          if (row is Map)
            rows.add({
              'id': row['vod_id'],
              'title': row['vod_name'],
              'rawUrl': row['vod_pic'],
            });
        }
      }
    } finally {
      source.close();
    }
    var cursor = 0;
    Future<Map<String, Object?>> fetch(
      Uri uri,
      Map<String, String> headers,
    ) async {
      final client = http.Client(), watch = Stopwatch()..start();
      try {
        final response = await client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 12));
        final result = <String, Object?>{
          'host': uri.host,
          'status': response.statusCode,
          'bytes': response.bodyBytes.length,
          'ms': watch.elapsedMicroseconds / 1000,
          'contentType': response.headers['content-type'],
        };
        if (response.statusCode == 200) {
          if (response.bodyBytes.length > 4 * 1024 * 1024)
            result['error'] = 'oversize';
          else {
            final buffer = await ui.ImmutableBuffer.fromUint8List(
              response.bodyBytes,
            );
            final descriptor = await ui.ImageDescriptor.encoded(buffer);
            result['width'] = descriptor.width;
            result['height'] = descriptor.height;
            descriptor.dispose();
            buffer.dispose();
          }
        }
        return result;
      } catch (error) {
        return {
          'host': uri.host,
          'error': error.runtimeType.toString(),
          'detail': error.toString(),
          'ms': watch.elapsedMicroseconds / 1000,
        };
      } finally {
        client.close();
      }
    }

    Future<void> worker() async {
      while (cursor < rows.length) {
        final row = rows[cursor++], raw = row['rawUrl']?.toString();
        final request = ArtworkRequest.parse(raw);
        if (request != null) {
          row['current'] = await fetch(request.uri, request.headers);
          if (row['current']['status'] != 200 ||
              row['current']['error'] != null) {
            row['retry'] = await fetch(request.uri, request.headers);
            row['browserAgent'] = await fetch(request.uri, {
              ...request.headers,
              'User-Agent': ArtworkRequest.browserAgent,
            });
          }
        } else {
          row['current'] = {'error': 'url-rejected'};
          final uri = Uri.tryParse(raw ?? '');
          if (uri != null &&
              uri.scheme == 'http' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              !uri.hasFragment &&
              uri.port == 80) {
            final secure = uri.replace(scheme: 'https', port: 443);
            row['httpsCandidate'] = await fetch(secure, {});
          }
        }
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    const output = String.fromEnvironment('ARTWORK_REPORT_PATH');
    if (output.isNotEmpty)
      await File(output).writeAsString(jsonEncode(rows), encoding: utf8);
    final groups = <String, int>{};
    for (final row in rows) {
      final result = row['current'] as Map;
      final key =
          '${result['host'] ?? 'no-host'}:${result['status'] ?? result['error']}';
      groups[key] = (groups[key] ?? 0) + 1;
    }
    debugPrintSynchronously(
      'ARTWORK_PROBE:${jsonEncode({'count': rows.length, 'current': groups, 'httpsRecovered': rows.where((r) => r['httpsCandidate']?['status'] == 200).length})}',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));
}
