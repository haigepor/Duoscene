import 'dart:async';

import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:duoscene/features/experience/short_feed.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:duoscene/features/playback/player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AnchorProvider implements MediaProvider {
  static const listed = Film(
    'whisklet:anchor-listed',
    '信息流里的短剧',
    '短剧',
    '都市',
    2,
    episodes: 6,
    posterUrl: '',
  );
  static const second = Film(
    'whisklet:anchor-second',
    '列表第二部短剧',
    '短剧',
    '都市',
    2,
    episodes: 5,
    posterUrl: '',
  );
  static const orphan = Film(
    'whisklet:anchor-orphan',
    '锚点新短剧',
    '短剧',
    '都市',
    2,
    episodes: 8,
    posterUrl: '',
  );
  static const movie = Film(
    'whisklet:anchor-movie',
    '普通长片',
    '电影',
    '剧情',
    90,
    posterUrl: '',
  );

  final unresolved = Completer<PlaybackSource>();

  void emitSource(PlaybackSource value) => unresolved.complete(value);

  @override
  String get id => 'anchor-provider';
  @override
  String get name => '锚点测试源';
  @override
  Future<List<MediaCategory>> categories() async => const [
    MediaCategory(21, '短剧'),
  ];
  @override
  Future<List<Film>> recommendations() async => const [listed];
  @override
  Future<CatalogPage> browse(int category, {int page = 1}) async =>
      CatalogPage(
        [
          if (category == 21) listed else movie,
          if (category == 21) second,
        ],
        page: page,
        pages: 1,
      );
  @override
  Future<CatalogPage> searchPage(String query, {int page = 1}) async =>
      CatalogPage(const [], page: page, pages: 1);
  @override
  Future<List<Film>> search(String query) async => const [];
  @override
  Future<MediaDetail> detail(String filmId) async => MediaDetail(
    filmId == orphan.id
        ? orphan
        : filmId == movie.id
        ? movie
        : filmId == second.id
        ? second
        : listed,
    const [
      MediaLine(
        code: 'main',
        name: '独家①',
        parser: 'https://example.com/parse?url=',
        episodes: [
          MediaEpisode('第一集', 'm1'),
          MediaEpisode('第二集', 'm2'),
          MediaEpisode('第三集', 'm3'),
        ],
      ),
      MediaLine(
        code: 'backup',
        name: '备用',
        parser: '',
        episodes: [MediaEpisode('第一集', 'b1'), MediaEpisode('第二集', 'b2')],
      ),
    ],
  );
  @override
  Future<PlaybackSource> resolve(
    String filmId, {
    required int episode,
    String? lineCode,
    MediaDetail? cachedDetail,
  }) => unresolved.future;
  @override
  void close() {}
}

LibraryState makeLibrary() => LibraryState(
  accountId: 'short-anchor',
  provider: _AnchorProvider(),
);

Future<void> render(
  WidgetTester tester,
  Widget Function(LibraryState) page,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final library = makeLibrary();
  addTearDown(library.dispose);
  await tester.pumpWidget(
    MaterialApp(
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('锚点剧不在信息流上游时插入第一位，集数按入口指定', (tester) async {
    await render(
      tester,
      (library) => ShortFeed(
        library: library,
        active: false,
        initialFilm: _AnchorProvider.orphan,
        initialEpisode: 2,
      ),
    );
    expect(find.text('锚点新短剧'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('short-episode-label')))
          .data,
      '第 2 集 · 共 8 集',
    );
  });

  testWidgets('锚点剧在上游列表内时直接落在该剧，不重复插入', (tester) async {
    await render(
      tester,
      (library) => ShortFeed(
        library: library,
        active: false,
        initialFilm: _AnchorProvider.listed,
      ),
    );
    expect(find.text('信息流里的短剧'), findsWidgets);
    expect(find.text('锚点新短剧'), findsNothing);
  });

  testWidgets('锚点剧在上游中间时翻页器落到该剧所在页', (tester) async {
    await render(
      tester,
      (library) => ShortFeed(
        library: library,
        active: false,
        initialFilm: _AnchorProvider.second,
      ),
    );
    expect(find.text('列表第二部短剧'), findsWidgets);
    final pager = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    expect(pager.hasClients, isTrue);
    expect(pager.page, 1);
  });

  testWidgets('解析完成换树后翻页器仍稳定落在锚点页', (tester) async {
    _AnchorProvider? captured;
    await render(
      tester,
      (library) {
        captured = library.provider as _AnchorProvider;
        return ShortFeed(
          library: library,
          active: true,
          initialFilm: _AnchorProvider.second,
        );
      },
    );
    final pager = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    expect(pager.page, 1);
    captured!.emitSource(
      PlaybackSource.network('https://example.com/ep1.mp4'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(pager.page, 1);
  });

  testWidgets('详情页短剧立即观看进入信息流播放器，不落横屏播放器', (tester) async {
    await render(
      tester,
      (library) => DetailPage(film: _AnchorProvider.listed, library: library),
    );
    await tester.tap(find.text('立即观看'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ShortFeed), findsOneWidget);
    expect(find.byType(ExperiencePlayer), findsNothing);
  });

  testWidgets('轮播选择视频对短剧推入信息流播放器', (tester) async {
    await render(
      tester,
      (library) => Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  openCatalogPlayer(context, _AnchorProvider.listed, library),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ShortFeed), findsOneWidget);
    expect(find.byType(ExperiencePlayer), findsNothing);
  });
}
