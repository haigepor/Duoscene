import '../../core/models.dart';
import '../auth/session.dart';

class RoomRepository {
  RoomRepository(this.session);
  final Session session;
  Future<RoomPage> list({String? after}) async => RoomPage.fromJson(
    await session.request(
      'GET',
      '/rooms',
      query: {'limit': '20', if (after != null) 'after': after},
    ),
  );
  Future<Room> create(String name) async => Room.fromJson(
    await session.request('POST', '/rooms', body: {'name': name.trim()}),
  );
  Future<Room> join(String token) async => Room.fromJson(
    await session.request('POST', '/rooms/join', body: {'token': token.trim()}),
  );
  Future<Room> get(String id) async =>
      Room.fromJson(await session.request('GET', '/rooms/$id'));
  Future<Invite> invite(String id) async =>
      Invite.fromJson(await session.request('POST', '/rooms/$id/invites'));
  Future<void> revoke(String roomId, String inviteId) async {
    await session.request('DELETE', '/rooms/$roomId/invites/$inviteId');
  }
}
