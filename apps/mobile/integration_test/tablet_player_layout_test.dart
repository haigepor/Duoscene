import 'dart:convert';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/rendering_budget.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/experience/chat_panel.dart';
import 'package:duoscene/features/experience/experience_player.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:duoscene/features/playback/playra/player_support.dart';
import 'package:duoscene/features/playback/widgets/player_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native tablet video survives rotation, composition, fullscreen and supported PIP',
    (t) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final budget = SkiaResourceBudget()..start();
      addTearDown(budget.dispose);
      const base = String.fromEnvironment('MEDIA_FIXTURE_BASE');
      const header = String.fromEnvironment('TEST_MEDIA_HEADER');
      expect(base, isNotEmpty, reason: 'Run scripts/test-tablet-layout.mjs');
      Future<void> phase(String name) async {
        expect(
          (await http.post(Uri.parse('$base/phase/$name'))).statusCode,
          204,
        );
        await t.pump(const Duration(milliseconds: 700));
      }

      Future<void> until(bool Function() ready, String reason) async {
        for (var i = 0; i < 120; i++) {
          if (ready()) return;
          await t.pump(const Duration(milliseconds: 200));
        }
        fail(reason);
      }

      final library = LibraryState(
        accountId: 'tablet-native-layout-fixture',
        preview: true,
      )..movieVolume = 0;
      await phase('landscape');
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: ExperiencePlayer(
            film: films.first,
            library: library,
            initialSource: PlaybackSource.network(
              '$base/video.mp4',
              title: 'Tablet layout fixture',
              headers: {'X-Duoscene-Test-Media': header},
            ),
          ),
        ),
      );
      await until(
        () => find.byType(PlayerSurface).evaluate().isNotEmpty,
        'Video surface missing',
      );
      final session = t
          .widget<PlayerSurface>(find.byType(PlayerSurface))
          .session;
      await until(
        () => session.core.mediaPlayer != null && !session.loading,
        'Synthetic MP4 did not load',
      );
      expect(session.error, isNull);
      await session.core.mediaPlayer!.setVolume(0);
      await session.play();
      await until(
        () => session.core.playerPosition > const Duration(seconds: 1),
        'Playback did not progress',
      );
      await session.core.videoController!.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 20),
      );
      await session.pause();
      await session.seek(const Duration(seconds: 12));
      await until(
        () =>
            (session.core.playerPosition - const Duration(seconds: 12)).abs() <
            const Duration(seconds: 1),
        'Seek did not converge',
      );
      final controller = session.core.videoController;
      final generation = session.generation;
      final wide = t.getRect(find.byType(PlayerSurface));
      expect(wide.width, greaterThan(780));
      expect(t.getRect(find.byType(ChatPanel)).left, greaterThan(wide.right));
      await phase('capture-landscape');

      if (find.byTooltip('全屏').hitTestable().evaluate().isEmpty) {
        await t.tapAt(t.getCenter(find.byType(PlayerSurface)));
        await t.pump(const Duration(milliseconds: 400));
      }
      await t.tap(find.byTooltip('全屏'));
      await t.pump(const Duration(milliseconds: 800));
      expect(
        t.widget<PlayerSurface>(find.byType(PlayerSurface)).fullscreen,
        isTrue,
      );
      await t.tap(find.byTooltip('退出全屏'));
      await t.pump(const Duration(milliseconds: 800));
      expect(
        t.widget<PlayerSurface>(find.byType(PlayerSurface)).fullscreen,
        isFalse,
      );
      expect(session.core.videoController, same(controller));

      await t.enterText(
        find.byKey(const Key('chat-input')),
        'tablet native draft',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await phase('portrait');
      expect(session.core.videoController, same(controller));
      expect(session.generation, generation);
      expect(
        (session.core.playerPosition - const Duration(seconds: 12)).abs(),
        lessThan(const Duration(seconds: 1)),
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('chat-input')))
            .controller!
            .text,
        'tablet native draft',
      );
      final portrait = t.getRect(find.byType(PlayerSurface));
      expect(
        t.getRect(find.byType(ChatPanel)).top,
        greaterThan(portrait.bottom),
      );
      await phase('capture-portrait');

      // 测试绑定缓存了上次 EditableText；手动取消焦点后先清空，再请求真实 IME。
      binding.focusedEditable = null;
      await t.showKeyboard(find.byKey(const Key('chat-input')));
      await t.pump(const Duration(milliseconds: 700));
      await phase('inspect-keyboard');
      await until(
        () =>
            WidgetsBinding
                .instance
                .platformDispatcher
                .views
                .first
                .viewInsets
                .bottom >
            0,
        'Native IME did not open',
      );
      await t.pump(const Duration(milliseconds: 700));
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final usableHeight =
          (view.physicalSize.height - view.viewInsets.bottom) /
          view.devicePixelRatio;
      expect(
        t.getRect(find.byKey(const Key('chat-input'))).bottom,
        lessThanOrEqualTo(usableHeight + 1),
      );
      await phase('capture-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await t.pump(const Duration(milliseconds: 600));
      expect(session.core.videoController, same(controller));

      final enteredPip =
          await PlatformEnvironmentService.channel.invokeMethod<bool>(
            'enterPip',
            {'width': 640, 'height': 360},
          ) ==
          true;
      if (enteredPip) {
        await until(
          () => t
              .widgetList<PlayerSurface>(
                find.byType(PlayerSurface, skipOffstage: false),
              )
              .any((surface) => surface.pictureInPicture),
          'PIP callback missing',
        );
        await phase('foreground');
        await until(
          () => t
              .widgetList<PlayerSurface>(
                find.byType(PlayerSurface, skipOffstage: false),
              )
              .any((surface) => !surface.pictureInPicture),
          'PIP did not exit',
        );
        expect(session.core.videoController, same(controller));
        expect(session.generation, generation);
      }
      final result = {
        'nativeFirstFrame': true,
        'sourceDimensions': [
          session.debug.playerWidth,
          session.debug.playerHeight,
        ],
        'wideVideoWidth': wide.width,
        'portraitVideoWidth': portrait.width,
        'controllerPreserved': true,
        'draftPreserved': true,
        'positionPreserved': true,
        'keyboardVisibleAndInputReachable': true,
        'fullscreenRoundTrip': true,
        'pipRoundTrip': enteredPip,
      };
      expect(
        (await http.post(
          Uri.parse('$base/result'),
          body: jsonEncode(result),
        )).statusCode,
        204,
      );
      binding.reportData = result;
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 500));
      library.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
