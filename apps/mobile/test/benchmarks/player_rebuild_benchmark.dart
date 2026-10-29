import 'dart:convert';

import 'package:duoscene/features/experience/short_playback.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends PlaybackSession {
  @override
  Future<void> prepare() =>
      Future.error(StateError('No native media in widget benchmark'));
}

void main() {
  testWidgets('measure progress-only and idle presentation rebuilds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final samples = <Map<String, int>>[];
    for (var run = 0; run < 7; run++) {
      final session = _Session();
      session.core.duration = const Duration(seconds: 60);
      session.refreshState();
      var builds = 0, notifications = 0;
      session.addListener(() => notifications++);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            key: ValueKey(run),
            roomName: 'Benchmark',
            session: session,
            presentation: (_, player, _) {
              builds++;
              // 只测确定性的重建次数，不把宿主缺少原生播放器当作媒体错误。
              return ShortScrubLine(
                player: PlayerPresentation(
                  session: player.session,
                  settings: player.settings,
                  network: player.network,
                  local: player.local,
                  screenshots: player.screenshots,
                  capture: player.capture,
                  pip: player.pip,
                  toggle: player.toggle,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialBuilds = builds;
      for (var tick = 1; tick <= 25; tick++) {
        session.core.currentPosition = Duration(milliseconds: tick * 200);
        session.refreshState();
        await tester.pump();
      }
      final progressBuilds = builds - initialBuilds;
      final progressNotifications = notifications;
      expect(find.bySemanticsLabel('播放进度 0:05 / 1:00'), findsOneWidget);
      for (var tick = 0; tick < 25; tick++) {
        session.refreshState();
        await tester.pump();
      }
      samples.add({
        'pageBuildsDuringProgress': progressBuilds,
        'pageBuildsWhileIdle': builds - initialBuilds - progressBuilds,
        'sessionNotificationsProgress': progressNotifications,
        'sessionNotificationsIdle': notifications - progressNotifications,
        'finalProgressPositionMs': session.positionTick.value.inMilliseconds,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      session.dispose();
      expect(tester.takeException(), isNull);
    }
    debugPrintSynchronously(
      'PERF_RESULT:${jsonEncode({'kind': 'widget-rebuild-count-not-fps', 'runs': 7, 'ticks': 25, 'samples': samples})}',
    );
  });
}
