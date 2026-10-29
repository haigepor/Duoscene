import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/experience/episode_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const film = Film(
    'sheet-film',
    '连播测试剧',
    '短剧',
    '一句话简介',
    0,
    episodes: 25,
    posterUrl: '',
  );

  Future<void> open(
    WidgetTester tester, {
    bool binge = false,
    ValueChanged<bool>? onBingeChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showEpisodes(
                context,
                film,
                1,
                shared: false,
                binge: binge,
                onBingeChanged: onBingeChanged,
              ),
              child: const Text('选集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
  }

  testWidgets('episode sheet hides the binge toggle unless it is wired', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('episode-binge-switch')), findsNothing);
  });

  testWidgets('binge toggle reports state and episode picking still works', (
    tester,
  ) async {
    final changes = <bool>[];
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showEpisodes(
                  context,
                  film,
                  1,
                  shared: false,
                  onBingeChanged: changes.add,
                );
              },
              child: const Text('选集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    expect(find.text('自动连播'), findsOneWidget);
    await tester.tap(find.byKey(const Key('episode-binge-switch')));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    await tester.tap(find.text('02'));
    await tester.pumpAndSettle();
    expect(picked, 2);
  });

  testWidgets('segment tabs scroll horizontally and reach the last segment', (
    tester,
  ) async {
    const longFilm = Film(
      'long-film',
      '长剧分段测试',
      '电视剧',
      '简介',
      0,
      episodes: 152,
      posterUrl: '',
    );
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showEpisodes(context, longFilm, 1, shared: false);
              },
              child: const Text('选集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('episode-segment-scroll')), findsOneWidget);
    expect(find.text('141–152'), findsOneWidget);
    // 宽度不够时横向滑动到末段，152 集可达可点。
    await tester.scrollUntilVisible(
      find.text('141–152'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('episode-segment-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('141–152'));
    await tester.pumpAndSettle();
    expect(find.text('152'), findsOneWidget);
    await tester.tap(find.text('152'));
    await tester.pumpAndSettle();
    expect(picked, 152);
  });

  testWidgets('order toggle reverses segments and episode numbers', (
    tester,
  ) async {
    const longFilm = Film(
      'long-film',
      '长剧分段测试',
      '电视剧',
      '简介',
      0,
      episodes: 152,
      posterUrl: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showEpisodes(context, longFilm, 1, shared: false),
              child: const Text('选集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('episode-order-toggle')));
    await tester.pumpAndSettle();
    final tabs =
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const Key('episode-segment-scroll')),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .toList();
    expect(tabs.first, '141–152');
    expect(tabs.last, '1–20');
    final cells =
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(Wrap),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .toList();
    // 倒序直达最新一页：分段条停在最左，格内从 152 排到 141。
    expect(cells.first, '152');
    expect(cells.last, '141');
    final position =
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byKey(const Key('episode-segment-scroll')),
                matching: find.byType(Scrollable),
              ).first,
            )
            .position;
    expect(position.pixels, 0);
    // 再点一次回到正序，恢复到正在看的第 1 集分段。
    await tester.tap(find.byKey(const Key('episode-order-toggle')));
    await tester.pumpAndSettle();
    final restored =
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(Wrap),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .toList();
    expect(restored.first, '01');
    expect(restored.last, '20');
  });

  testWidgets('sheet opens scrolled to the segment of the current episode', (
    tester,
  ) async {
    const longFilm = Film(
      'long-film',
      '长剧分段测试',
      '电视剧',
      '简介',
      0,
      episodes: 152,
      posterUrl: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showEpisodes(context, longFilm, 100, shared: false),
              child: const Text('选集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    // 从第 100 集进入：分段条应定位到 81–100，而不是停在起点。
    final position =
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byKey(const Key('episode-segment-scroll')),
                matching: find.byType(Scrollable),
              ).first,
            )
            .position;
    expect(position.pixels, greaterThan(0));
    expect(find.text('81–100'), findsOneWidget);
  });
}
