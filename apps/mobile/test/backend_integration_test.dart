import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:duoscene/features/realtime/room_connection.dart';
import 'package:duoscene/features/realtime/room_media.dart';
import 'package:duoscene/features/rooms/room_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' show MemoryTokenStore;

Future<Map<String, dynamic>> _connectedSnapshot(
  RoomConnection connection,
) async {
  final snapshot = Completer<Map<String, dynamic>>();
  final subscription = connection.events.stream.listen((event) {
    if (event['type'] == 'snapshot' && !snapshot.isCompleted)
      snapshot.complete(event);
  });
  try {
    await connection.connect();
    return connection.snapshot ??
        await snapshot.future.timeout(const Duration(seconds: 12));
  } finally {
    await subscription.cancel();
  }
}

class _DeviceProvider extends Fake implements MediaProvider {
  _DeviceProvider(this.device);
  final String device;
  @override
  String get id => 'whisklet';
  @override
  Future<PlaybackSource> resolve(
    String filmId, {
    required int episode,
    String? lineCode,
    MediaDetail? cachedDetail,
  }) async => PlaybackSource.network(
    'https://$device.example/video.m3u8?signature=$device',
    identity: '$filmId:$lineCode:$episode',
    headers: {'Referer': 'https://$device.example'},
  );
}

void main() {
  final path = Platform.environment['DUOSCENE_MOBILE_FIXTURE'];
  // 默认测试不依赖运行中的数据库；集成入口由 Node 夹具执行器显式加载。
  if (path == null) return;
  test('real backend: provider handoff, independent resolution, invite, join and token rotation', () async {
    final fixture = jsonDecode(
      await File(path).readAsString(encoding: utf8),
    ) as Map<String, dynamic>;
    final origin = Uri.parse(fixture['API_BASE_URL'] as String);
    final store = MemoryTokenStore();
    final owner = Session(ApiClient(origin), store);
    final guest = Session(ApiClient(origin), MemoryTokenStore());
    addTearDown(owner.dispose);
    addTearDown(guest.dispose);
    await owner.login(
      fixture['TEST_OWNER'] as String,
      fixture['TEST_PASSWORD'] as String,
    );
    await guest.login(
      fixture['TEST_GUEST'] as String,
      fixture['TEST_PASSWORD'] as String,
    );
    final rooms = RoomRepository(owner);
    final otherRooms = RoomRepository(guest);
    final room = await rooms.create('跨端真实数据库联测');
    expect(room.members.length, 1);
    final media = catalogRoomMedia(
      film: const Film('whisklet:7', '跨端片目', '电视剧', '', 40),
      episode: 3,
      lineCode: 'main',
    );
    await initializeRoomMedia(
      RoomConnection(owner, room.id),
      media: media,
      positionMs: 42500,
    );
    final invitation = await rooms.invite(room.id);
    final joined = await otherRooms.join(invitation.token);
    expect(joined.id, room.id);
    expect(joined.members.length, 2);
    expect((await rooms.get(room.id)).members.length, 2);
    final ownerConnection = RoomConnection(owner, room.id);
    final guestConnection = RoomConnection(guest, room.id);
    try {
      final snapshots = await Future.wait([
        _connectedSnapshot(ownerConnection),
        _connectedSnapshot(guestConnection),
      ]);
      for (final snapshot in snapshots) {
        expect(snapshot['media'], media);
        expect(snapshot['positionMs'], 42500);
        expect(snapshot['playing'], false);
      }
      // 两端使用自己的解析上下文；真实房间协议不传 URL 或媒体私有请求头。
      final ownerSource = await resolveRoomMedia(
        (snapshots[0]['media'] as Map).cast<String, dynamic>(),
        provider: _DeviceProvider('owner'),
      );
      final guestSource = await resolveRoomMedia(
        (snapshots[1]['media'] as Map).cast<String, dynamic>(),
        provider: _DeviceProvider('guest'),
      );
      expect(ownerSource.identity, guestSource.identity);
      expect(ownerSource.uri, isNot(guestSource.uri));
      expect(ownerSource.headers, isNot(guestSource.headers));
    } finally {
      ownerConnection.dispose();
      guestConnection.dispose();
    }
    expect(
      (await otherRooms.list()).items.any((item) => item.id == room.id),
      isTrue,
    );
    // 同一成员重试不会再消费邀请；非房主无法生成邀请。
    expect((await otherRooms.join(invitation.token)).members.length, 2);
    await expectLater(
      otherRooms.invite(room.id),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
    final oldToken = store.value;
    final restored = Session(ApiClient(origin), store);
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.user?.id, owner.user?.id);
    expect(store.value, isNot(oldToken));
    expect((await RoomRepository(restored).get(room.id)).members.length, 2);
    final access = (await restored.request('GET', '/auth/me'))['id'];
    expect(access, owner.user!.id);
    await restored.logout();
    expect(store.value, isNull);
    await expectLater(
      restored.request('GET', '/rooms'),
      throwsA(isA<ApiException>()),
    );
    await guest.logout();
  });
}
