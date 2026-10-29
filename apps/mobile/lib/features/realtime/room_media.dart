import 'dart:async';

import '../catalog/catalog.dart';
import '../catalog/media_provider.dart';
import '../playback/playback_source.dart';
import 'room_connection.dart';

/// 房间只保存片目选择；短期拉流地址和防盗链请求头由每台设备独立取得。
Map<String, dynamic> catalogRoomMedia({
  required Film film,
  required int episode,
  String? lineCode,
  String? sourceIdentity,
}) {
  if (film.id.length > 80 ||
      !RegExp(r'^whisklet:[1-9]\d*$').hasMatch(film.id)) {
    throw const FormatException('这个片目暂不支持同步观看，请使用双方可访问的视频地址。');
  }
  // 自动回退可能改变实际线路；邀请必须以已装载来源为准，不能沿用过期的 UI 选择。
  final loaded = RegExp('^${RegExp.escape(film.id)}:([^:]+):([1-9]\\d*)\$')
      .firstMatch(sourceIdentity ?? '');
  if (loaded != null) {
    lineCode = loaded.group(1);
    episode = int.parse(loaded.group(2)!);
  }
  if (episode < 1 ||
      episode > 100000 ||
      (lineCode != null &&
          (lineCode.isEmpty ||
              lineCode.length > 80 ||
              RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(lineCode)))) {
    throw const FormatException('剧集或播放线路无效，请重新选择后邀请。');
  }
  return {
    'provider': 'whisklet',
    'filmId': film.id,
    'episode': episode,
    if (lineCode != null) 'lineCode': lineCode,
    'identity': '${film.id}:${lineCode ?? 'auto'}:$episode',
    'title': film.title,
  };
}

Future<PlaybackSource> resolveRoomMedia(
  Map<String, dynamic> media, {
  MediaProvider? provider,
}) async {
  if (media['provider'] != null) {
    if (media['provider'] != 'whisklet' || provider?.id != 'whisklet') {
      throw const FormatException('此设备尚不支持房间选择的播放源。');
    }
    final filmId = media['filmId'] as String;
    final episode = media['episode'] as int;
    final lineCode = media['lineCode'] as String?;
    final source = await provider!.resolve(
      filmId,
      episode: episode,
      lineCode: lineCode,
    );
    // 同看不接受静默回退到另一剪辑；允许用户明确换线后重新建立共同时间轴。
    if (lineCode != null && source.identity != '$filmId:$lineCode:$episode') {
      throw const FormatException('房间选择的线路暂不可用，请双方更换片源后重试。');
    }
    return source;
  }
  return PlaybackSource.network(
    media['uri'] as String,
    title: media['title'] as String,
    identity: media['identity'] as String,
    hls: media['hls'] as bool,
  );
}

/// 初始化先于签发邀请；重试遇到已有媒体时保留服务端状态，不覆盖另一端的操作。
Future<void> initializeRoomMedia(
  RoomConnection connection, {
  required Map<String, dynamic> media,
  required int positionMs,
}) async {
  final firstSnapshot = Completer<Map<String, dynamic>>();
  final subscription = connection.events.stream.listen((event) {
    if (event['type'] == 'snapshot' && !firstSnapshot.isCompleted) {
      firstSnapshot.complete(event);
    }
  });
  try {
    if (!connection.connected) await connection.connect();
    if (!connection.connected) {
      throw StateError(connection.notice ?? '无法连接房间，请重试后再分享邀请。');
    }
    final state =
        connection.snapshot ??
        await firstSnapshot.future.timeout(const Duration(seconds: 12));
    if (state['media'] != null) return;
    try {
      await connection.command('media', {
        'media': media,
        'positionMs': positionMs.clamp(0, 86400000),
      });
    } catch (_) {
      // ack 丢失或版本竞争后，已收到的媒体快照足以确认房间不再为空。
      if (connection.snapshot?['media'] == null) rethrow;
    }
  } finally {
    await subscription.cancel();
    connection.dispose();
  }
}
