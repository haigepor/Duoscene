import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../design/motion.dart';

final duosceneTheme = buildDuosceneTheme(DSPalette.light);
final duosceneDarkTheme = buildDuosceneTheme(DSPalette.dark);

Widget themeSystemBars(BuildContext context, Widget? child) {
  final p = DSPalette.of(context);
  final light = Theme.of(context).brightness == Brightness.light;
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      statusBarColor: p.bg,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: p.bg,
      systemNavigationBarIconBrightness: light
          ? Brightness.dark
          : Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

ThemeData buildDuosceneTheme(DSPalette p) => ThemeData(
  useMaterial3: true,
  extensions: [p],
  brightness: p == DSPalette.light ? Brightness.light : Brightness.dark,
  visualDensity: VisualDensity.standard,
  materialTapTargetSize: MaterialTapTargetSize.padded,
  // 统一关闭点击、悬停和聚焦的墨水背景；选中图标与文字颜色仍表达状态。
  splashFactory: NoSplash.splashFactory,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  focusColor: Colors.transparent,
  colorScheme: ColorScheme.fromSeed(
    seedColor: p.primary,
    brightness: p == DSPalette.light ? Brightness.light : Brightness.dark,
    primary: p.primary,
    onPrimary: p.onPrimary,
    surface: p.panel,
    error: p.error,
    onSurfaceVariant: p.muted,
    outline: p.outline,
    primaryContainer: p.tint,
    onPrimaryContainer: p.onTint,
    onSurface: p.ink,
  ),
  scaffoldBackgroundColor: p.bg,
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: p.primary,
    selectionColor: p.tint,
    selectionHandleColor: p.primary,
  ),
  iconTheme: IconThemeData(size: DS.iconSize, color: p.ink),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: DSPageTransitions(),
      TargetPlatform.windows: DSPageTransitions(),
      TargetPlatform.linux: DSPageTransitions(),
    },
  ),
  textTheme: const TextTheme(
    headlineSmall: DS.heading,
    headlineMedium: DS.heading,
    titleLarge: DS.section,
    bodyMedium: TextStyle(fontSize: DS.bodySize, height: 1.4),
    bodyLarge: TextStyle(fontSize: 14, height: 1.4),
    bodySmall: TextStyle(fontSize: DS.captionSize, height: 1.4),
    titleMedium: TextStyle(fontSize: 15, height: 1.4),
    titleSmall: TextStyle(fontSize: 13, height: 1.4),
    labelLarge: TextStyle(fontSize: 13, height: 1.2),
  ).apply(bodyColor: p.ink, displayColor: p.ink),
  dividerColor: p.line,
  dividerTheme: DividerThemeData(color: p.line, thickness: .7, space: 1),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: p.panel,
    modalBackgroundColor: p.panel,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: const Radius.circular(DS.radiusSheet),
      ),
    ),
  ),
  sliderTheme: SliderThemeData(
    overlayColor: Colors.transparent,
    activeTrackColor: p.primary,
    thumbColor: p.primary,
    inactiveTrackColor: p.line,
    trackHeight: 2,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: p.bg,
    centerTitle: false,
    titleTextStyle: DS.toolbar.copyWith(color: p.ink),
    toolbarHeight: DS.toolbarHeight,
    surfaceTintColor: Colors.transparent,
    foregroundColor: p.ink,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: p.panel,
    titleTextStyle: DS.heading,
    contentTextStyle: DS.body,
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      overlayColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      textStyle: DS.label,
      minimumSize: const Size(48, 48),
    ),
  ),
  iconButtonTheme: const IconButtonThemeData(
    style: ButtonStyle(
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    ),
  ),
  elevatedButtonTheme: const ElevatedButtonThemeData(
    style: ButtonStyle(
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    ),
  ),
  switchTheme: const SwitchThemeData(
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
  ),
  checkboxTheme: const CheckboxThemeData(
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
  ),
  radioTheme: const RadioThemeData(
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
  ),
  expansionTileTheme: const ExpansionTileThemeData(
    tilePadding: EdgeInsets.symmetric(horizontal: 12),
    childrenPadding: EdgeInsets.zero,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: p.panel,
    border: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: p.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DS.radiusMedium),
      borderSide: BorderSide(color: p.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DS.radiusMedium),
      borderSide: BorderSide(color: p.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      overlayColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DS.radiusMedium),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      overlayColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DS.radiusMedium),
      ),
    ),
  ),
);
