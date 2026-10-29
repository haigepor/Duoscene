import 'dart:async';

import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/collection_pages.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/profile_page.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:duoscene/features/catalog/catalog_data.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/catalog/category_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

class _SearchProvider implements MediaProvider {
  static const sample = Film('whisklet:42', '历史片目', '电影', '', 0);
  final requests = <String, Completer<CatalogPage>>{};
  final browsed = <int>[];
  @override
  Future<CatalogPage> browse(int category, {int page = 1}) async {
    browsed.add(category);
    return CatalogPage([films.first], page: page, pages: 2);
  }

  @override
  Future<CatalogPage> searchPage(String query, {int page = 1}) => requests
      .putIfAbsent('$query:$page', () => Completer<CatalogPage>())
      .future;
  @override
  Future<List<Film>> recommendations() async => [sample];
  @override
  Future<MediaDetail> detail(String filmId) async =>
      const MediaDetail(sample, []);
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FilterProvider extends _SearchProvider implements FilteredMediaProvider {
  final navigation = Completer<List<MediaCategory>>();
  @override
  Future<List<MediaCategory>> categories() => navigation.future;
  @override
  Future<CatalogPage> browseFiltered(
    int category,
    CatalogFilter filter, {
    int page = 1,
  }) => browse(category, page: page);
}

<<<<<<< HEAD

class _SkeletonProvider extends _SearchProvider {
  final pending = Completer<MediaDetail>();
  @override
  Future<MediaDetail> detail(String filmId) => pending.future;
=======
class _SlowHomeProvider extends _FilterProvider {
  final home = Completer<List<Film>>();
  @override
  Future<List<Film>> recommendations() => home.future;
>>>>>>> 435fea310b21dfe7c5279ea88167a6a247ec0461
}

void main() {
  test('slow filter metadata does not block category prewarming', () async {
    final provider = _FilterProvider();
    final catalog = CatalogData(provider, (_) {});
    addTearDown(catalog.dispose);
    final loading = catalog.load();
    await Future<void>.delayed(Duration.zero);
    final started = List.of(provider.browsed);
    provider.navigation.complete(const [MediaCategory(1, '电影')]);
    await loading;
    expect(started, contains(1));
  });

  test('repeated bootstrap waits for the same first-screen work', () async {
    final provider = _SlowHomeProvider();
    final catalog = CatalogData(provider, (_) {});
    addTearDown(catalog.dispose);
    final first = catalog.load();
    final second = catalog.load();
    await Future<void>.delayed(Duration.zero);
    final premature = List.of(provider.browsed);
    provider.home.complete([_SearchProvider.sample]);
    provider.navigation.complete(const [MediaCategory(1, '电影')]);
    await Future.wait([first, second]);
    expect(premature, isEmpty);
    expect(provider.browsed, [1, 2, 4, 21]);
  });

  test('concurrent feed load callers wait for the actual page', () async {
    final page = Completer<CatalogPage>();
    final feed = CatalogFeed(fetch: (_) => page.future);
    addTearDown(feed.dispose);
    final first = feed.load();
    var secondDone = false;
    final second = feed.load().then((_) => secondDone = true);
    await Future<void>.delayed(Duration.zero);
    final premature = secondDone;
    page.complete(const CatalogPage([], page: 1, pages: 1));
    await Future.wait([first, second]);
    expect(premature, isFalse);
    expect(feed.loaded, isTrue);
  });

  test('slow filter metadata does not block home recommendations', () async {
    final provider = _FilterProvider();
    final catalog = CatalogData(provider, (_) {});
    addTearDown(catalog.dispose);
    final loading = catalog.load();
    await Future<void>.delayed(Duration.zero);
    expect(catalog.home.items, [_SearchProvider.sample]);
    provider.navigation.complete(const [MediaCategory(1, '电影')]);
    await loading;
  });
  testWidgets(
    'remote filters render five-field rows and request source conditions',
    (tester) async {
      final library = LibraryState(accountId: 'filters');
      addTearDown(library.dispose);
      final selection = CatalogSelection()..genre = '喜剧';
      CatalogFilter? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: CatalogDiscovery(
              library: library,
              kind: '电影',
              selection: selection,
              header: const SizedBox(),
              remoteFilters: true,
              filterOptions: const {
                'class': ['喜剧'],
                'year': ['2026'],
              },
              onFilter: (value) => selected = value,
              items: const [_SearchProvider.sample],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('category-film-whisklet:42')),
        findsOneWidget,
      );
      expect(find.text('100 分钟以内'), findsNothing);
      await tester.tap(find.byKey(const Key('category-year-2026')));
      await tester.pumpAndSettle();
      expect(selected?.parameters, {'class': '喜剧', 'year': '2026'});
      expect(find.text('本页片名'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'filtered loading shows a skeleton grid instead of a progress bar',
    (tester) async {
      final library = LibraryState(accountId: 'catalog-skeleton');
      addTearDown(library.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: CatalogDiscovery(
              library: library,
              kind: '电影',
              selection: CatalogSelection()..genre = '喜剧',
              header: const SizedBox(),
              remoteFilters: true,
              filterOptions: const {
                'class': ['喜剧'],
              },
              items: const [],
              loading: true,
            ),
          ),
        ),
      );
      // 骨架呼吸动画常驻，不能用 pumpAndSettle
      await tester.pump();
      expect(find.byKey(const Key('catalog-skeleton')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('正在加载…'), findsNothing);
    },
  );
  test(
    'replacing a feed ignores stale success, errors and loading cleanup',
    () async {
      final oldRequest = Completer<CatalogPage>();
      final latest = Completer<CatalogPage>();
      final feed = CatalogFeed(fetch: (_) => oldRequest.future);
      addTearDown(feed.dispose);
      final old = feed.load();
      final replacement = feed.replace((_) => latest.future);
      oldRequest.completeError(StateError('old request failed'));
      await old;
      expect(feed.loading, isTrue);
      expect(feed.error, isNull);
      latest.complete(CatalogPage([films[1]], page: 1, pages: 2));
      await replacement;
      final late = Completer<CatalogPage>();
      final pending = feed.replace((_) => late.future);
      await feed.replace(
        (_) async => CatalogPage([films[2]], page: 1, pages: 1),
      );
      late.complete(CatalogPage([films[0]], page: 1, pages: 4));
      await pending;
      expect(feed.items, [films[2]]);
      expect(feed.page, 1);
      expect(feed.hasMore, isFalse);
    },
  );
  testWidgets(
    'profile favorite strip renders account snapshots in the original posters',
    (tester) async {
      final library = LibraryState(
        accountId: 'profile',
        provider: _SearchProvider(),
      );
      library.remember([_SearchProvider.sample]);
      library.favorites.add(_SearchProvider.sample.id);
      addTearDown(library.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(body: ProfilePage(library: library)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilmPoster), findsOneWidget);
      expect(
        tester.widget<FilmPoster>(find.byType(FilmPoster)).film.id,
        _SearchProvider.sample.id,
      );
      expect(
        tester.getSize(find.byType(FilmPoster)).width,
        lessThanOrEqualTo(tester.getSize(find.byType(ProfilePage)).width / 3),
      );
    },
  );
  testWidgets(
    'remote history resumes through fresh detail without changing the row',
    (tester) async {
      final library = LibraryState(
        accountId: 'history',
        provider: _SearchProvider(),
      );
      library.remember([_SearchProvider.sample]);
      library.history.add(
        const WatchEntry('whisklet:42', 12, 1, lineCode: 'direct'),
      );
      addTearDown(library.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: HistoryPage(library: library, onBrowse: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator).first,
            )
            .value,
        0,
      );
      await tester.tap(
        find.byKey(const Key('history-resume-whisklet:42:personal')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DetailPage>(find.byType(DetailPage)).resume!.seconds,
        12,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'feed retries errors, appends real pages and remembers unique metadata',
    () async {
      var fail = true;
      final requests = <int>[];
      final remembered = <Film>[];
      final feed = CatalogFeed(
        fetch: (page) async {
          requests.add(page);
          if (fail) throw StateError('offline');
          return CatalogPage(
            page == 1 ? [films[0]] : [films[0], films[1]],
            page: page,
            pages: 2,
          );
        },
        onItems: remembered.addAll,
      );
      await feed.load();
      expect(feed.items, isEmpty);
      expect(feed.error, isNotNull);
      fail = false;
      await feed.load();
      await feed.load();
      await feed.load(next: true);
      await feed.load(next: true);
      expect(requests, [1, 1, 2]);
      expect(feed.items.map((film) => film.id).toSet().length, 2);
      expect(feed.hasMore, isFalse);
      expect(feed.error, isNull);
      expect(remembered.last, films[1]);
      feed.dispose();
    },
  );

  test('disposed feed ignores late network completion', () async {
    final request = Completer<CatalogPage>();
    var remembered = false;
    final feed = CatalogFeed(
      fetch: (_) => request.future,
      onItems: (_) => remembered = true,
    );
    final pending = feed.load();
    feed.dispose();
    request.complete(CatalogPage([films.first], page: 1, pages: 1));
    await pending;
    expect(remembered, isFalse);
  });

  test(
    'search uses category browse and invalidates results during debounce',
    () async {
      final provider = _SearchProvider();
      final search = SearchState(provider)..kind = '短剧';
      await search.search('');
      expect(provider.browsed, [21]);
      final old = search.search('old');
      search.invalidate();
      provider.requests['old:1']!.complete(
        CatalogPage([films[1]], page: 1, pages: 1),
      );
      await old;
      expect(search.results, [films.first]);
      final latest = search.search('new');
      provider.requests['new:1']!.complete(
        CatalogPage([films[2]], page: 1, pages: 2),
      );
      await latest;
      final more = search.search('new', next: true);
      provider.requests['new:2']!.complete(
        CatalogPage([films[2], films[3]], page: 2, pages: 2),
      );
      await more;
      expect(search.results, [films[2], films[3]]);
      expect(search.hasMore, isFalse);
      search.dispose();
    },
  );  testWidgets(
    'remote detail loading shows a skeleton that real sections replace',
    (tester) async {
      final provider = _SkeletonProvider();
      final library = LibraryState(
        accountId: 'skeleton',
        provider: provider,
      );
      addTearDown(library.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: DetailPage(
              film: _SearchProvider.sample,
              library: library,
            ),
          ),
        ),
      );
      await tester.pump();
      // 加载中：骨架占位替代进度条，标题保持真实文案
      expect(find.byKey(const Key('detail-skeleton')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('剧情简介'), findsOneWidget);
      expect(find.text('你可能也喜欢'), findsNothing);
      // 详情到达：骨架让位给真实内容
      provider.pending.complete(const MediaDetail(_SearchProvider.sample, []));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-skeleton')), findsNothing);
      expect(find.text('当前片目暂无可用播放线路'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
