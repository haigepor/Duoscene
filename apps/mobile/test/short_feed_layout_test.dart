import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/bottom_navigation.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/search_page.dart';
import 'package:duoscene/features/experience/short_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'short feed keeps white readable controls clear of the compact tab bar',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final library = LibraryState(accountId: 'short-layout', preview: true);
      for (final width in [320.0, 390.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final palette in [DSPalette.light, DSPalette.dark]) {
            t.view.physicalSize = Size(width, 760);
            await t.pumpWidget(
              MaterialApp(
                theme: buildDuosceneTheme(palette),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  extendBody: true,
                  body: ShortFeed(library: library, active: false),
                  bottomNavigationBar: DuosceneNavigation(
                    index: 1,
                    onSelect: (_) {},
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(
              t.widget<Text>(find.text(films.last.title)).style!.color,
              Colors.white,
            );
            final rail = t.getRect(find.byKey(const Key('short-action-rail')));
            final details = t.getRect(find.byKey(const Key('short-details')));
            final bar = t.getRect(find.byKey(const Key('navigation-island')));
            expect(find.byKey(const Key('short-select-video')), findsNothing);
            expect(find.text('封面预览 · 选择自己的视频'), findsNothing);
            expect(rail.center.dy, greaterThan(760 / 2));
            if (scale == 1) expect(details.height, lessThanOrEqualTo(160));
            expect(find.text('推荐'), findsNothing);
            expect(find.byTooltip('搜索短剧'), findsOneWidget);
            expect(
              t.getSize(find.byKey(const Key('short-episode-label'))).width,
              lessThanOrEqualTo(details.width),
            );
            expect(details.right, lessThan(rail.left));
            expect(details.bottom, lessThan(bar.top));
            expect(rail.bottom, lessThan(bar.top));
            if (scale == 1) expect(bar.height, lessThanOrEqualTo(50));
            expect(
              t.getSize(find.byKey(const Key('tab-1'))).height,
              greaterThanOrEqualTo(48),
            );
          }
        }
      }
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'short feed retains favorite and episode selection and searches short dramas',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final library = LibraryState(accountId: 'short-actions');
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(body: ShortFeed(library: library, active: false)),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('short-favorite')));
      await t.pumpAndSettle();
      expect(library.favorites, contains(films.last.id));
      await t.tap(find.byKey(const Key('short-episodes')));
      await t.pumpAndSettle();
      await t.tap(find.text('09'));
      await t.pumpAndSettle();
      expect(find.text('第 9 集 · 共 ${films.last.episodes} 集'), findsOneWidget);
      await t.tap(find.byTooltip('搜索短剧'));
      await t.pumpAndSettle();
      expect(t.widget<SearchPage>(find.byType(SearchPage)).initialKind, '短剧');
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
