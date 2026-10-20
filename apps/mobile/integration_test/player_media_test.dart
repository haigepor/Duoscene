import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:duoscene/features/playback/player_page.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:duoscene/features/playback/playra/player_support.dart';
import 'package:duoscene/features/playback/widgets/player_surface.dart';
import 'package:duoscene/app/theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real native MP4/HLS first frame, seek, speed, tracks, screenshot and lifecycle',
    (tester) async {
      // 换片会创建 Android Texture，必须持续处理平台帧，不能沿用单元测试的按需帧策略。
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      const base = String.fromEnvironment('MEDIA_FIXTURE_BASE');
      const header = String.fromEnvironment('TEST_MEDIA_HEADER');
      expect(base, isNotEmpty, reason: 'Run scripts/test-player-media.mjs');
      final session = PlaybackSession();
      addTearDown(session.dispose);
      // 页面与来源可能同时请求初始化，真实平台也只允许安装一次轮询和设置订阅。
      await Future.wait([session.prepare(), session.prepare()]);
      const renderer = String.fromEnvironment('TEST_PLAYER_RENDERER');
      if (renderer.isNotEmpty)
        await session.preferences.putSetting(
          SettingsKeys.androidVideoRenderer,
          renderer,
        );
      await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
        .6,
      );
      expect(
        await ScreenBrightnessPlatform.instance.application,
        closeTo(.6, .02),
      );
      final mp4 = PlaybackSource.network(
        '$base/video.mp4',
        title: 'Playra · MP4 验证',
        headers: {'X-Duoscene-Test-Media': header},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: PlayerPage(
            roomName: '播放器联测',
            initialSource: mp4,
            session: session,
          ),
        ),
      );
      Future<void> until(
        bool Function() ready, {
        String reason = 'native state did not converge',
      }) async {
        for (var attempt = 0; attempt < 150; attempt++) {
          if (ready()) return;
          await tester.pump(const Duration(milliseconds: 200));
        }
        fail(reason);
      }

      await until(
        () => session.core.mediaPlayer != null && !session.loading,
        reason: 'MP4 did not load',
      );
      expect(session.error, isNull, reason: session.debug.playerLog.join('\n'));
      await session.play();
      await until(
        () => session.core.playerPosition > const Duration(seconds: 1),
      );
      await session.core.videoController!.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 20),
      );
      await until(() => session.debug.playerWidth > 0);
      expect(session.debug.playerWidth, 640);
      expect(session.debug.playerHeight, 360);
      final native = await session.core.screenshotPng();
      expect(native, isNotNull);
      expect(native!.length, greaterThan(1000));
      expect(
        (await http.post(
          Uri.parse('$base/capture/native.png'),
          body: native,
        )).statusCode,
        204,
      );
      await session.pause();
      await until(() => !session.core.playerPlaying);
      final paused = session.core.playerPosition;
      await tester.pump(const Duration(seconds: 1));
      expect(
        (session.core.playerPosition - paused).abs(),
        lessThan(const Duration(milliseconds: 300)),
      );
      await session.seek(const Duration(seconds: 12));
      await until(
        () =>
            (session.core.playerPosition - const Duration(seconds: 12)).abs() <
            const Duration(seconds: 1),
      );
      expect(session.core.playerPlaying, isFalse);
      await session.setRate(1.5);
      await until(() => session.core.mediaPlayer!.state.rate == 1.5);
      expect(session.core.mediaPlayer!.state.tracks.audio, isNotEmpty);
      final temporary = await getTemporaryDirectory();
      final subtitle = File('${temporary.path}/duoscene-player-fixture.srt');
      addTearDown(() async {
        if (await subtitle.exists()) await subtitle.delete();
      });
      await subtitle.writeAsString(
        '1\n00:00:00,000 --> 00:00:30,000\nDuoscene subtitle fixture\n',
      );
      await session.core.mediaPlayer!.setSubtitleTrack(
        SubtitleTrack.uri(
          Uri.file(subtitle.path).toString(),
          title: 'Local fixture',
        ),
      );
      await until(
        () => session.core.mediaPlayer!.state.subtitle
            .join(' ')
            .contains('Duoscene subtitle fixture'),
      );
      await tester.ensureVisible(find.text('全部设置 ›'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('全部设置 ›'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('画面比例'), findsOneWidget);
      Navigator.of(tester.element(find.text('画面比例'))).pop();
      await tester.pump(const Duration(milliseconds: 600));
      if (find.byTooltip('全屏').hitTestable().evaluate().isEmpty) {
        await tester.tapAt(tester.getCenter(find.byType(PlayerSurface)));
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.tap(find.byTooltip('播放').hitTestable().first);
      await until(() => session.core.playerPlaying);
      await tester.tap(find.byTooltip('暂停').hitTestable().first);
      await until(() => !session.core.playerPlaying);
      await tester.tap(find.byTooltip('全屏'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        tester.widget<PlayerSurface>(find.byType(PlayerSurface)).fullscreen,
        isTrue,
      );
      await tester.tap(find.byTooltip('退出全屏'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        tester.widget<PlayerSurface>(find.byType(PlayerSurface)).fullscreen,
        isFalse,
      );
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 400));
      final page = await binding.takeScreenshot('player');
      expect(
        (await http.post(
          Uri.parse('$base/capture/page.png'),
          body: Uint8List.fromList(page),
        )).statusCode,
        204,
      );
      await session.preferences.putSetting(SettingsKeys.hAenable, false);
      final hls = PlaybackSource.network(
        '$base/hls/stream',
        title: 'Playra · HLS 验证',
        headers: {'X-Duoscene-Test-Media': header},
        hls: true,
      );
      await session.load(hls);
      expect(session.error, isNull);
      await session.play();
      await until(
        () => session.core.playerPosition > const Duration(seconds: 1),
      );
      await session.seek(const Duration(seconds: 18));
      await until(
        () => session.core.playerPosition > const Duration(seconds: 16),
      );
      await session.capture();
      expect(session.screenshots.candidates, isNotEmpty);
      final staleLoad = session.load(mp4);
      final newestLoad = session.load(hls);
      await Future.wait([staleLoad, newestLoad]);
      expect(session.source, same(hls));
      expect(session.error, isNull);
      final localVideo = File('${temporary.path}/duoscene-player-fixture.mp4');
      addTearDown(() async {
        if (await localVideo.exists()) await localVideo.delete();
      });
      final response = await http.get(mp4.uri, headers: mp4.headers);
      expect(response.statusCode, 200);
      await localVideo.writeAsBytes(response.bodyBytes);
      await session.load(
        PlaybackSource.local(localVideo.path, title: 'Local fixture'),
      );
      expect(session.error, isNull);
      await session.play();
      await until(
        () => session.core.playerPosition > const Duration(seconds: 1),
      );
      await session.core.videoController!.waitUntilFirstFrameRendered;
      expect(
        await PlatformEnvironmentService.channel.invokeMethod<bool>(
          'enterPip',
          {'width': 640, 'height': 360},
        ),
        isTrue,
      );
      await until(
        () => tester
            .widget<PlayerSurface>(find.byType(PlayerSurface))
            .pictureInPicture,
      );
      await session.pause();
      await session.close();
      expect(session.core.mediaPlayer, isNull);
      expect(session.core.videoController, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
