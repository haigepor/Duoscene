import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/collection_pages.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'empty favorites shows the approved artwork, disables management and opens discovery',
    (t) async {
      final library = LibraryState(accountId: 'favorites-empty');
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: FavoritesPage(library: library),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('favorites-empty')), findsOneWidget);
      expect(find.byKey(const Key('favorites-illustration')), findsOneWidget);
      expect(find.text('把喜欢的故事，留到下次'), findsOneWidget);
      expect(
        t.getBottomLeft(find.byKey(const Key('favorites-illustration'))).dy,
        lessThan(t.getTopLeft(find.text('把喜欢的故事，留到下次')).dy),
      );
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '管理')).onPressed,
        isNull,
      );
      await t.tap(find.text('去找片'));
      await t.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'favorites keeps detail navigation, filtering and removal behavior',
    (t) async {
      final library = LibraryState(
        accountId: 'favorites-actions',
        preview: true,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: FavoritesPage(library: library),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('短剧'));
      await t.pumpAndSettle();
      expect(find.text('山海之间'), findsNothing);
      await t.tap(find.byKey(const Key('favorite-card-short')));
      await t.pumpAndSettle();
      expect(t.widget<DetailPage>(find.byType(DetailPage)).film.id, 'short');
      await t.tap(find.byTooltip('返回').first);
      await t.pumpAndSettle();
      await t.tap(find.text('管理'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('favorite-card-short')));
      await t.pump();
      await t.tap(find.text('取消收藏 1 项'));
      await t.pumpAndSettle();
      expect(library.favorites, isNot(contains('short')));
      expect(library.favorites.length, 4);
      expect(find.text('这个分类还没有收藏'), findsOneWidget);
      await t.tap(find.text('全部'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('favorite-card-mountains')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets('favorites handles narrow layouts large text and all palettes', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    final library = LibraryState(accountId: 'favorites-layout', preview: true);
    for (final palette in [DSPalette.light, DSPalette.dark]) {
      for (final empty in [false, true]) {
        library.scenario = empty ? 'favorites-empty' : 'normal';
        await t.pumpWidget(
          MaterialApp(
            theme: buildDuosceneTheme(palette),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: FavoritesPage(library: library),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    }
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });
}
