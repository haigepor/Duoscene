import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/palette.dart';
import 'package:duoscene/design/theme_preferences.dart';
import 'package:duoscene/features/experience/preview_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'preferences persist, migrate forest and serialize rapid changes',
    () async {
      SharedPreferences.setMockInitialValues({'duoscene.library.v1.old': '{}'});
      final preferences = ThemePreferences();
      await preferences.restore();
      expect(preferences.selected, DSTheme.forest);
      final first = preferences.change(theme: DSTheme.sky);
      final second = preferences.change(brightness: ThemeMode.dark);
      await Future.wait([first, second]);
      final restored = ThemePreferences();
      await restored.restore();
      expect(restored.selected, DSTheme.sky);
      expect(restored.mode, ThemeMode.dark);
      restored.dispose();
      preferences.dispose();
    },
  );
  testWidgets('theme change retains route and user input state', (t) async {
    var palette = DSPalette.light;
    late StateSetter change;
    final controller = TextEditingController();
    await t.pumpWidget(
      StatefulBuilder(
        builder: (_, update) {
          change = update;
          return MaterialApp(
            theme: buildDuosceneTheme(palette),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          Scaffold(body: TextField(controller: controller)),
                    ),
                  ),
                  child: const Text('进入'),
                ),
              ),
            ),
          );
        },
      ),
    );
    await t.tap(find.text('进入'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '保留输入');
    final original = t.element(find.byType(TextField));
    for (final theme in [DSPalette.dark, DSPalette.woodland, DSPalette.light]) {
      change(() => palette = theme);
      await t.pumpAndSettle();
      expect(identical(t.element(find.byType(TextField)), original), isTrue);
      expect(controller.text, '保留输入');
      expect(DSPalette.of(t.element(find.byType(TextField))).bg, theme.bg);
    }
    await t.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('all 18 pages support sky light dark and forest at 200 percent', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    for (final viewport in [
      (width: 320.0, scale: 2.0), (width: 390.0, scale: 2.0), (width: 430.0, scale: 1.6),
    ]) {
    t.view.physicalSize = Size(viewport.width, 844);
    for (final palette in [
      DSPalette.light,
      DSPalette.dark,
      DSPalette.woodland,
    ]) {
      for (var page = 0; page < 18; page++) {
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildDuosceneTheme(palette),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.scale)),
              child: child!,
            ),
            home: PreviewHost(page: page),
          ),
        );
        await t.pumpAndSettle();
        expect(
          t.takeException(),
          isNull,
          reason: '${viewport.width}/${viewport.scale} ${palette.forest}/${palette.bg} page ${page + 1}',
        );
      }
    }
    }
    await t.pumpWidget(const SizedBox());
  });
}
