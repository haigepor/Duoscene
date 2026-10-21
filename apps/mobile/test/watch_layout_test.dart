import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:duoscene/features/experience/chat_panel.dart';
import 'package:duoscene/features/experience/invite_pages.dart';
import 'package:duoscene/features/experience/watch_controls.dart';
import 'package:duoscene/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnavailableArtwork extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.endsWith('.webp') || key.endsWith('.png')) {
      return Future.error(FlutterError('Artwork unavailable'));
    }
    return rootBundle.load(key);
  }
}

void main() {
  testWidgets('watch page keeps artwork failures inside their bounds', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final library = LibraryState(accountId: 'watch-layout', preview: true);
    for (final width in [320.0, 430.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final palette in [DSPalette.light, DSPalette.dark]) {
          t.view.physicalSize = Size(width, 844);
          await t.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: buildDuosceneTheme(palette),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: DefaultAssetBundle(
                  bundle: _UnavailableArtwork(),
                  child: child!,
                ),
              ),
              home: ExperiencePlayer(film: films.first, library: library),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$width / $scale');
          expect(find.byType(ErrorWidget), findsNothing);
          final title = t.getRect(find.byKey(const Key('watch-header-title')));
          final cover = t.getRect(find.byType(WatchCover));
          expect(title.width, greaterThanOrEqualTo(50 * scale));
          expect(title.right, lessThanOrEqualTo(width));
          expect(title.bottom, lessThan(cover.top));
          final statusBar = t.getRect(
            find.byKey(const Key('watch-composer-status')),
          );
          final inputSurface = t.getRect(
            find.byKey(const Key('watch-composer-input-surface')),
          );
          expect(inputSurface.width, greaterThan(statusBar.width));
          expect(inputSurface.left, lessThan(statusBar.left));
          expect(inputSurface.right, greaterThan(statusBar.right));
          expect(inputSurface.left, 0);
          expect(inputSurface.width, width);
          expect(find.text('剧情 · 108 分钟'), findsOneWidget);
          expect(find.text('正在观看'), findsNothing);
          expect(find.text('山海之间'), findsOneWidget);
          expect(find.text('片源'), findsOneWidget);
          expect(find.text('同看'), findsOneWidget);
          expect(find.text('音频'), findsOneWidget);
          expect(find.text('麦克风已关闭'), findsNothing);
          expect(find.text('视频地址'), findsNothing);
          // 聊天自然铺在背景上，不能再被 Panel 包成卡片。
          expect(
            find.ancestor(
              of: find.byType(ChatPanel),
              matching: find.byType(Panel),
            ),
            findsNothing,
          );
          if (scale == 1) {
            expect(
              t.getSize(find.byKey(const Key('watch-control-bar'))).height,
              lessThanOrEqualTo(40),
            );
          }
          await t.tap(find.text('片源'));
          await t.pumpAndSettle();
          expect(find.text('视频地址'), findsOneWidget);
          expect(find.text('本地视频'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.tap(find.byTooltip('关闭片源选择'));
          await t.pumpAndSettle();
        }
      }
    }
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });

  testWidgets(
    'watch sheets keep source, invite, audio and chat flows reachable',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'watch-controls', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: buildDuosceneTheme(DSPalette.light),
          home: ExperiencePlayer(film: films[1], library: library, episode: 3),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('治愈 · 第 3 集 · 共 12 集'), findsOneWidget);
      expect(find.text('选集 · 3'), findsOneWidget);
      expect(find.byKey(const Key('watch-composer-status')), findsOneWidget);
      expect(
        t.getRect(find.byKey(const Key('watch-composer-status'))).bottom,
        lessThanOrEqualTo(t.getRect(find.byKey(const Key('chat-input'))).top),
      );
      expect(
        t.widget<IconButton>(find.byKey(const Key('chat-send'))).onPressed,
        isNull,
      );
      await t.enterText(find.byKey(const Key('chat-input')), '这一段好好看');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('chat-send')));
      await t.pumpAndSettle();
      expect(find.text('这一段好好看'), findsOneWidget);
      expect(
        t.widget<IconButton>(find.byKey(const Key('chat-send'))).onPressed,
        isNull,
      );

      await t.tap(find.text('音频'));
      await t.pumpAndSettle();
      final slider = find.byKey(const Key('watch-volume'));
      await t.tapAt(
        t.getTopLeft(slider) +
            Offset(t.getSize(slider).width * .3, t.getSize(slider).height / 2),
      );
      await t.pumpAndSettle();
      final volume = library.movieVolume;
      expect(volume, lessThan(.5));
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await t.tap(find.byTooltip('关闭音频设置'));
      await t.pumpAndSettle();
      await t.tap(find.text('音频'));
      await t.pumpAndSettle();
      expect(t.widget<Slider>(slider).value, volume);
      await t.tap(find.byTooltip('关闭音频设置'));
      await t.pumpAndSettle();

      await t.tap(find.text('同看'));
      await t.pumpAndSettle();
      expect(find.text('界面预览 · 不会建立真实连接'), findsOneWidget);
      await t.tap(find.byKey(const Key('watch-together-primary')));
      await t.pumpAndSettle();
      expect(find.byType(InviteSheet), findsOneWidget);
      Navigator.of(t.element(find.byType(InviteSheet))).pop();
      await t.pumpAndSettle();

      await t.tap(find.text('清晰度'));
      await t.pumpAndSettle();
      expect(find.text('先选择视频，再查看可用清晰度'), findsOneWidget);
      expect(find.text('1080P'), findsNothing);
      await t.tap(find.byTooltip('关闭清晰度选择'));
      await t.pumpAndSettle();
      await t.tap(find.text('同看预览'));
      await t.pumpAndSettle();
      await t.tap(find.text('结束同看预览'));
      await t.pumpAndSettle();
      expect(find.text('个人观看'), findsOneWidget);
      await t.tap(find.text('选集 · 3'));
      await t.pumpAndSettle();
      await t.tap(find.text('04'));
      await t.pumpAndSettle();
      expect(find.text('选集 · 4'), findsOneWidget);
      expect(find.text('治愈 · 第 4 集 · 共 12 集'), findsOneWidget);

      await t.tap(find.byTooltip('选择视频，开始观看'));
      await t.pumpAndSettle();
      await t.tap(find.text('视频地址'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('media-url')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'multiline composer grows, caps its height and scrolls long drafts',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      for (final scale in [1.0, 2.0]) {
        final library = LibraryState(
          accountId: 'composer-multiline',
          preview: true,
        );
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildDuosceneTheme(DSPalette.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ExperiencePlayer(film: films.first, library: library),
          ),
        );
        await t.pumpAndSettle();
        final field = find.byKey(const Key('chat-input'));
        final surface = find.byKey(const Key('watch-composer-input-surface'));
        await t.tap(field);
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        expect(find.byType(WatchCover), findsNothing);
        await t.enterText(field, '第一行');
        await t.pumpAndSettle();
        final singleHeight = t.getSize(surface).height;
        await t.enterText(field, '第一行\n第二行\n第三行');
        await t.pumpAndSettle();
        expect(t.getSize(surface).height, greaterThan(singleHeight));
        await t.enterText(field, List.filled(10, '这是一段多行草稿').join('\n'));
        await t.pumpAndSettle();
        final cappedHeight = t.getSize(surface).height;
        await t.enterText(field, List.filled(30, '这是一段多行草稿').join('\n'));
        await t.pumpAndSettle();
        expect(t.getSize(surface).height, cappedHeight);
        expect(cappedHeight, lessThanOrEqualTo(DS.inputHeight * 3 + DS.space8));
        final scrolling = find.descendant(
          of: field,
          matching: find.byType(Scrollable),
        );
        expect(
          t.state<ScrollableState>(scrolling).position.maxScrollExtent,
          greaterThan(0),
        );
        expect(t.getRect(surface).bottom, lessThanOrEqualTo(544));
        await t.enterText(field, '第一行\n第二行');
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('chat-send')));
        await t.pumpAndSettle();
        expect(find.text('第一行\n第二行'), findsOneWidget);
        expect(t.widget<TextField>(field).controller!.text, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        library.dispose();
        t.view.resetViewInsets();
      }
    },
  );

  testWidgets('keyboard leaves input visible and hides the media cover', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 640);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    final library = LibraryState(accountId: 'watch-keyboard', preview: true);
    await t.pumpWidget(
      MaterialApp(
        theme: buildDuosceneTheme(DSPalette.dark),
        home: ExperiencePlayer(film: films.first, library: library),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('chat-input')));
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    await t.pumpAndSettle();
    expect(find.byType(WatchCover), findsNothing);
    expect(
      t.getRect(find.byKey(const Key('chat-input'))).bottom,
      lessThanOrEqualTo(360),
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });

  testWidgets(
    'personal together sheet stays compact and adapts to large text',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final palette in [DSPalette.light, DSPalette.dark]) {
        for (final scale in [1.0, 2.0]) {
          t.view.physicalSize = const Size(320, 740);
          final library = LibraryState(
            accountId: 'together-personal',
            preview: true,
          )..scenario = 'private-chat-empty';
          await t.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: buildDuosceneTheme(palette),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: ExperiencePlayer(film: films.first, library: library),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.text('同看'));
          await t.pumpAndSettle();
          expect(find.text('等待好友加入'), findsOneWidget);
          expect(find.text('观看状态'), findsNothing);
          expect(find.text('交流范围'), findsNothing);
          expect(find.text('界面预览 · 不会建立真实连接'), findsOneWidget);
          final action = find.byKey(const Key('watch-together-primary'));
          expect(t.widget<FilledButton>(action).onPressed, isNotNull);
          if (scale == 1) {
            expect(
              t.getSize(find.byType(DSSheetContent)).height,
              lessThan(300),
            );
          }
          await t.ensureVisible(action);
          await t.tap(action);
          await t.pumpAndSettle();
          expect(find.byType(InviteSheet), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          library.dispose();
        }
      }
    },
  );

  testWidgets(
    'large composer status keeps episode and quality actions reachable',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 740);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'composer-large', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: buildDuosceneTheme(DSPalette.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ExperiencePlayer(film: films[1], library: library, episode: 3),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('清晰度'));
      await t.pumpAndSettle();
      await t.tap(find.text('清晰度'));
      await t.pumpAndSettle();
      expect(find.text('先选择视频，再查看可用清晰度'), findsOneWidget);
      await t.tap(find.byTooltip('关闭清晰度选择'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('选集 · 3'));
      await t.pumpAndSettle();
      await t.tap(find.text('选集 · 3'));
      await t.pumpAndSettle();
      expect(find.text('同看时，换集将与好友同步确认'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'real personal viewing guides source selection before invitation',
    (t) async {
      final library = LibraryState(accountId: 'together-real');
      await t.pumpWidget(
        MaterialApp(
          theme: buildDuosceneTheme(DSPalette.light),
          home: ExperiencePlayer(film: films.first, library: library),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('同看'));
      await t.pumpAndSettle();
      expect(find.text('先选择视频'), findsOneWidget);
      expect(find.text('界面预览 · 不会建立真实连接'), findsNothing);
      await t.tap(find.byKey(const Key('watch-together-primary')));
      await t.pumpAndSettle();
      expect(find.text('选择视频'), findsOneWidget);
      expect(find.text('视频地址'), findsOneWidget);
      expect(find.text('本地视频'), findsOneWidget);
      expect(find.byType(InviteSheet), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
