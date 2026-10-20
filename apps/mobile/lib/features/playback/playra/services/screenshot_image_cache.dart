// Ported from Playra; see third_party/playra-player/NOTICE.md.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

const screenshotThumbnailCacheWidth = 240;

void evictScreenshotImages(Uint8List bytes) {
  final image = MemoryImage(bytes);
  unawaited(image.evict());
  unawaited(
    ResizeImage.resizeIfNeeded(
      screenshotThumbnailCacheWidth,
      null,
      image,
    ).evict(),
  );
}
