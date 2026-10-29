import 'dart:async';

import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:duoscene/features/playback/playra/controller/player_debug_controller.dart';
import 'package:duoscene/features/playback/playra/controller/player_playback_controller.dart';
import 'package:duoscene/features/playback/playra/player_support.dart';
import 'package:duoscene/features/realtime/room_connection.dart';
import 'package:duoscene/features/realtime/room_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'session_test.dart' show MemoryTokenStore;

Map<String, dynamic> snapshot({
  int generation = 1,
  int positionMs = 42000,
  Map<String, dynamic>? media,
  bool playing = false,
}) => {
  'type': 'snapshot',
  'epoch': 'room-epoch',
  'generation': generation,
  'revision': generation,
  'positionMs': positionMs,
  'playing': playing,
  'rate': 1.0,
  'media':
      media ??
      {
        'uri': 'https://example.com/video.mp4',
        'identity': 'video:$generation',
        'title': 'Shared video',
        'hls': false,
      },
};

class TestRoom extends RoomConnection {
  TestRoom()
    : super(
        Session(ApiClient(Uri.parse('http://localhost')), MemoryTokenStore()),
        'room-id',
      ) {
    connected = true;
  }
  final sent = <Map<String, dynamic>>[];
  void publish(Map<String, dynamic> event) {
    if (event['type'] == 'snapshot') this.snapshot = event;
    events.add(event);
  }

  @override
  void send(Map<String, dynamic> message) => sent.add(message);
  @override
  void dispose() {
    super.dispose();
    auth.dispose();
  }
}

class TestPlayer extends Fake implements Player {
  @override
  PlayerState state = const PlayerState();
}

class TestCore extends PlayerPlaybackController {
  TestCore()
    : super(
        shaderAssetService: ShaderAssetService(),
        debug: PlayerDebugController(),
        videoUrl: () => '',
        isLocalPlayback: () => false,
        preferences: PlaybackPreferences(),
        onNotice: null,
      );
  final player = TestPlayer();
  @override
  Player get mediaPlayer => player;
}

class TestPlayback extends PlaybackSession {
  @override
  late final TestCore core = TestCore();
  final loads = <PlaybackSource>[];
  final targets = <Duration>[];
  final playingTargets = <bool>[];
  @override
  Future<void> load(
    PlaybackSource target, {
    bool play = false,
    bool synchronized = false,
  }) async {
    source = target;
    loads.add(target);
    loading = false;
    notifyListeners();
  }

  void durationAvailable() {
    core.player.state = const PlayerState(duration: Duration(minutes: 3));
    notifyListeners();
  }

  @override
  Future<void> applyTarget({
    required Duration position,
    required bool playing,
    required double rate,
    bool forceSeek = false,
  }) async {
    targets.add(position);
    playingTargets.add(playing);
    core.player.state = PlayerState(
      position: position,
      duration: core.player.state.duration,
      playing: playing,
    );
  }

  @override
  Future<void> close() async {
    await preferences.dispose();
    await core.preferences.dispose();
  }
}

void main() {
  test(
    'room waits for seekable media before applying the invitation position',
    () async {
      final room = TestRoom();
      final player = TestPlayback();
      final sync = RoomPlayback(room, player);
      room.publish(snapshot());
      await sync.serial;
      expect(player.loads, hasLength(1));
      expect(
        player.targets,
        isEmpty,
        reason: 'A zero-duration player cannot retain a seek.',
      );
      expect(room.sent.where((event) => event['ready'] == true), isEmpty);
      player.durationAvailable();
      await Future<void>.delayed(Duration.zero);
      await sync.serial;
      expect(player.targets, [const Duration(seconds: 42)]);
      expect(room.sent.last['ready'], true);
      await sync.dispose();
      player.dispose();
      room.dispose();
    },
  );

  test('provider snapshots resolve locally once and retain the server media identity', () async {
    final room = TestRoom();
    final player = TestPlayback()..durationAvailable();
    var resolutions = 0;
    final sync = RoomPlayback(
      room,
      player,
      resolveMedia: (media) async {
        resolutions++;
        return PlaybackSource.network(
          'https://device.example/video.m3u8?token=local',
          identity: media['identity'] as String,
          headers: {'Referer': 'https://device.example'},
        );
      },
    );
    final media = <String, dynamic>{
      'provider': 'whisklet',
      'filmId': 'whisklet:7',
      'episode': 3,
      'lineCode': 'main',
      'identity': 'whisklet:7:main:3',
      'title': 'Shared film',
    };
    room.publish(snapshot(media: media));
    await sync.serial;
    room.publish(snapshot(media: media, positionMs: 43000));
    await sync.serial;
    expect(resolutions, 1);
    expect(player.loads, hasLength(1));
    expect(player.source!.headers['Referer'], 'https://device.example');
    expect(player.targets.last, const Duration(seconds: 43));
    await sync.dispose();
    player.dispose();
    room.dispose();
  });

  test(
    'late provider resolution cannot install or ready a replaced generation',
    () async {
      final room = TestRoom();
      final player = TestPlayback()..durationAvailable();
      final slow = Completer<PlaybackSource>();
      final sync = RoomPlayback(
        room,
        player,
        resolveMedia: (media) {
          if (media['identity'] == 'video:1') return slow.future;
          return Future.value(
            PlaybackSource.network(
              media['uri'] as String,
              identity: media['identity'] as String,
            ),
          );
        },
      );
      room.publish(snapshot());
      await Future<void>.delayed(Duration.zero);
      room.publish(snapshot(generation: 2, positionMs: 7000));
      slow.complete(PlaybackSource.network('https://old.example/video.mp4'));
      await sync.serial;
      expect(player.loads.map((source) => source.identity), ['video:2']);
      expect(player.targets, [const Duration(seconds: 7)]);
      expect(
        room.sent.where(
          (event) => event['generation'] == 1 && event['ready'] == true,
        ),
        isEmpty,
      );
      await sync.dispose();
      player.dispose();
      room.dispose();
    },
  );

  test(
    'a same-media seek advances readiness without resolving or loading again',
    () async {
      final room = TestRoom();
      final player = TestPlayback()..durationAvailable();
      var resolutions = 0;
      final sync = RoomPlayback(
        room,
        player,
        resolveMedia: (media) async {
          resolutions++;
          return PlaybackSource.network(
            'https://example.com/video.mp4',
            identity: 'same',
          );
        },
      );
      final media = snapshot()['media'] as Map<String, dynamic>;
      room.publish(snapshot(media: media));
      await sync.serial;
      room.publish(snapshot(media: media, generation: 2, positionMs: 90000));
      expect(sync.ready, false);
      await sync.serial;
      expect(resolutions, 1);
      expect(player.loads, hasLength(1));
      expect(player.targets.last, const Duration(seconds: 90));
      expect(room.sent.last['generation'], 2);
      expect(room.sent.last['ready'], true);
      await sync.dispose();
      player.dispose();
      room.dispose();
    },
  );

  test('provider failure cannot reuse the previous source readiness', () async {
    final room = TestRoom();
    final player = TestPlayback()..durationAvailable();
    final failure = Completer<PlaybackSource>();
    final sync = RoomPlayback(
      room,
      player,
      resolveMedia: (media) async {
        if (media['identity'] == 'video:2') return failure.future;
        return PlaybackSource.network(media['uri'] as String);
      },
    );
    room.publish(snapshot(playing: true));
    await sync.serial;
    expect(room.sent.last['ready'], true);
    room.publish(snapshot(generation: 2));
    await Future<void>.delayed(Duration.zero);
    expect(
      player.core.playerPlaying,
      false,
      reason: 'The previous video must stay paused during slow or failed resolution.',
    );
    expect(room.sent.last['ready'], false);
    failure.completeError(StateError('upstream failed'));
    await sync.serial;
    expect(room.sent.last['generation'], 2);
    expect(room.sent.last['ready'], false);
    expect(player.error, contains('片源'));
    expect(player.loads, hasLength(1));
    expect(player.targets, hasLength(2));
    expect(player.playingTargets.last, false);
    await sync.dispose();
    player.dispose();
    room.dispose();
  });

  test('disconnect invalidates an in-flight provider resolution', () async {
    final room = TestRoom();
    final player = TestPlayback();
    final slow = Completer<PlaybackSource>();
    final sync = RoomPlayback(room, player, resolveMedia: (_) => slow.future);
    room.publish(snapshot());
    await Future<void>.delayed(Duration.zero);
    room.connected = false;
    room.publish({'type': 'disconnected'});
    slow.complete(PlaybackSource.network('https://old.example/video.mp4'));
    await sync.serial;
    expect(player.loads, isEmpty);
    expect(room.sent.where((event) => event['ready'] == true), isEmpty);
    await sync.dispose();
    player.dispose();
    room.dispose();
  });
}
