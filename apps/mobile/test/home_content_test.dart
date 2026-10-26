import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/motion.dart';
import 'package:duoscene/design/components.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/home_content.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:duoscene/features/experience/preview_gallery.dart';
import 'package:duoscene/design/bottom_navigation.dart';

void main() {
  testWidgets(
    'all category genres filter real films across themes and scales',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'category-filter', preview: true);
      for (final dark in [false, true]) {
        for (final large in [false, true]) {
          t.view.physicalSize = Size(large ? 320 : 390, 844);
          await t.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: buildDuosceneTheme(
                dark ? DSPalette.dark : DSPalette.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(large ? 2 : 1),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: WatchHome(
                  library: library,
                  onProfile: () {},
                  active: false,
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          final brandRect = t.getRect(find.byType(Brand));
          final searchRect = t.getRect(find.byKey(const Key('home-search')));
          final tabsTop = t
              .getTopLeft(find.byKey(const Key('home-categories')))
              .dy;
          for (final kind in ['电影', '电视剧', '动漫', '短剧']) {
            final category = find.widgetWithText(TextButton, kind);
            await Scrollable.ensureVisible(
              t.element(category),
              alignment: .25,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            );
            await t.tap(category);
            await t.pumpAndSettle();
            expect(t.getRect(find.byType(Brand)), brandRect);
            expect(t.getRect(find.byKey(const Key('home-search'))), searchRect);
            expect(
              t.getTopLeft(find.byKey(const Key('home-categories'))).dy,
              tabsTop,
            );
            expect(find.byType(HomeCarousel), findsNothing);
            expect(find.byType(WatchTogetherPanel), findsNothing);
            final items = films.where((film) => film.kind == kind);
            for (final genre in items.map((film) => film.genre).toSet()) {
              final chip = find.byKey(Key('category-genre-$genre'));
              await Scrollable.ensureVisible(
                t.element(chip),
                alignment: .25,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              );
              await t.tap(chip);
              await t.pumpAndSettle();
              for (final film in items) {
                expect(
                  find.byKey(Key('category-film-${film.id}')),
                  film.genre == genre ? findsOneWidget : findsNothing,
                );
              }
              expect(t.takeException(), isNull);
            }
          }
          final recommend = find.widgetWithText(TextButton, '推荐');
          await Scrollable.ensureVisible(
            t.element(recommend),
            alignment: .25,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          await t.tap(recommend);
          await t.pumpAndSettle();
          expect(find.byType(HomeCarousel), findsOneWidget);
          expect(find.byType(WatchTogetherPanel), findsOneWidget);
        }
      }
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'carousel restarts its full interval when its cached tab resumes',
    (t) async {
      final library = LibraryState(
        accountId: 'carousel-visible',
        preview: true,
      );
      final carousel = HomeCarousel(
        items: films.take(3).toList(),
        library: library,
        active: true,
      );
      var enabled = true;
      late StateSetter change;
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: StatefulBuilder(
            builder: (context, update) {
              change = update;
              return Scaffold(
                body: TickerMode(enabled: enabled, child: carousel),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final pager = t
          .widget<PageView>(find.byKey(const Key('home-carousel')))
          .controller!;
      change(() => enabled = false);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      change(() => enabled = true);
      await t.pump();
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(milliseconds: 500));
      expect(pager.page, 0);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));
      expect(pager.page, 1);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'home v2 separates artwork and live actions across widths themes and text scales',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final library = LibraryState(accountId: 'hero-layout', preview: true);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final width in [320.0, 390.0, 430.0]) {
          for (final scale in [1.0, 2.0]) {
            for (final palette in [DSPalette.light, DSPalette.dark]) {
              t.view.physicalSize = Size(width, 1000);
              await t.pumpWidget(
                MaterialApp(
                  theme: buildDuosceneTheme(palette)
                      .copyWith(platform: platform),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: WatchHome(
                      library: library,
                      onProfile: () {},
                      active: false,
                    ),
                  ),
                ),
              );
              await t.pumpAndSettle();
              final failure = t.takeException();
              if (failure != null) {
                debugPrint(
                  'layout failure: $platform / $width / $scale / ${palette.bg}',
                );
                debugDumpRenderTree();
              }
              expect(failure, isNull);
              final card = t.getRect(
                find.byKey(const Key('home-slide-mountains')),
              );
              final art = t.getRect(
                find.byKey(const Key('home-art-mountains')),
              );
              final detail = t.getRect(
                find.byKey(const Key('home-detail-mountains')),
              );
              final play = t.getRect(find.byType(HomePlayAction).first);
              expect(detail.top, greaterThanOrEqualTo(art.bottom));
              expect(play.top, greaterThanOrEqualTo(art.bottom));
              expect(card.contains(detail.center), isTrue);
              expect(card.contains(play.center), isTrue);
              expect(play.height, greaterThanOrEqualTo(48));
              expect(find.byType(FilmHero), findsNothing);
              expect(
                find.descendant(
                  of: find.byType(HomeCarousel),
                  matching: find.byType(LinearProgressIndicator),
                ),
                findsNothing,
              );
              expect(find.byTooltip('暂停轮播'), findsNothing);
            }
          }
        }
      }
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets('carousel resumes after swiping and retains the selected film', (
    t,
  ) async {
    final library = LibraryState(accountId: 'hero-navigation', preview: true);
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(
          body: WatchHome(library: library, onProfile: () {}),
        ),
      ),
    );
    await t.pumpAndSettle();
    final pager = t
        .widget<PageView>(find.byKey(const Key('home-carousel')))
        .controller!;
    expect(pager.page, 0);
    await t.drag(find.byKey(const Key('home-carousel')), const Offset(-700, 0));
    await t.pumpAndSettle();
    expect(pager.page, 1);
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 500));
    expect(pager.page, 2);
    await t.tap(find.widgetWithText(TextButton, '电影'));
    await t.pumpAndSettle();
    expect(find.byType(HomeCarousel), findsNothing);
    expect(find.byType(WatchTogetherPanel), findsNothing);
    expect(find.byKey(const ValueKey('pick-mountains')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const Key('category-genre-科幻')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('category-film-mountains')), findsNothing);
    expect(find.byKey(const Key('category-film-stars')), findsOneWidget);
    await t.tap(find.byKey(const Key('category-length-1')));
    await t.pumpAndSettle();
    expect(find.text('暂时没有符合条件的片目'), findsOneWidget);
    await t.tap(find.text('重置筛选').last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-mountains')), findsOneWidget);
    await t.tap(find.byKey(const Key('category-genre-科幻')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, '电视剧'));
    await t.pumpAndSettle();
    expect(find.text('全部剧集'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, '电影'));
    await t.pumpAndSettle();
    expect(find.text('筛选结果'), findsOneWidget);
    await t.tap(find.byKey(const Key('category-genre-all')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pick-mountains')));
    await t.pumpAndSettle();
    expect(t.widget<DetailPage>(find.byType(DetailPage)).film.id, 'mountains');
    expect(find.text('山海之间'), findsWidgets);
    expect(find.byKey(const Key('home-carousel')), findsNothing);
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });

  testWidgets(
    'section text and SVG share a center and retain a full tap target',
    (t) async {
      var taps = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SectionHeading(
                '动漫 · 另一种想象',
                action: ArrowAction('全部', onTap: () => taps++),
              ),
            ),
          ),
        ),
      );
      final title = t.getCenter(find.text('动漫 · 另一种想象'));
      final label = t.getCenter(find.text('全部'));
      final arrow = t.getCenter(find.byType(DSIcon));
      expect((title.dy - label.dy).abs(), lessThan(1));
      expect((arrow.dy - label.dy).abs(), lessThan(1));
      expect(
        t.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48),
      );
      await t.tap(find.text('全部'));
      expect(taps, 1);
    },
  );
  testWidgets('home keeps equal gaps above and below the compact resume card', (
    t,
  ) async {
    final library = LibraryState(accountId: 'home-gap', preview: true);
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(
          body: WatchHome(library: library, onProfile: () {}, active: false),
        ),
      ),
    );
    await t.pumpAndSettle();
    final gap =
        t.getTopLeft(find.byType(ContinueCard)).dy -
        t.getBottomLeft(find.byType(HomeCarousel)).dy;
    final bottomGap =
        t.getTopLeft(find.byType(WatchTogetherPanel)).dy -
        t.getBottomLeft(find.byType(ContinueCard)).dy;
    expect(gap, DS.space12);
    expect(bottomGap, gap);
    expect(t.getSize(find.byType(ContinueCard)).height, lessThanOrEqualTo(76));
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });
  testWidgets(
    'carousel advances, pauses offscreen and respects reduced motion',
    (t) async {
      final library = LibraryState(accountId: 'carousel-test', preview: true);
      var active = true, reduced = false;
      late StateSetter change;
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduced),
                child: Scaffold(
                  body: HomeCarousel(
                    items: films.take(3).toList(),
                    library: library,
                    active: active,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final pager = t
          .widget<PageView>(find.byKey(const Key('home-carousel')))
          .controller!;
      expect(pager.page, 0);
      await t.pump(const Duration(seconds: 6));
      await t.pump(const Duration(milliseconds: 500));
      expect(pager.page, 1);
      change(() => active = false);
      await t.pump();
      await t.pump(const Duration(seconds: 7));
      expect(pager.page, 1);
      change(() {
        active = true;
        reduced = true;
      });
      await t.pump();
      await t.pump(const Duration(seconds: 7));
      expect(pager.page, 1);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  testWidgets(
    'category buttons have no interaction overlay and continue card is compact',
    (t) async {
      final library = LibraryState(accountId: 'continue-test', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: Column(
              children: [
                DSTabs(labels: const ['推荐', '电影'], index: 0, onChanged: (_) {}),
                ContinueCard(library: library),
              ],
            ),
          ),
        ),
      );
      final button = t.widget<TextButton>(
        find.widgetWithText(TextButton, '电影'),
      );
      expect(
        button.style!.overlayColor!.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      expect(
        t.getSize(find.byType(ContinueCard)).height,
        lessThanOrEqualTo(76),
      );
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  testWidgets(
    'taller home posters remain visible and metadata scrolls above navigation',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await t.pumpWidget(
        MaterialApp(theme: duosceneTheme, home: const PreviewHost(page: 0)),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final nav = t.getRect(find.byKey(const Key('navigation-island')));
      expect(nav.left, greaterThan(0));
      expect(nav.right, lessThan(390));
      final river = find.text('治愈 · 98 分钟');
      final artwork = find.descendant(
        of: find.byType(FilmPoster).first,
        matching: find.byType(AspectRatio),
      );
      expect(t.getSize(artwork).height, greaterThan(130));
      expect(t.getTopLeft(artwork).dy, lessThan(nav.top));
      // 更高的海报允许延伸到首屏下方，轻滚后片名和元信息应完整可见。
      await t.drag(
        find
            .descendant(
              of: find.byType(WatchHome),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -80),
      );
      await t.pumpAndSettle();
      expect(t.getBottomLeft(river).dy, lessThanOrEqualTo(nav.top));
      final posters = t.widgetList<FilmPoster>(find.byType(FilmPoster));
      expect(posters.take(3).every((p) => p.editorial && p.showTitle), isTrue);
      await t.tap(find.byKey(const Key('home-create-room')));
      await t.pumpAndSettle();
      expect(find.text('登录后即可创建或加入真实房间。'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.byKey(const Key('home-join-room')));
      await t.pumpAndSettle();
      expect(find.text('登录后即可创建或加入真实房间。'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.byKey(const Key('tab-2')));
      await t.pumpAndSettle();
      expect(
        t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
        2,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('swiped resume keeps each saved episode and playback position', (
    t,
  ) async {
    // 本测试验收手机续播参数；800×600 横屏播放器布局另行覆盖。
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    final library = LibraryState(accountId: 'resume-v2', preview: true);
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(body: ContinueCard(library: library)),
      ),
    );
    await t.pumpAndSettle();
    for (var i = 0; i < library.history.length; i++) {
      if (i > 0) {
        await t.drag(find.byType(ContinueCard), const Offset(-390, 0));
        await t.pumpAndSettle();
      }
      final entry = library.history[i];
      expect(find.text('继续观看 · ${i + 1}/3').hitTestable(), findsOneWidget);
      await t.tap(find.text('继续').hitTestable());
      await t.pumpAndSettle();
      final player = t.widget<ExperiencePlayer>(find.byType(ExperiencePlayer));
      expect(player.film!.id, entry.filmId);
      expect(player.episode, entry.episode);
      expect(player.resume!.seconds, entry.seconds);
      expect(player.resume!.shared, entry.shared);
      Navigator.of(t.element(find.byType(ExperiencePlayer))).pop();
      await t.pumpAndSettle();
    }
    await t.drag(find.byType(ContinueCard), const Offset(390, 0));
    await t.pumpAndSettle();
    expect(find.text('继续观看 · 2/3').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });

  testWidgets('resume handles empty, missing and removed history entries', (
    t,
  ) async {
    final library = LibraryState(accountId: 'resume-empty');
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(body: ContinueCard(library: library)),
      ),
    );
    expect(find.byType(PageView), findsNothing);
    library.history.addAll([
      const WatchEntry('missing', 100, 1),
      const WatchEntry('summer', 1122, 3),
    ]);
    library.changed();
    await t.pumpAndSettle();
    expect(
      t
          .widget<PageView>(find.byType(PageView))
          .childrenDelegate
          .estimatedChildCount,
      1,
    );
    expect(find.text('继续观看'), findsOneWidget);
    library.history.add(const WatchEntry('mountains', 2180, 1));
    library.changed();
    await t.pumpAndSettle();
    await t.drag(find.byType(ContinueCard), const Offset(-800, 0));
    await t.pumpAndSettle();
    expect(find.text('继续观看 · 2/2').hitTestable(), findsOneWidget);
    library.history.removeLast();
    library.changed();
    await t.pumpAndSettle();
    expect(find.text('继续观看').hitTestable(), findsOneWidget);
    library.history.clear();
    library.changed();
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });
}
