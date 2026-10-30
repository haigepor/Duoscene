import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/experience/chat_panel.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:duoscene/features/experience/watch_controls.dart';
import 'package:duoscene/features/playback/player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'tablet detail reserves a stable information column while detail is unavailable',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(
        accountId: 'tablet-detail-failure',
        preview: true,
      );
      const film = Film('whisklet:tablet-unavailable', '片名', '电影', '', 0);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: DetailPage(film: film, library: library),
        ),
      );
      await t.pumpAndSettle();
      final poster = t.getRect(find.byKey(const Key('tablet-detail-poster')));
      expect(t.getRect(find.text('片名')).left, lessThan(poster.right + 120));
      expect(find.text('详情加载失败'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );
  testWidgets(
    'short tablet windows reserve readable conversation space at large text',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(
        accountId: 'tablet-low-height',
        preview: true,
      );
      for (final height in [400.0, 500.0]) {
        t.view.physicalSize = Size(1280, height);
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: duosceneTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ExperiencePlayer(film: films.first, library: library),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'height=$height');
        expect(
          t.getRect(find.byKey(const Key('chat-input'))).bottom,
          lessThanOrEqualTo(height),
        );
        await t.pumpWidget(const SizedBox.shrink());
      }
      library.dispose();
    },
  );
  testWidgets(
    'wide watch layout gives video a main pane and preserves player and draft on resize',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'tablet-watch', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: ExperiencePlayer(film: films.first, library: library),
        ),
      );
      await t.pumpAndSettle();
      final cover = t.getRect(find.byType(WatchCover));
      final chat = t.getRect(find.byType(ChatPanel));
      expect(cover.left, 0);
      expect(cover.width, 1280 - 360 - 24);
      expect(chat.left, greaterThan(cover.right));
      final player = t.state(find.byType(PlayerPage));
      await t.enterText(find.byKey(const Key('chat-input')), 'tablet draft');
      t.view.physicalSize = const Size(853, 1280);
      await t.pumpAndSettle();
      final portraitCover = t.getRect(find.byType(WatchCover));
      expect(portraitCover.left, 0);
      expect(portraitCover.width, 853);
      expect(t.state(find.byType(PlayerPage)), same(player));
      expect(
        t
            .widget<TextField>(find.byKey(const Key('chat-input')))
            .controller!
            .text,
        'tablet draft',
      );
      t.view.physicalSize = const Size(480, 720);
      await t.pumpAndSettle();
      expect(t.state(find.byType(PlayerPage)), same(player));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );

  testWidgets(
    'tablet detail shows a bounded portrait poster beside the synopsis',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'tablet-detail', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: DetailPage(film: films.first, library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tablet-detail-poster')), findsOneWidget);
      final poster = t.getRect(find.byKey(const Key('tablet-detail-poster')));
      expect(poster.width, inInclusiveRange(180, 220));
      expect(t.getRect(find.text('剧情简介')).left, greaterThan(poster.right));
      expect(
        t.getSize(find.text(films.first.synopsis)).width,
        lessThanOrEqualTo(720),
      );
      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );

  testWidgets(
    'tablet detail renders modern episode selector card with quick rail and polished actions',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 853);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'tablet-episode', preview: true);
      const multiEpFilm = Film(
        'series-test',
        '多集剧集',
        '电视剧',
        '情感',
        45,
        episodes: 12,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: DetailPage(film: multiEpFilm, library: library),
        ),
      );
      await t.pumpAndSettle();

      // 验证顶部导航按钮存在，且支持语义与 tooltip 查找
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.byTooltip('收藏影片'), findsOneWidget);
      expect(find.bySemanticsLabel('返回'), findsOneWidget);
      expect(find.bySemanticsLabel('收藏影片'), findsOneWidget);

      // 验证选集卡片渲染
      expect(find.text('选集'), findsOneWidget);
      expect(find.text('第 1 集'), findsOneWidget);
      expect(find.text('共 12 集'), findsOneWidget);

      // 验证横向快捷集数按钮渲染
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // 点按快捷集数中的“2”，立即切换当前选集到第 2 集
      await t.tap(find.text('2'));
      await t.pumpAndSettle();
      expect(find.text('第 2 集'), findsOneWidget);

      // 点按收藏按钮，验证收藏逻辑被调用并高亮激活
      await t.tap(find.bySemanticsLabel('收藏影片'));
      await t.pumpAndSettle();
      expect(library.favorites.contains(multiEpFilm.id), isTrue);

      await t.pumpWidget(const SizedBox.shrink());
      library.dispose();
    },
  );
}
