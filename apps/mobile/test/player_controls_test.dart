import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:duoscene/features/playback/playra/controller/player_debug_controller.dart';
import 'package:duoscene/features/playback/playra/controller/player_playback_controller.dart';
import 'package:duoscene/features/playback/playra/controller/player_seek_controller.dart';
import 'package:duoscene/features/playback/playra/controller/player_screenshot_controller.dart';
import 'package:duoscene/features/playback/playra/player_support.dart';
import 'package:duoscene/features/playback/playra/widgets/player_gesture_detector.dart';

class _Player extends Fake implements Player {
  @override
  PlayerState state = const PlayerState(duration: Duration(seconds: 60));
  final seeks = <Duration>[];
  Completer<void>? pending;
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    await pending?.future;
    state = PlayerState(
      duration: const Duration(seconds: 60),
      position: position,
      playing: state.playing,
    );
  }
}

class _Core extends PlayerPlaybackController {
  _Core(this.current)
    : super(
        shaderAssetService: ShaderAssetService(),
        debug: PlayerDebugController(),
        videoUrl: () => '',
        isLocalPlayback: () => false,
        preferences: PlaybackPreferences(),
        onNotice: null,
      ) {
    duration = const Duration(seconds: 60);
  }
  Player current;
  @override
  Player? get mediaPlayer => current;
}

void main() {
  test(
    'confirming a seek preserves an explicit pause and clamps the timeline',
    () async {
      final player = _Player();
      final core = _Core(player);
      var plays = 0;
      final seek = PlayerSeekController(
        playback: core,
        clearOverlays: () {},
        pause: ({bool enableSync = true}) async {},
        play: ({bool enableSync = true}) async {
          plays++;
        },
        onSeekCompleted: (_) async {},
      );
      seek.beginInteractiveSeek();
      seek.updateInteractiveSeek(const Duration(seconds: 90));
      expect(await seek.finishInteractiveSeek(), isTrue);
      expect(player.seeks, [const Duration(seconds: 60)]);
      expect(plays, 0);
      await core.preferences.dispose();
    },
  );
  test('replacing the player ignores a stale seek completion', () async {
    final player = _Player()..pending = Completer<void>();
    final core = _Core(player);
    var completed = 0;
    final seek = PlayerSeekController(
      playback: core,
      clearOverlays: () {},
      pause: ({bool enableSync = true}) async {},
      play: ({bool enableSync = true}) async {},
      onSeekCompleted: (_) async {
        completed++;
      },
    );
    final operation = seek.seekTo(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    core.current = _Player();
    player.pending!.complete();
    await operation;
    expect(completed, 0);
    await core.preferences.dispose();
  });
  test(
    'cancelled and disposed screenshot work does not enter the candidate list',
    () async {
      final shots = PlayerScreenshotController();
      final bytes = Completer<Uint8List?>();
      final operation = shots.capture(
        capturePng: () => bytes.future,
        title: 'test',
        episode: '',
        position: Duration.zero,
        isCurrent: () => true,
      );
      shots.dispose();
      bytes.complete(Uint8List.fromList([1, 2, 3]));
      expect(await operation, isFalse);
      expect(shots.candidates, isEmpty);
    },
  );
  testWidgets('pointer cancellation cancels the copied seek gesture', (
    tester,
  ) async {
    final ended = <bool>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 300,
          height: 200,
          child: PlayerGestureDetector(
            onSeekStart: () {},
            onSeekUpdate: (_, __) {},
            onSeekEnd: ended.add,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(ended, [true]);
  });
}
