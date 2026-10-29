import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android Skia 的大屏缓存预算；保留小屏默认值，不改变渲染器或画质。
class SkiaResourceBudget with WidgetsBindingObserver {
  static const maximumBytes = 192 * 1024 * 1024;
  bool _started = false, _overridden = false;
  int? _lastBytes;

  void start() {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    didChangeMetrics();
  }

  @override
  void didChangeMetrics() {
    if (!_started) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null || view.physicalSize.isEmpty) return;
    // Flutter engine shell.cc 沿用 width*height*12*4 的默认预算。
    // 先前覆盖后，小窗口仍需同步缩小，避免用户覆盖值阻止引擎回调默认值。
    final engineBytes =
        (view.physicalSize.width * view.physicalSize.height * 48).round();
    if (!_overridden && engineBytes <= maximumBytes) return;
    final bytes = engineBytes.clamp(1, maximumBytes);
    if (bytes == _lastBytes) return;
    _overridden = true;
    _lastBytes = bytes;
    unawaited(_apply(bytes));
  }

  Future<void> _apply(int bytes) async {
    try {
      // 官方 JSON 通道要求整数参数；缺失/不支持时继续使用引擎默认策略。
      // https://api.flutter.dev/flutter/services/SystemChannels/skia-constant.html
      final applied = await SystemChannels.skia.invokeMethod<bool>(
        'Skia.setResourceCacheMaxBytes',
        bytes,
      );
      if (!kReleaseMode && const bool.fromEnvironment('PERF_CAPTURE')) {
        // 仅性能采集包记录通道确认，不把总 Graphics 误认为可完全限制的缓存。
        debugPrint('DUOSCENE_SKIA_BUDGET bytes=$bytes applied=$applied');
      }
    } on MissingPluginException {
      if (_lastBytes == bytes) _lastBytes = null;
    } on PlatformException {
      if (_lastBytes == bytes) _lastBytes = null;
    }
  }

  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }
}
