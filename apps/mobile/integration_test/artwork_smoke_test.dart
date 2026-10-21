import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:duoscene/features/catalog/artwork_request.dart';
import 'package:duoscene/features/catalog/artwork_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native artwork response and full image decoding', (
    tester,
  ) async {
    final results = <Map<String, Object?>>[];
    for (final url in [
      'https://img2.doubanio.com/view/photo/s_ratio_poster/public/p2936709341.jpg',
      'http://m.ykimg.com/058400006AD1B9FD13FA2B1479067535',
    ]) {
      final policy = ArtworkRequest.parse(url)!;
      final result = <String, Object?>{'host': policy.uri.host};
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      try {
        final request = await client
            .getUrl(policy.uri)
            .timeout(const Duration(seconds: 12));
        policy.headers.forEach(request.headers.set);
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        result['status'] = response.statusCode;
        result['type'] = response.headers.contentType?.mimeType;
        final bytes = BytesBuilder(copy: false);
        await for (final part in response.timeout(
          const Duration(seconds: 12),
        )) {
          if (bytes.length + part.length > 2 * 1024 * 1024)
            throw StateError('image too large');
          bytes.add(part);
        }
        result['bytes'] = bytes.length;
        if (response.statusCode == 200) {
          final codec = await ui.instantiateImageCodec(bytes.takeBytes());
          final frame = await codec.getNextFrame();
          result['width'] = frame.image.width;
          result['height'] = frame.image.height;
          frame.image.dispose();
          codec.dispose();
        }
      } catch (error) {
        result['errorType'] = error.runtimeType.toString();
      } finally {
        client.close(force: true);
      }
      results.add(result);
    }
    binding.reportData = {'artwork': results};
    final policy = ArtworkRequest.parse(
      'https://img2.doubanio.com/view/photo/s_ratio_poster/public/p2936709341.jpg',
    )!;
    final completed = Completer<void>();
    final stream = NetworkImage(
      policy.uri.toString(),
      headers: policy.headers,
    ).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    final network = <String, Object?>{};
    listener = ImageStreamListener(
      (image, _) {
        network['width'] = image.image.width;
        image.dispose();
        completed.complete();
      },
      onError: (Object error, StackTrace? stack) {
        network['errorType'] = error.runtimeType.toString();
        if (error is NetworkImageLoadException)
          network['status'] = error.statusCode;
        completed.complete();
      },
    );
    stream.addListener(listener);
    try {
      await completed.future.timeout(const Duration(seconds: 18));
    } finally {
      stream.removeListener(listener);
    }
    binding.reportData!['networkImage'] = network;
    debugPrint('ARTWORK_NATIVE_PROOF ${jsonEncode(results)}');
    debugPrint('NETWORK_IMAGE_PROOF ${jsonEncode(network)}');
    final fixed = Completer<int>();
    final fixedStream = ArtworkImage(policy).resolve(ImageConfiguration.empty);
    final fixedListener = ImageStreamListener(
      (image, _) {
        fixed.complete(image.image.width);
        image.dispose();
      },
      onError: (Object error, StackTrace? stack) =>
          fixed.completeError(error, stack),
    );
    fixedStream.addListener(fixedListener);
    try {
      final width = await fixed.future.timeout(const Duration(seconds: 18));
      binding.reportData!['fixedImageWidth'] = width;
      debugPrint('FIXED_IMAGE_WIDTH $width');
      expect(width, greaterThan(0));
    } finally {
      fixedStream.removeListener(fixedListener);
    }
    expect(results.first['width'], greaterThan(0));
  });
}
