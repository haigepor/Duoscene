import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/palette.dart';
import 'package:duoscene/design/theme_preferences.dart';
import 'package:duoscene/features/experience/appearance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget appearance(
  ThemePreferences preferences, {
  double scale = 1,
  bool disableAnimations = false,
  Key? key,
}) => ThemePreferencesScope(
  preferences: preferences,
  child: ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => MaterialApp(
      key: key,
      theme: buildDuosceneTheme(
        preferences.mode == ThemeMode.dark ? DSPalette.dark : DSPalette.light,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: const AppearancePage(),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'appearance choices persist and retain the page while switching',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = ThemePreferences();
      await preferences.restore();
      await tester.pumpWidget(appearance(preferences));
      await tester.pumpAndSettle();
      final page = tester.element(find.byType(AppearancePage));

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(preferences.mode, ThemeMode.dark);
      expect(find.text('森林'), findsNothing);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(
        identical(page, tester.element(find.byType(AppearancePage))),
        isTrue,
      );

      final restored = ThemePreferences();
      await restored.restore();
      expect(restored.selected, DSTheme.sky);
      expect(restored.mode, ThemeMode.dark);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      preferences.dispose();
      restored.dispose();
    },
  );

  testWidgets('appearance stays usable across themes widths and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = ThemePreferences();
    await preferences.restore();
    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final scale in [1.0, 2.0]) {
        for (final (theme, mode) in [
          (DSTheme.sky, ThemeMode.light),
          (DSTheme.sky, ThemeMode.dark),
        ]) {
          await preferences.change(theme: theme, brightness: mode);
          await tester.pumpWidget(
            appearance(preferences, scale: scale, key: UniqueKey()),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$width/$scale/$theme/$mode',
          );
          await tester.drag(
            find.byType(ListView).first,
            const Offset(0, -1800),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.textContaining('自动保存'));
          expect(tester.takeException(), isNull);
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    preferences.dispose();
  });

  testWidgets('brightness thumb moves continuously and reverses mid-flight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = ThemePreferences();
    await preferences.restore();
    final thumb = find.byKey(const Key('appearance-mode-indicator'));
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        appearance(preferences, scale: scale, key: UniqueKey()),
      );
      await tester.pumpAndSettle();
      final start = tester.getRect(thumb);
      await preferences.change(brightness: ThemeMode.dark);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final middle = tester.getRect(thumb);
      expect(
        scale == 1 ? middle.left : middle.top,
        greaterThan(scale == 1 ? start.left : start.top),
      );
      await preferences.change(brightness: ThemeMode.system);
      await tester.pump();
      final reversed = tester.getRect(thumb);
      expect(reversed.left, closeTo(middle.left, .01));
      expect(reversed.top, closeTo(middle.top, .01));
      await tester.pumpAndSettle();
      expect(tester.getRect(thumb), start);
      await preferences.change(brightness: ThemeMode.dark);
      await tester.pumpAndSettle();
      final end = tester.getRect(thumb);
      expect(
        scale == 1 ? middle.left : middle.top,
        lessThan(scale == 1 ? end.left : end.top),
      );
      await preferences.change(brightness: ThemeMode.system);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    preferences.dispose();
  });

  testWidgets('brightness thumb respects reduced motion in both layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = ThemePreferences();
    await preferences.restore();
    final thumb = find.byKey(const Key('appearance-mode-indicator'));
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        appearance(
          preferences,
          scale: scale,
          disableAnimations: true,
          key: UniqueKey(),
        ),
      );
      await tester.pumpAndSettle();
      final start = tester.getRect(thumb);
      await preferences.change(brightness: ThemeMode.dark);
      await tester.pump();
      await tester.pump();
      final immediate = tester.getRect(thumb);
      expect(immediate, isNot(start));
      await tester.pumpAndSettle();
      expect(tester.getRect(thumb), immediate);
      await preferences.change(brightness: ThemeMode.system);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    preferences.dispose();
  });
}
