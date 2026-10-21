import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/palette.dart';
import 'package:duoscene/features/experience/preview_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in <String, String>{
      'DuosceneSerif': 'LibreBaskerville-Italic.ttf',
      'DuosceneDisplay': 'ZhiMangXing-Regular.ttf',
    }.entries) {
      await (FontLoader(
        font.key,
      )..addFont(rootBundle.load('assets/design/fonts/${font.value}'))).load();
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final theme in <String, DSPalette>{
    'light': DSPalette.light,
    'dark': DSPalette.dark,
  }.entries) {
    for (var page = 0; page < previewPages.length; page++) {
      final number = (page + 1).toString().padLeft(2, '0');
      testWidgets('original ${theme.key} $number ${previewPages[page]}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const captureKey = ValueKey('original-style-capture');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDuosceneTheme(theme.value),
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => RepaintBoundary(
              key: captureKey,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.noScaling,
                  disableAnimations: true,
                ),
                child: child!,
              ),
            ),
            home: PreviewHost(page: page),
          ),
        );
        await tester.pumpAndSettle();
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        await tester.runAsync(() async {
          for (final image in images) {
            await precacheImage(
              image.image,
              tester.element(find.byKey(captureKey)),
            );
          }
        });
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(captureKey),
          matchesGoldenFile(
            'goldens/${{1, 6, 9}.contains(page) ? 'short_feed_refinement' : 'style_reference'}/${theme.key}-$number.png',
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
