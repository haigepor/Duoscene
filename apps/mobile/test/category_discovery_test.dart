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
      expect(find.byKey(const Key('category-filter-panel')), findsOneWidget);
      expect(find.byKey(const Key('category-picks')), findsOneWidget);
      final grid = t.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      await t.tap(find.byKey(const Key('category-genre-科幻')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('category-picks')), findsNothing);
      expect(find.byKey(const Key('category-film-mountains')), findsNothing);
      expect(find.byKey(const Key('category-film-stars')), findsOneWidget);
      expect(find.byKey(const Key('category-filter-panel')), findsOneWidget);
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

  testWidgets(
    'remote bottom auto-loads, retries failures and chains while parked',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'discovery-remote', preview: true);
      final selection = CatalogSelection();
      Film film(int i) => Film(
        'item-$i',
        '影片 $i',
        '电影',
        '剧情',
        100 + i,
        art: 'poster-mountains',
      );
      var items = [for (var i = 0; i < 12; i++) film(i)];
      // 计数器放可变容器里：闭包内自增不违反 prefer_final_locals。
      final loads = <int>[0];
      final hasMore = true;
      String? error;

      Future<void> rebuild() => t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: CatalogDiscovery(
              library: library,
              kind: '电影',
              selection: selection,
              header: const SizedBox(height: 48),
              items: items,
              hasMore: hasMore,
              error: error,
              onLoadMore: () => loads[0]++,
            ),
          ),
        ),
      );

      // 确定性触底：先回顶（事件在顶部无效果），再跳到底（恰好一次触底事件）。
      // 直接 jumpTo 已在底部时不会再发滚动事件。
      Future<void> toBottom() async {
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = t.state<ScrollableState>(scrollable).position;
        position.jumpTo(0);
        await t.pumpAndSettle();
        position.jumpTo(position.maxScrollExtent);
        await t.pumpAndSettle();
      }

      await rebuild();
      await t.pumpAndSettle();

      // 触底自动拉取下一页：无需任何点击。
      await toBottom();
      expect(loads[0], 1);

      // 拉取失败：滚回底部即自动重试（error 不再拦停），底部出现内联重试。
      error = '片库加载失败，请检查网络后重试';
      await rebuild();
      await t.pumpAndSettle();
      await toBottom();
      expect(loads[0], 2);
      expect(find.byKey(const Key('category-load-retry')), findsOneWidget);
      await t.tap(find.byKey(const Key('category-load-retry')));
      await t.pumpAndSettle();
      expect(loads[0], 3);
      // 停在底部无手势：退避定时器到点自动重试。
      await t.pump(const Duration(seconds: 2));
      expect(loads[0], 4);

      // 成功但上游返回重复片目：停底也继续追拉下一页（列表引用变化触发）。
      error = null;
      items = [for (var i = 0; i < 12; i++) film(i)];
      await rebuild();
      await t.pumpAndSettle();
      expect(loads[0], 5);
      expect(find.text('继续上滑，查看更多'), findsOneWidget);

      // 成功带来新片目：停在底部无需任何手势，新页到达后直接续渲染到位
      // （item-12 已进视口；item-23 在构建缓存外，触底后才物化）。
      items = [for (var i = 0; i < 24; i++) film(i)];
      await rebuild();
      await t.pumpAndSettle();
      expect(selection.limit, 24);
      expect(find.byKey(const Key('category-film-item-12')), findsOneWidget);
      expect(loads[0], 5);
      await toBottom();
      expect(find.byKey(const Key('category-film-item-23')), findsOneWidget);
      expect(loads[0], 6);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
