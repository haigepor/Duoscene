import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/bottom_navigation.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/app_shell.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/collection_pages.dart';
import 'package:duoscene/features/catalog/home_content.dart';
import 'package:duoscene/features/experience/preview_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'standalone preview ignores repeated selection of its current tab',
    (t) async {
      await t.pumpWidget(
        MaterialApp(theme: duosceneTheme, home: const PreviewHost(page: 0)),
      );
      await t.pumpAndSettle();
      final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
      await t.tap(find.byKey(const Key('tab-0')));
      await t.pumpAndSettle();
      expect(navigator.canPop(), isFalse);
      await t.tap(find.byKey(const Key('tab-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tab-2')));
      await t.pumpAndSettle();
      navigator.pop();
      await t.pumpAndSettle();
      expect(navigator.canPop(), isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('first tab layout precedes the shared page and thumb motion', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(theme: duosceneTheme, home: const AppShell(preview: true)),
    );
    await t.pumpAndSettle();
    final thumb = find.byKey(const Key('navigation-thumb'));
    final start = t.getTopLeft(thumb).dx;
    await t.tap(find.byKey(const Key('tab-2')));
    await t.pump();
    expect(
      t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
      0,
    );
    final prepared = find.byType(HistoryPage, skipOffstage: false);
    expect(prepared, findsOneWidget);
    expect(prepared.hitTestable(), findsNothing);
    expect(TickerMode.valuesOf(t.element(prepared)).enabled, isFalse);
    // 模拟首次布局占用较长时间，提交选择后的首帧仍从原位置开始。
    await t.pump(const Duration(milliseconds: 100));
    expect(
      t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
      2,
    );
    expect(t.getTopLeft(thumb).dx, closeTo(start, .01));
    await t.pump(const Duration(milliseconds: 16));
    expect(t.getTopLeft(thumb).dx, greaterThan(start));
    await t.pumpAndSettle();
    expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);
    expect(find.byType(WatchHome, skipOffstage: false), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'superseded preparation cannot select a stale tab after rapid taps',
    (t) async {
      await t.pumpWidget(
        MaterialApp(theme: duosceneTheme, home: const AppShell(preview: true)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tab-2')));
      await t.tap(find.byKey(const Key('tab-3')));
      await t.pumpAndSettle();
      expect(
        t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
        3,
      );
      expect(find.byType(HistoryPage, skipOffstage: false), findsNothing);
      await t.tap(find.byKey(const Key('tab-2')));
      await t.tap(find.byKey(const Key('tab-3')));
      await t.pumpAndSettle();
      expect(
        t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
        3,
      );
      expect(find.byType(HistoryPage, skipOffstage: false), findsNothing);
      await t.tap(find.byKey(const Key('tab-2')));
      await t.tap(find.byKey(const Key('tab-0')));
      await t.pumpAndSettle();
      expect(
        t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
        0,
      );
      await t.tap(find.byKey(const Key('tab-2')));
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'tab selection does not rebuild outgoing or cached page content',
    (t) async {
      await t.pumpWidget(
        MaterialApp(theme: duosceneTheme, home: const AppShell(preview: true)),
      );
      await t.pumpAndSettle();
      final pager = t
          .widget<PageView>(find.byKey(const Key('home-carousel')))
          .controller!;
      final rebuilt = <Type>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        rebuilt.add(element.widget.runtimeType);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      await t.tap(find.byKey(const Key('tab-2')));
      await t.pumpAndSettle();
      expect(rebuilt.where((type) => type == WatchHome), isEmpty);
      // 后台轮播必须同步暂停；不能通过保留活动页来减少重建。
      await t.pump(const Duration(seconds: 7));
      expect(pager.page, 0);
      rebuilt.clear();
      await t.tap(find.byKey(const Key('tab-0')));
      await t.pumpAndSettle();
      expect(
        rebuilt.where((type) => type == HistoryPage || type == WatchHome),
        isEmpty,
      );
      expect(find.byType(HomeCarousel), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      await t.pump(const Duration(milliseconds: 500));
      expect(pager.page, 1);
      rebuilt.clear();
      final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('secondary')),
        ),
      );
      await t.pumpAndSettle();
      expect(rebuilt.where((type) => type == WatchHome), isEmpty);
      navigator.pop();
      await t.pumpAndSettle();
      expect(rebuilt.where((type) => type == WatchHome), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cached shell pages still refresh when library data changes', (
    t,
  ) async {
    final library = LibraryState(accountId: 'cached-library', preview: true);
    library.favorites.clear();
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: AppShell(preview: true, library: library),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tab-3')));
    await t.pumpAndSettle();
    expect(find.text('还没有收藏，去发现喜欢的影片。'), findsOneWidget);
    library.favorites.add('stars');
    library.changed();
    await t.pumpAndSettle();
    expect(find.text('还没有收藏，去发现喜欢的影片。'), findsNothing);
    expect(
      t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
      3,
    );
    await t.tap(find.byKey(const Key('tab-0')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tab-3')));
    await t.pumpAndSettle();
    expect(find.text('还没有收藏，去发现喜欢的影片。'), findsNothing);
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });

  testWidgets(
    'reduced motion commits a first tab without a preparation frame',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const AppShell(preview: true),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tab-3')));
      await t.pump();
      expect(
        t.widget<DuosceneNavigation>(find.byType(DuosceneNavigation)).index,
        3,
      );
      // 焦点转移另排一次布局；不推进时间，避免将它误判为过渡动画。
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'glass navigation supports dark palettes large text and reduced motion',
    (t) async {
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      for (final palette in [DSPalette.light, DSPalette.dark]) {
        var selected = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: buildDuosceneTheme(palette),
            home: StatefulBuilder(
              builder: (context, change) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(2),
                ),
                child: Scaffold(
                  bottomNavigationBar: DuosceneNavigation(
                    index: selected,
                    onSelect: (next) => change(() => selected = next),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final before = t
            .getTopLeft(find.byKey(const Key('navigation-thumb')))
            .dx;
        await t.tap(find.byKey(const Key('tab-3')));
        await t.pump();
        expect(
          t.getTopLeft(find.byKey(const Key('navigation-thumb'))).dx,
          greaterThan(before),
        );
        expect(t.hasRunningAnimations, isFalse);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'floating navigation leaves short feed controls and list endings reachable',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await t.pumpWidget(
        MaterialApp(theme: duosceneTheme, home: const AppShell(preview: true)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tab-1')));
      await t.pumpAndSettle();
      final top = t.getTopLeft(find.byKey(const Key('navigation-island'))).dy;
      expect(
        t.getBottomLeft(find.byKey(const Key('short-details'))).dy,
        lessThan(top),
      );
      expect(find.byKey(const Key('short-select-video')), findsNothing);
      await t.tap(find.byKey(const Key('tab-3')));
      await t.pumpAndSettle();
      final list = find.byType(ListView).last;
      await t.drag(list, const Offset(0, -1400));
      await t.pumpAndSettle();
      expect(t.getBottomLeft(find.text('退出预览')).dy, lessThan(top));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'glass navigation moves one thumb continuously without ink overlays',
    (t) async {
      var index = 0;
      late StateSetter change;
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return Scaffold(
                bottomNavigationBar: DuosceneNavigation(
                  index: index,
                  onSelect: (next) => change(() => index = next),
                ),
              );
            },
          ),
        ),
      );
      final thumb = find.byKey(const Key('navigation-thumb'));
      expect(thumb, findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      final start = t.getTopLeft(thumb).dx;
      await t.tap(find.byKey(const Key('tab-1')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      final moving = t.getTopLeft(thumb).dx;
      expect(moving, greaterThan(start));
      change(() => index = 0);
      await t.pump();
      expect(t.getTopLeft(thumb).dx, closeTo(moving, .01));
      for (var i = 0; i < 4; i++) {
        final button = t.widget<TextButton>(find.byKey(Key('tab-$i')));
        expect(
          button.style!.overlayColor!.resolve({WidgetState.pressed}),
          Colors.transparent,
        );
        expect(
          button.style!.backgroundColor!.resolve({WidgetState.selected}),
          Colors.transparent,
        );
        expect(
          t.getSize(find.byKey(Key('tab-$i'))).height,
          greaterThanOrEqualTo(48),
        );
      }
      await t.pumpAndSettle();
      expect(t.getTopLeft(thumb).dx, closeTo(start, .01));
    },
  );

  testWidgets('home category thumb continues smoothly on reversal', (t) async {
    final library = LibraryState(accountId: 'category-motion', preview: true);
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(
          body: WatchHome(library: library, onProfile: () {}, active: false),
        ),
      ),
    );
    await t.pumpAndSettle();
    final thumb = find.byKey(const Key('tabs-pill-indicator'));
    expect(thumb, findsOneWidget);
    expect(find.byKey(const Key('tabs-ticket-paint')), findsOneWidget);
    expect(t.getSize(thumb).height, lessThanOrEqualTo(30));
    final start = t.getTopLeft(thumb).dx;
    await t.tap(find.widgetWithText(TextButton, '电影'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 70));
    final moving = t.getTopLeft(thumb).dx;
    expect(moving, greaterThan(start));
    await t.tap(find.widgetWithText(TextButton, '推荐'));
    await t.pump();
    expect(t.getTopLeft(thumb).dx, closeTo(moving, .01));
    await t.pumpAndSettle();
    expect(t.getTopLeft(thumb).dx, closeTo(start, .01));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });

  testWidgets('room card uses compact type and preserves full touch targets', (
    t,
  ) async {
    var create = 0, join = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(
          body: SizedBox(
            width: 354,
            child: WatchTogetherPanel(
              onCreate: () => create++,
              onJoin: () => join++,
            ),
          ),
        ),
      ),
    );
    expect(
      t.widget<Text>(find.text('一起看')).style!.fontSize,
      lessThanOrEqualTo(14),
    );
    for (final key in ['home-create-room', 'home-join-room']) {
      expect(t.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(48));
      await t.tap(find.byKey(Key(key)));
    }
    expect(create, 1);
    expect(join, 1);
    expect(t.takeException(), isNull);
  });
}
