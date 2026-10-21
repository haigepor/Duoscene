import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/collection_pages.dart';
import 'package:duoscene/features/catalog/detail_page.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'empty history shows the approved artwork, browse works and management stays disabled',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final library = LibraryState(accountId: 'empty-history');
      var browsed = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: HistoryPage(library: library, onBrowse: () => browsed++),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.byKey(const Key('history-illustration')), findsOneWidget);
      expect(find.text('看过的故事，会在这里等你。'), findsOneWidget);
      expect(
        t.getBottomLeft(find.byKey(const Key('history-illustration'))).dy,
        lessThan(t.getTopLeft(find.text('还没有观看记录')).dy),
      );
      expect(
        t.getBottomLeft(find.byKey(const Key('collection-browse'))).dy,
        lessThan(t.getTopLeft(find.text('个人与共同进度独立保存 · 仅此设备')).dy),
      );
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '管理')).onPressed,
        isNull,
      );
      await t.tap(find.text('去找片'));
      expect(browsed, 1);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'history filters, details, resume and confirmed deletion retain their behavior',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final library = LibraryState(accountId: 'history-actions', preview: true);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: HistoryPage(library: library, onBrowse: () {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('影视'));
      await t.pumpAndSettle();
      expect(find.text('回到风起时'), findsNothing);
      await t.tap(find.byKey(const Key('history-row-summer:personal')));
      await t.pumpAndSettle();
      expect(t.widget<DetailPage>(find.byType(DetailPage)).film.id, 'summer');
      await t.tap(find.byTooltip('返回').first);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('history-resume-summer:personal')));
      await t.pumpAndSettle();
      final player = t.widget<ExperiencePlayer>(find.byType(ExperiencePlayer));
      expect(player.episode, 3);
      expect(player.resume!.seconds, 1122);
      await t.tap(find.byTooltip('返回').first);
      await t.pumpAndSettle();
      await t.tap(find.text('管理'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('history-row-summer:personal')));
      await t.pump();
      await t.tap(find.text('删除所选 1 条'));
      await t.pumpAndSettle();
      expect(find.text('删除本机记录？'), findsOneWidget);
      await t.tap(find.text('删除').last);
      await t.pumpAndSettle();
      expect(library.history.any((entry) => entry.filmId == 'summer'), isFalse);
      expect(find.text('风起的夏天'), findsNothing);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  testWidgets(
    'history layout accommodates narrow screens large text and all palettes',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final library = LibraryState(accountId: 'history-layout', preview: true);
      for (final palette in [DSPalette.light, DSPalette.dark]) {
        for (final empty in [false, true]) {
          library.scenario = empty ? 'history-empty' : 'normal';
          await t.pumpWidget(
            MaterialApp(
              theme: buildDuosceneTheme(palette),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: HistoryPage(library: library, onBrowse: () {}),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
      }
      await t.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
