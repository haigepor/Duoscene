import 'dart:async';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/motion.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/home_content.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/catalog/search_page.dart';
import 'package:duoscene/features/experience/short_feed.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StyleProvider implements MediaProvider {
  static const movie = Film(
    'whisklet:style-movie',
    '接口电影标题',
    '电影',
    '剧情',
    90,
    posterUrl: '',
    synopsis: '接口返回的真实剧情信息',
  );
  static const short = Film(
    'whisklet:style-short',
    '接口短剧标题',
    '短剧',
    '都市',
    2,
    episodes: 12,
    posterUrl: '',
  );
  final unresolvedMedia = Completer<PlaybackSource>();

  @override
  String get id => 'style-provider';
  @override
  String get name => '样式回归测试源';
  @override
  Future<List<MediaCategory>> categories() async => const [
    MediaCategory(1, '电影'),
    MediaCategory(21, '短剧'),
  ];
  @override
  Future<List<Film>> recommendations() async => const [movie, short];
  @override
  Future<CatalogPage> browse(int category, {int page = 1}) async =>
      CatalogPage([category == 21 ? short : movie], page: page, pages: 1);
  @override
  Future<CatalogPage> searchPage(String query, {int page = 1}) async =>
      CatalogPage(const [movie], page: page, pages: 1);
  @override
  Future<List<Film>> search(String query) async => const [movie];
  @override
  Future<MediaDetail> detail(String filmId) async =>
      MediaDetail(filmId == short.id ? short : movie, const [
        MediaLine(
          code: 'direct',
          name: '接口直连线路',
          episodes: [MediaEpisode('第一集', 'opaque-media-token')],
          parser: '',
        ),
        MediaLine(
          code: 'backup',
          name: '接口备用线路',
          episodes: [
            MediaEpisode('第一集', 'opaque-backup-token'),
            MediaEpisode('第二集', 'opaque-second-token'),
          ],
          parser: 'https://example.com/parse?url=',
        ),
      ]);
  @override
  Future<PlaybackSource> resolve(
    String filmId, {
    required int episode,
    String? lineCode,
    MediaDetail? cachedDetail,
  }) => unresolvedMedia.future;
  @override
  void close() {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<LibraryState> render(
    WidgetTester tester,
    Widget Function(LibraryState) page,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = LibraryState(
      accountId: 'provider-style-regression',
      provider: _StyleProvider(),
    );
    addTearDown(library.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: page(library),
      ),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return library;
  }

  testWidgets(
    'provider home binds data to original carousel and category shell',
    (tester) async {
      await render(
        tester,
        (library) => Scaffold(
          body: WatchHome(library: library, onProfile: () {}, active: false),
        ),
      );
      expect(find.byKey(const Key('home-search')), findsOneWidget);
      expect(find.byKey(const Key('home-categories')), findsOneWidget);
      expect(find.byType(HomeCarousel), findsOneWidget);
      expect(find.text(_StyleProvider.movie.title), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'provider search keeps original input tabs and information rows',
    (tester) async {
      await render(
        tester,
        (library) => SearchPage(library: library, initialQuery: '接口'),
      );
      expect(find.byKey(const Key('search-input')), findsOneWidget);
      expect(find.byType(DSTabs), findsOneWidget);
      expect(find.byType(ListView), findsWidgets);
      expect(find.byType(GridView), findsNothing);
      expect(find.text(_StyleProvider.movie.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'provider short feed keeps full screen vertical pager and overlays',
    (tester) async {
      await render(
        tester,
        (library) => Scaffold(body: ShortFeed(library: library, active: true)),
      );
      expect(find.byKey(const Key('short-action-rail')), findsOneWidget);
      expect(find.byKey(const Key('short-details')), findsOneWidget);
      final pagers = tester.widgetList<PageView>(find.byType(PageView));
      expect(
        pagers.where((pager) => pager.scrollDirection == Axis.vertical),
        isNotEmpty,
      );
      expect(find.text(_StyleProvider.short.title), findsWidgets);
      expect(find.text('第 1 集 · 共 2 集'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider detail retains related section without dropdown form', (
    tester,
  ) async {
    await render(
      tester,
      (library) => DetailPage(film: _StyleProvider.movie, library: library),
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('你可能也喜欢'), findsOneWidget);
    expect(find.text(_StyleProvider.movie.synopsis), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
