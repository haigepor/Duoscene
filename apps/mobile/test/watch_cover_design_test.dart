import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/experience/watch_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleFilm = Film(
    'test-film',
    '嫁金钗',
    '电视剧',
    '古装,爱情',
    45,
    episodes: 38,
    posterUrl: 'https://example.com/poster.jpg',
  );

  testWidgets('WatchCover resolving state renders cinematic layout without play icon or cover preview badge', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 220,
            child: WatchCover(
              cover: 'assets/mock/films/media-movie-1-landscape.png',
              onChoose: () {},
              film: sampleFilm,
              resolving: true,
              episode: 1,
            ),
          ),
        ),
      ),
    );

    // Verify resolving minimal card is displayed with clean progress indicator
    expect(find.text('正在解析片源…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Verify unnecessary clutter and old artifacts are completely GONE:
    expect(find.text('正在寻找最优线路与画质…'), findsNothing);
    expect(find.text('封面预览'), findsNothing);
    expect(find.byTooltip('选择视频，开始观看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WatchCover error state renders alert icon and action buttons', (tester) async {
    var retried = false;
    var chose = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 220,
            child: WatchCover(
              cover: 'assets/mock/films/media-movie-1-landscape.png',
              onChoose: () => chose = true,
              onRetry: () => retried = true,
              film: sampleFilm,
              resolving: false,
              error: '片源线路连接超时，请重试。',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('片源解析未完成'), findsOneWidget);
    expect(find.text('片源线路连接超时，请重试。'), findsOneWidget);
    expect(find.text('切换线路'), findsOneWidget);
    expect(find.text('重试解析'), findsOneWidget);

    await tester.tap(find.text('重试解析'));
    expect(retried, isTrue);

    await tester.tap(find.text('切换线路'));
    expect(chose, isTrue);
  });

  testWidgets('WatchCover renders integrated top controls with back, title, subtitle and more options', (tester) async {
    var backed = false;
    var moreTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 220,
            child: WatchCover(
              cover: 'assets/mock/films/media-movie-1-landscape.png',
              onChoose: () {},
              film: sampleFilm,
              resolving: true,
              episode: 1,
              title: '嫁金钗 · 独家① · 第01集',
              subtitle: '古装,爱情 · 第 1 集 · 共 38 集',
              onBack: () => backed = true,
              onMore: () => moreTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('watch-header-title')), findsOneWidget);
    expect(find.text('嫁金钗 · 独家① · 第01集'), findsOneWidget);
    expect(find.text('古装,爱情 · 第 1 集 · 共 38 集'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('播放器更多功能'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    expect(backed, isTrue);

    await tester.tap(find.byTooltip('播放器更多功能'));
    expect(moreTapped, isTrue);
  });
}
