import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
}
