import 'dart:convert';
import 'dart:io';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/rooms/room_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'session_test.dart' show MemoryTokenStore;

void main() {
  final path = Platform.environment['DUOSCENE_MOBILE_FIXTURE'];
  // 默认测试不依赖运行中的数据库；集成入口由 Node 夹具执行器显式加载。
  if (path == null) return;
  test(
    'real backend: login, create, invite, join, restore and revoke logout',
    () async {
      final fixture =
          jsonDecode(await File(path).readAsString(encoding: utf8))
              as Map<String, dynamic>;
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
      final invitation = await rooms.invite(room.id);
      final joined = await otherRooms.join(invitation.token);
      expect(joined.id, room.id);
      expect(joined.members.length, 2);
      expect((await rooms.get(room.id)).members.length, 2);
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
    },
  );
}
