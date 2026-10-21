import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

Map<String, num> frameStatistics(List<int> samples) {
  if (samples.isEmpty) return {'count': 0};
  final sorted = List<int>.of(samples)..sort();
  int percentile(double fraction) =>
      sorted[(sorted.length * fraction).ceil() - 1];
  return {
    'count': sorted.length,
    'p50Us': percentile(.5),
    'p95Us': percentile(.95),
    'p99Us': percentile(.99),
    'maxUs': sorted.last,
    'above16667Us': sorted.where((value) => value > 16667).length,
  };
}

void startPerformanceCapture() {
  if (kReleaseMode) return;
  final clock = Stopwatch()..start();
  final frames = <Map<String, int>>[];
  void collect(List<FrameTiming> batch) {
    for (final frame in batch) {
      if (frames.length >= 5000) break;
      frames.add({
        'callbackUs': clock.elapsedMicroseconds,
        'vsyncUs': frame.timestampInMicroseconds(FramePhase.vsyncStart),
        'buildUs': frame.buildDuration.inMicroseconds,
        'rasterUs': frame.rasterDuration.inMicroseconds,
        'spanUs': frame.totalSpan.inMicroseconds,
      });
    }
  }

  final startedAt = DateTime.now().toUtc().toIso8601String();
  SchedulerBinding.instance.addTimingsCallback(collect);
  Timer(const Duration(seconds: 40), () async {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    final report = {
      'mode': kProfileMode ? 'profile' : 'debug',
      'startedAt': startedAt,
      'windowUs': clock.elapsedMicroseconds,
      'build': frameStatistics(
        frames.map((frame) => frame['buildUs']!).toList(),
      ),
      'raster': frameStatistics(
        frames.map((frame) => frame['rasterUs']!).toList(),
      ),
      'decodedImageCacheBytes':
          PaintingBinding.instance.imageCache.currentSizeBytes,
      'frames': frames,
    };
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return;
      await File('${directory.path}/duoscene-performance.json')
          .writeAsString(jsonEncode(report), encoding: utf8);
      debugPrint('DUOSCENE_PERFORMANCE_CAPTURE_READY ${frames.length}');
    } catch (error) {
      debugPrint('DUOSCENE_PERFORMANCE_CAPTURE_FAILED ${error.runtimeType}');
    }
  });
}
