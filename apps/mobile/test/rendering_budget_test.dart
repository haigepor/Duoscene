import 'package:duoscene/app/duoscene_app.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'large Android view bounds the GPU cache and follows smaller windows',
    (t) async {
      final calls = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.skia,
        (call) async {
          calls.add(call);
          return true;
        },
      );
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();

        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.skia,
          null,
        );
      });
      t.view.physicalSize = const Size(2560, 3840);
      t.view.devicePixelRatio = 3;
      await t.pumpWidget(const DuosceneApp());
      await t.pumpAndSettle();
      expect(calls.map((v) => v.method), ['Skia.setResourceCacheMaxBytes']);
      expect(calls.single.arguments, 192 * 1024 * 1024);
      t.view.physicalSize = const Size(1800, 1200);
      await t.pumpAndSettle();
      expect(calls.last.arguments, 103680000);
      final count = calls.length;
      t.view.physicalSize = const Size(1200, 1800);
      await t.pumpAndSettle();
      expect(calls.length, count);
      await t.pumpWidget(const SizedBox.shrink());
      t.view.physicalSize = const Size(3840, 2560);
      await t.pump();
      expect(calls.length, count);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'normal phone or non-Android view keeps its existing engine policy: $platform',
      (t) async {
        final calls = <MethodCall>[];
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.skia,
          (call) async {
            calls.add(call);
            return true;
          },
        );
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();

          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.skia,
            null,
          );
        });
        t.view.physicalSize = platform == TargetPlatform.android
            ? const Size(1080, 1920)
            : const Size(2560, 3840);
        t.view.devicePixelRatio = 3;
        await t.pumpWidget(const DuosceneApp());
        await t.pumpAndSettle();
        expect(calls, isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
  testWidgets('an unavailable graphics channel never blocks guest startup', (
    t,
  ) async {
    t.view.physicalSize = const Size(2560, 3840);
    t.view.devicePixelRatio = 3;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.skia,
      (_) async => throw MissingPluginException(),
    );
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();

      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.skia,
        null,
      );
    });
    await t.pumpWidget(const DuosceneApp());
    await t.pumpAndSettle();
    expect(find.byType(WatchHome), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
