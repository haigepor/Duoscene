import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/adaptive_watch_layout.dart';
import 'package:duoscene/features/catalog/artwork_request.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/profile_page.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _AutoProvider extends Fake implements MediaProvider {
  static const film = Film(
    'whisklet:42',
    'Quick entry',
    '电视剧',
    '',
    0,
    episodes: 1,
  );
  final detailValue = MediaDetail(film, [
    MediaLine(
      code: 'main',
      name: '正片',
      parser: '',
      episodes: List.generate(
        8,
        (i) => MediaEpisode('第 ${i + 1} 集', 'fixture'),
      ),
    ),
  ]);
  MediaDetail? suppliedDetail;
  @override
  Future<MediaDetail> detail(String filmId, {bool refresh = false}) async =>
      detailValue;
  @override
  Future<PlaybackSource> resolve(
    String filmId, {
    required int episode,
    String? lineCode,
    MediaDetail? cachedDetail,
  }) async {
    suppliedDetail = cachedDetail;
    // 这里只验证详情/选集组合；原生加载由集成测试覆盖。
    throw StateError('Fixture stops before native loading');
  }

  @override
  void close() {}
}

void main() {
  testWidgets(
    'tablet detail keeps readable system bars and compact hero stays immersive',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final library = LibraryState(
        accountId: 'merge-system-bars',
        preview: true,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: DetailPage(film: films.first, library: library),
        ),
      );
      await t.pumpAndSettle();
      final state = t.state(find.byType(DetailPage));
      final region = find.descendant(
        of: find.byType(DetailPage),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(
        t
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(region.first)
            .value
            .statusBarIconBrightness,
        Brightness.dark,
      );
      t.view.physicalSize = const Size(390, 844);
      await t.pumpAndSettle();
      expect(t.state(find.byType(DetailPage)), same(state));
      expect(
        t
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(region.first)
            .value
            .statusBarIconBrightness,
        Brightness.light,
      );
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );
  testWidgets(
    'quick entry uses the loaded unified episode count and detail cache',
    (t) async {
      final provider = _AutoProvider();
      final library = LibraryState(
        accountId: 'merge-auto-entry',
        provider: provider,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: ExperiencePlayer(
            film: _AutoProvider.film,
            library: library,
            autoResolve: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('共 8 集'), findsOneWidget);
      expect(provider.suppliedDetail, same(provider.detailValue));
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );
  test(
    'merged polling updates lightweight progress without page rebuilds',
    () async {
      final session = PlaybackSession();
      session.refreshState();
      var pageChanges = 0;
      session.presentationChanges.addListener(() => pageChanges++);
      session.core.currentPosition = const Duration(seconds: 3);
      session.core.buffer = const Duration(seconds: 9);
      session.refreshState();
      expect(session.positionTick.value, const Duration(seconds: 3));
      expect(session.bufferTick.value, const Duration(seconds: 9));
      expect(pageChanges, 0);
      session.error = 'Transient fragment error';
      session.refreshState();
      expect(session.error, isNotNull);
      session.core.currentPosition = const Duration(seconds: 4);
      session.refreshState();
      // 没有原生播放实例时，即使轮询位置改变也不能把真实失败当作已恢复。
      expect(session.error, isNotNull);
      expect(session.stateTick.value, greaterThan(0));
      await session.close();
      session.dispose();
    },
  );

  for (final target in [
    'https://user:password@img3.doubanio.com/cover.jpg',
    'https://img3.doubanio.com/cover.jpg#fragment',
  ]) {
    test('proxy unwrapping does not bypass artwork validation: $target', () {
      final proxy = Uri.https('image.baidu.com', '/search/down', {
        'url': target,
      });
      expect(ArtworkRequest.parse(proxy.toString()), isNull);
    });
  }

  testWidgets('profile scroll-top is bound during mounting at either width', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final library = LibraryState(accountId: 'merge-scroll', preview: true);
    for (final width in [390.0, 1280.0]) {
      t.view.physicalSize = Size(width, 700);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: ProfilePage(key: ValueKey(width), library: library),
          ),
        ),
      );
      await t.pumpAndSettle();
      final list = t.widget<ListView>(
        find.byKey(const PageStorageKey('profile')),
      );
      final scroll = list.controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      library.requestScrollTop();
      await t.pumpAndSettle();
      expect(scroll.offset, 0);
    }
    await t.pumpWidget(const SizedBox.shrink());
    library.dispose();
  });

  testWidgets(
    'portrait media remains taller inside the stable adaptive slots',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(853, 1280);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveWatchLayout(
              showMedia: true,
              mediaAspectRatio: 9 / 16,
              header: SizedBox(height: 64),
              controls: SizedBox(height: 48),
              media: SizedBox(key: Key('merge-portrait-media')),
              conversation: SizedBox(key: Key('merge-conversation')),
            ),
          ),
        ),
      );
      final media = t.getSize(find.byKey(const Key('merge-portrait-media')));
      expect(media.height, greaterThan(700));
      expect(
        t.getSize(find.byKey(const Key('merge-conversation'))).height,
        greaterThan(160),
      );
      expect(t.takeException(), isNull);
    },
  );
}
