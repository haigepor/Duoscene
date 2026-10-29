import 'package:duoscene/features/experience/short_playback.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/player_page.dart';
import 'package:duoscene/features/playback/playra/controller/player_aspect_ratio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends PlaybackSession {
  @override
  Future<void> prepare() =>
      Future.error(StateError('Native unavailable in widget test'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unchanged playback state stops notifying idle consumers', () async {
    final session = PlaybackSession();
    session.refreshState();
    var changes = 0;
    session.addListener(() => changes++);
    for (var tick = 0; tick < 25; tick++) {
      session.refreshState();
    }
    expect(changes, 0);
    session.core.currentPosition = const Duration(seconds: 1);
    session.refreshState();
    expect(changes, 1);
    await session.close();
    session.refreshState();
    expect(changes, 1);
    session.dispose();
  });

  test(
    'paused aspect, duration and error changes still reach presentation',
    () async {
      final session = PlaybackSession();
      session.refreshState();
      var changes = 0;
      session.presentationChanges.addListener(() => changes++);
      session.panel.aspectRatioMode = PlayerAspectRatio.crop;
      session.refreshState();
      session.core.duration = const Duration(minutes: 2);
      session.refreshState();
      session.error = 'A playback error';
      session.refreshState();
      expect(changes, 3);
      session.core.currentPosition = const Duration(seconds: 4);
      session.core.buffer = const Duration(seconds: 10);
      session.refreshState();
      expect(changes, 3);
      await session.close();
      session.dispose();
    },
  );

  testWidgets(
    'progress updates the short timeline without rebuilding the page',
    (tester) async {
      final session = _Session();
      session.core.duration = const Duration(seconds: 60);
      session.refreshState();
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            roomName: 'Test',
            session: session,
            presentation: (_, player, _) {
              builds++;
              return ShortPlaybackControls(player: player);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initial = builds;
      for (var tick = 1; tick <= 5; tick++) {
        session.core.currentPosition = Duration(seconds: tick);
        session.refreshState();
        await tester.pump();
      }
      expect(builds, initial);
      expect(
        tester.widget<Slider>(find.byKey(const Key('short-seek'))).value,
        5000,
      );
      session.core.duration = const Duration(seconds: 120);
      session.refreshState();
      await tester.pump();
      expect(builds, initial + 1);
      expect(
        tester.widget<Slider>(find.byKey(const Key('short-seek'))).max,
        120000,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      session.dispose();
    },
  );
}
