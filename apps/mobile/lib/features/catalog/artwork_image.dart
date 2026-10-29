import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'artwork_request.dart';

class ArtworkImage extends ImageProvider<ArtworkImage> {
  const ArtworkImage(this.request);
  final ArtworkRequest request;
  @override
  Future<ArtworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  // 共享 Client：海报网格一次十几张图，keep-alive 复用连接，避免每图一条 TLS 握手。
  static final http.Client _sharedClient = http.Client();

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final client = _sharedClient;
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 12), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      // IOClient 使用 headers.set，避免 NetworkImage 的 add 把默认 Dart UA 追加进浏览器 UA。
      final message = http.AbortableRequest(
        'GET',
        request.uri,
        abortTrigger: abort.future,
      )..headers.addAll(request.headers);
      final response = await client
          .send(message)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200)
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: request.uri,
        );
      final bytes = BytesBuilder(copy: false);
      await for (final part in response.stream.timeout(
        const Duration(seconds: 12),
      )) {
        if (bytes.length + part.length > 4 * 1024 * 1024)
          throw StateError('Artwork exceeds byte limit');
        bytes.add(part);
      }
      return await decode(
        await ui.ImmutableBuffer.fromUint8List(bytes.takeBytes()),
      );
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ArtworkImage &&
      other.request.uri == request.uri &&
      mapEquals(other.request.headers, request.headers);
  @override
  int get hashCode => Object.hash(
    request.uri,
    request.headers['User-Agent'],
    request.headers['Referer'],
  );
}
