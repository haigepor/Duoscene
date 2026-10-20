import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/motion.dart';
import 'package:duoscene/design/components.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/home_content.dart';
import 'package:duoscene/features/catalog/library_state.dart';

void main() {
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
  testWidgets(
    'home leaves space between the carousel and compact resume card',
    (t) async {
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
      expect(gap, DS.carouselContentGap);
      expect(
        t.getSize(find.byType(ContinueCard)).height,
        lessThanOrEqualTo(76),
      );
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
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
}
