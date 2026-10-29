import 'dart:ui' show SemanticsAction, Tristate;

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/app_shell.dart';
import 'package:duoscene/features/catalog/category_discovery.dart';
import 'package:duoscene/features/catalog/home_content.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/collection_pages.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'tablet favorites use a lazy grid and home shelves share poster scale',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(
        accountId: 'tablet-favorites',
        preview: true,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: FavoritesPage(library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(
        t.getSize(find.byType(FilmPoster).first).width,
        inInclusiveRange(128, 176),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: AppShell(library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.getSize(find.byType(FilmPoster).first).width,
        inInclusiveRange(128, 160),
      );
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );

  testWidgets(
    'tablet navigation has actions and keeps the same tab state when resized',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final handle = t.ensureSemantics();
      final library = LibraryState(accountId: 'tablet-test', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: AppShell(library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(find.byKey(const Key('tab-3')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      final watchState = t.state(find.byType(WatchHome));
      await t.tap(find.byKey(const Key('tab-3')));
      await t.pumpAndSettle();
      final homeState = t.state(find.byType(AppShell));
      t.view.physicalSize = const Size(1280, 853);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tablet-navigation')), findsOneWidget);
      expect(t.state(find.byType(AppShell)), same(homeState));
      expect(
        t.state(find.byType(WatchHome, skipOffstage: false)),
        same(watchState),
      );
      expect(
        t
            .getSemantics(find.byKey(const Key('tab-3')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        t
            .getSemantics(find.byKey(const Key('tab-3')))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      t.view.physicalSize = const Size(480, 720);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tablet-navigation')), findsNothing);
      expect(t.state(find.byType(AppShell)), same(homeState));
      await t.pumpWidget(const SizedBox.shrink());
      handle.dispose();
      library.dispose();
    },
  );

  testWidgets(
    'tablet categories use bounded poster widths instead of three enlarged columns',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'tablet-grid', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: AppShell(library: library),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, '电影'));
      await t.pumpAndSettle();
      expect(find.byType(CatalogDiscovery), findsOneWidget);
      final grid = t.widget<SliverGrid>(find.byType(SliverGrid));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, inInclusiveRange(7, 8));
      final discovery = t.state(find.byType(CatalogDiscovery));
      t.view.physicalSize = const Size(853, 1280);
      await t.pumpAndSettle();
      expect(t.state(find.byType(CatalogDiscovery)), same(discovery));
      final portraitGrid = t.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (portraitGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        5,
      );
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );

  testWidgets(
    'wide carousel preserves portrait artwork within a composed recommendation card',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'tablet-carousel', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: AppShell(library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(HomeCarousel), findsOneWidget);
      expect(find.byKey(const Key('tablet-feature-card')), findsWidgets);
      final cover = t.getSize(
        find.byKey(const Key('tablet-feature-cover')).first,
      );
      expect(cover.width / cover.height, closeTo(.75, .01));
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );
}
