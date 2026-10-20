import 'dart:async';

import '../playback/playback_session.dart';
import '../playback/playback_source.dart';
import 'room_connection.dart';

/// 用户控制与服务端目标分开，避免本地 applyTarget 被再广播；异步换片用本地代际隔离。
class RoomPlayback {
  RoomPlayback(this.room, this.player) {
    player.remoteCommand = (type, values) async {
      try {
        await room.command(type, values);
      } catch (_) {
        room.notice ??= '操作未完成，请确认连接后重试';
        room.changed();
      }
    };
    events = room.events.stream.listen((e) {
      if (e['type'] == 'snapshot') {
        latest = e;
        received = DateTime.now();
        serial = serial.catchError((Object _) {}).then((_) => apply());
      }
      if (e['type'] == 'disconnected') {
        latest = null;
        epoch = null;
        ready = null;
        unawaited(
          player.applyTarget(
            position: player.core.playerPosition,
            playing: false,
            rate: player.core.playerSpeed,
          ),
        );
      }
    });
    player.addListener(checkReady);
  }
  final RoomConnection room;
  final PlaybackSession player;
  late final StreamSubscription<Map<String, dynamic>> events;
  Map<String, dynamic>? latest;
  DateTime received = DateTime.now();
  Future<void> serial = Future.value();
  String? epoch;
  int generation = -1;
  bool? ready;
  bool disposed = false, applying = false;
  int corrections = 0;
  Future<void> apply() async {
    final state = latest;
    if (disposed || state == null || !room.connected) return;
    final media = state['media'];
    if (media is! Map) return;
    final newEpoch = state['epoch'] as String;
    final newGeneration = state['generation'] as int;
    final changed = epoch != newEpoch || generation != newGeneration;
    if (changed) {
      epoch = newEpoch;
      generation = newGeneration;
      ready = null;
    }
    applying = true;
    try {
      if (player.source?.identity != media['identity'] ||
          player.source?.uri.toString() != media['uri']) {
        final source = PlaybackSource.network(
          media['uri'] as String,
          title: media['title'] as String,
          identity: media['identity'] as String,
          hls: media['hls'] as bool,
        );
        player.playlist = [source];
        player.playlistIndex = 0;
        await player.load(source, synchronized: true);
      }
      if (disposed ||
          latest?['epoch'] != newEpoch ||
          latest?['generation'] != newGeneration)
        return;
      final playing = state['playing'] == true;
      final elapsed = DateTime.now()
          .difference(received)
          .inMilliseconds
          .clamp(0, 3000);
      final position = Duration(
        milliseconds:
            (state['positionMs'] as num).round() +
            (playing ? (elapsed * (state['rate'] as num)).round() : 0),
      );
      if ((player.core.playerPosition - position).abs().inMilliseconds > 1200)
        corrections++;
      await player.applyTarget(
        position: position,
        playing: playing,
        rate: (state['rate'] as num).toDouble(),
        forceSeek: changed,
      );
    } finally {
      applying = false;
      checkReady();
    }
  }

  void checkReady() {
    if (disposed ||
        applying ||
        latest == null ||
        !room.connected ||
        player.source == null ||
        epoch != latest!['epoch'] ||
        generation != latest!['generation'])
      return;
    final value =
        !player.loading &&
        player.error == null &&
        player.core.mediaPlayer != null &&
        player.core.playerDuration > Duration.zero &&
        !player.core.playerBuffering;
    if (ready == value) return;
    ready = value;
    room.send({
      'type': 'ready',
      'epoch': epoch,
      'generation': generation,
      'ready': value,
    });
  }

  Future<void> dispose() async {
    disposed = true;
    player.remoteCommand = null;
    player.removeListener(checkReady);
    await events.cancel();
    await serial.catchError((Object _) {});
  }
}
