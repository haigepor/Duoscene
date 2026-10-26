import 'dart:async';
import 'dart:convert';

import '../playback/playback_session.dart';
import '../playback/playback_source.dart';
import 'room_connection.dart';
import 'room_media.dart';

/// 用户控制与服务端目标分开，避免本地 applyTarget 被再广播；异步换片用本地代际隔离。
class RoomPlayback {
  RoomPlayback(
    this.room,
    this.player, {
    Future<PlaybackSource> Function(Map<String, dynamic>)? resolveMedia,
  }) : resolveMedia = resolveMedia ?? ((media) => resolveRoomMedia(media)) {
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
        final replaced =
            latest?['epoch'] != e['epoch'] ||
            latest?['generation'] != e['generation'];
        latest = e;
        received = DateTime.now();
        if (replaced) {
          epoch = e['epoch'] as String;
          generation = e['generation'] as int;
          ready = null;
          _targetApplied = false;
          checkReady();
        }
        _schedule();
      }
      if (e['type'] == 'disconnected') {
        ++_connectionGeneration;
        latest = null;
        epoch = null;
        ready = null;
        _loadedMediaKey = _failedKey = null;
        _targetApplied = _awaitingTarget = false;
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
  final Future<PlaybackSource> Function(Map<String, dynamic>) resolveMedia;
  late final StreamSubscription<Map<String, dynamic>> events;
  Map<String, dynamic>? latest;
  DateTime received = DateTime.now();
  Future<void> serial = Future.value();
  String? epoch;
  int generation = -1;
  bool? ready;
  bool disposed = false, applying = false;
  bool _queued = false, _targetApplied = false, _awaitingTarget = false;
  int _connectionGeneration = 0;
  String? _loadedMediaKey, _failedKey;
  int corrections = 0;

  String _key(Map<String, dynamic> state) =>
      '$_connectionGeneration:${state['epoch']}:${state['generation']}';

  String _mediaKey(Map<String, dynamic> state) {
    final media = state['media'] as Map;
    return jsonEncode([
      _connectionGeneration,
      state['epoch'],
      media['provider'],
      media['filmId'],
      media['episode'],
      media['lineCode'],
      media['uri'],
      media['identity'],
      media['title'],
      media['hls'],
    ]);
  }

  bool _current(String key) =>
      !disposed && room.connected && latest != null && _key(latest!) == key;

  void _schedule() {
    if (disposed || _queued) return;
    _queued = true;
    serial = serial.catchError((Object _) {}).then((_) async {
      _queued = false;
      await apply();
    });
  }

  Future<void> apply() async {
    var state = latest;
    if (disposed || state == null || !room.connected) return;
    final media = state['media'];
    if (media is! Map) return;
    final key = _key(state);
    final mediaKey = _mediaKey(state);
    if (_failedKey == key) return;
    applying = true;
    try {
      // 服务端片目身份与本机短期 URL 分开缓存，心跳快照不重复解析或装载。
      if (_loadedMediaKey != mediaKey) {
        // 新片源可能解析很久或失败；先暂停旧媒体，不能让上一部继续在后台发声。
        if (player.source != null) {
          await player.applyTarget(
            position: player.core.playerPosition,
            playing: false,
            rate: player.core.playerSpeed,
          );
          if (!_current(key)) return;
        }
        final source = await resolveMedia(media.cast<String, dynamic>());
        if (!_current(key)) return;
        player.error = null;
        player.playlist = [source];
        player.playlistIndex = 0;
        await player.load(source, synchronized: true);
        if (!_current(key)) return;
        if (player.error != null) throw FormatException(player.error!);
        _loadedMediaKey = mediaKey;
      }
      // file-loaded 之前 seek 会被播放器丢弃；保留目标，由时长就绪后的通知继续应用。
      if (player.loading || player.core.playerDuration <= Duration.zero) {
        _awaitingTarget = true;
        return;
      }
      state = latest!;
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
        forceSeek: !_targetApplied,
      );
      if (_current(key)) {
        _targetApplied = true;
        _awaitingTarget = false;
      }
    } catch (error) {
      if (_current(key)) {
        _failedKey = key;
        _targetApplied = _awaitingTarget = false;
        player.error = error is FormatException
            ? error.message
            : '房间片源解析或加载失败，请检查网络后重新连接房间或更换片源。';
        room.notice = player.error;
        room.changed();
      }
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
        epoch != latest!['epoch'] ||
        generation != latest!['generation'])
      return;
    final key = _key(latest!);
    final media = latest!['media'];
    if (media is! Map) return;
    final mediaKey = _mediaKey(latest!);
    if (_awaitingTarget &&
        _loadedMediaKey == mediaKey &&
        !player.loading &&
        player.core.playerDuration > Duration.zero) {
      _awaitingTarget = false;
      _schedule();
    }
    final value =
        _loadedMediaKey == mediaKey &&
        _failedKey != key &&
        _targetApplied &&
        player.source != null &&
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
