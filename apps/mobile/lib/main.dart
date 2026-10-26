import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app/duoscene_app.dart';
import 'core/performance_capture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && const bool.fromEnvironment('PERF_CAPTURE'))
    startPerformanceCapture();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Lucide icons',
    ], await rootBundle.loadString('assets/design/icons/LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Libre Baskerville',
    ], await rootBundle.loadString('assets/design/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Zhi Mang Xing',
    ], await rootBundle.loadString('assets/design/fonts/ZhiMangXing-OFL.txt'));
    yield LicenseEntryWithLineBreaks(
      ['Playra player'],
      await rootBundle.loadString('assets/design/licenses/Playra-GPL-3.0.txt'),
    );
  });
  runApp(const DuosceneApp());
  // 后台 isolate 预热 libmpv：dlopen 有进程级缓存，UI isolate 首次打开视频时
  // 直接命中。低端机冷启后点开视频曾实测卡住主线程数秒（292 帧跳帧）。
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    Timer(const Duration(seconds: 3), () async {
      try {
        await Isolate.run(() {
          try {
            MediaKit.ensureInitialized();
          } catch (_) {}
        });
      } catch (_) {}
    });
  }
}
