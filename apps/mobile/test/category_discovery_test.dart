import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/category_discovery.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/search_page.dart';

void main() {
  testWidgets(
    'category shares home search, preserves its kind and keeps discovery filters',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'discovery', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: WatchHome(library: library, onProfile: () {}, active: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, '电影'));
      await t.pumpAndSettle();
      expect(find.text('搜索影片、剧集'), findsOneWidget);
      expect(find.byKey(const Key('home-search')), findsOneWidget);
      expect(find.byKey(const Key('category-filter-panel')), findsNothing);
      expect(find.byKey(const Key('category-picks')), findsOneWidget);
      final grid = t.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      await t.tap(find.byKey(const Key('category-filter-toggle')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('category-genre-科幻')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('category-picks')), findsNothing);
      expect(find.byKey(const Key('category-film-mountains')), findsNothing);
      expect(find.byKey(const Key('category-film-stars')), findsOneWidget);
      await t.tap(find.byKey(const Key('category-filter-toggle')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('category-filter-panel')), findsNothing);
      expect(find.textContaining('科幻'), findsWidgets);
      await t.tap(find.byKey(const Key('category-film-stars')));
      await t.pumpAndSettle();
      expect(t.widget<DetailPage>(find.byType(DetailPage)).film.id, 'stars');
      Navigator.of(t.element(find.byType(DetailPage))).pop();
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.byKey(const Key('home-search'))),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('home-search')));
      await t.pumpAndSettle();
      expect(t.widget<SearchPage>(find.byType(SearchPage)).initialKind, '电影');
      Navigator.of(t.element(find.byType(SearchPage))).pop();
      await t.pumpAndSettle();
      for (final kind in ['电视剧', '动漫', '短剧', '推荐']) {
        await t.tap(find.widgetWithText(TextButton, kind));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('home-search')));
        await t.pumpAndSettle();
        expect(
          t.widget<SearchPage>(find.byType(SearchPage)).initialKind,
          kind == '推荐' ? isNull : kind,
        );
        Navigator.of(t.element(find.byType(SearchPage))).pop();
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  test('filters honor real boundaries, unique IDs and stable sort', () {
    final selection = CatalogSelection();
    final source = [
      const Film('a', 'A', '电影', '剧情', 100),
      const Film('b', 'B', '电影', '科幻', 101),
      const Film('c', 'C', '电影', '科幻', 120),
      const Film('d', 'D', '电影', '科幻', 121),
      const Film('d', '重复', '电影', '科幻', 121),
      const Film('e', 'E', '短剧', '情感', 2, episodes: 40),
      const Film('f', 'F', '短剧', '悬疑', 3, episodes: 20),
    ];
    expect(selection.results(source, '电影').length, 4);
    selection.length = 1;
    expect(selection.results(source, '电影').map((f) => f.id), ['a']);
    selection.length = 2;
    expect(selection.results(source, '电影').map((f) => f.id), ['b', 'c']);
    selection.length = 3;
    expect(selection.results(source, '电影').map((f) => f.id), ['d']);
    selection.reset();
    selection.genre = '剧情';
    selection.length = 3;
    expect(selection.results(source, '电影'), isEmpty);
    selection.reset();
    selection.length = 1;
    expect(selection.results(source, '短剧').map((f) => f.id), ['e']);
    selection.length = 2;
    expect(selection.results(source, '短剧').map((f) => f.id), ['f']);
    selection.reset();
    selection.sort = 2;
    expect(selection.results(source.reversed, '电影').map((f) => f.id), [
      'a',
      'b',
      'c',
      'd',
    ]);
    selection.reset();
    expect(selection.filtered, isFalse);
    expect(selection.limit, CatalogSelection.pageSize);
  });

  testWidgets(
    'picks change locally and finite pages append without duplicates',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'discovery-pages', preview: true);
      final selection = CatalogSelection();
      final items = [
        for (var i = 0; i < 40; i++)
          Film(
            'item-$i',
            '影片 $i',
            '电影',
            '剧情',
            100 + i,
            art: 'poster-mountains',
          ),
      ];
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: CatalogDiscovery(
              library: library,
              kind: '电影',
              selection: selection,
              header: const SizedBox(height: 48),
              items: items,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = t.state<ScrollableState>(scrollable).position;
      expect(selection.limit, 12);
      expect(find.byKey(const ValueKey('pick-item-0')), findsOneWidget);
      final offset = position.pixels;
      await t.tap(find.byKey(const Key('category-refresh-picks')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-item-0')), findsNothing);
      expect(find.byKey(const ValueKey('pick-item-4')), findsOneWidget);
      expect(position.pixels, offset);
      for (var i = 0; i < 5; i++) {
        position.jumpTo(position.maxScrollExtent);
        await t.pumpAndSettle();
      }
      expect(selection.limit, 40);
      expect(find.byKey(const Key('category-film-item-39')), findsOneWidget);
      expect(find.text('已经到底了'), findsOneWidget);
      position.jumpTo(position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(selection.limit, 40);
      position.jumpTo(0);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('category-filter-toggle')));
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.byKey(const Key('category-length-3'))),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('category-length-3')));
      await t.pumpAndSettle();
      expect(selection.limit, 12);
      expect(find.byKey(const Key('category-film-item-0')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
