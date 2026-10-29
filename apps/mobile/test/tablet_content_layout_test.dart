import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/scroll_chrome.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:duoscene/features/catalog/profile_page.dart';
import 'package:duoscene/features/experience/settings_pages.dart';
import 'package:duoscene/features/experience/short_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tablet account and profile constrain reading width and collection artwork',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'tablet-content', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: AccountPage(library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.getSize(find.byType(ScrollChrome)).width,
        lessThanOrEqualTo(720),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(body: ProfilePage(library: library)),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.getSize(find.byType(ScrollChrome)).width,
        lessThanOrEqualTo(960),
      );
      expect(
        t.getSize(find.byType(FilmPoster).first).width,
        lessThanOrEqualTo(160),
      );
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );

  testWidgets(
    'tablet short feed keeps a portrait viewing stage while narrow windows fill their width',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'tablet-short', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(body: ShortFeed(library: library, active: false)),
        ),
      );
      await t.pumpAndSettle();
      final stage = find.byKey(const Key('short-portrait-stage'));
      expect(stage, findsOneWidget);
      final wide = t.getSize(stage);
      expect(wide.width / wide.height, closeTo(9 / 16, .01));
      final state = t.state(find.byType(ShortFeed));
      t.view.physicalSize = const Size(390, 844);
      await t.pumpAndSettle();
      expect(t.getSize(stage).width, 390);
      expect(t.state(find.byType(ShortFeed)), same(state));
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );
}
