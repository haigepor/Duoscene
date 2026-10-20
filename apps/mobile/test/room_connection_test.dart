import 'package:flutter_test/flutter_test.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/auth/token_store.dart';
import 'package:duoscene/features/realtime/room_connection.dart';

void main() {
  testWidgets(
    'retry keeps the same message and gets its own acknowledgement timeout',
    (t) async {
      final auth = Session(
        ApiClient(Uri.parse('http://127.0.0.1:3000')),
        _Store(),
      );
      final room = _Connection(auth);
      room.chat('同一条消息', retryId: 'one-message');
      await t.pump(const Duration(seconds: 7));
      room.chat('同一条消息', retryId: 'one-message');
      await t.pump(const Duration(seconds: 2));
      expect(room.pending.length, 1);
      expect(room.pending['one-message']!['delivery'], 'sending');
      await t.pump(const Duration(seconds: 6));
      expect(room.pending['one-message']!['delivery'], 'failed');
      room.chat('新消息');
      room.dispose();
      auth.dispose();
    },
  );
}

class _Connection extends RoomConnection {
  _Connection(Session auth) : super(auth, 'test-room');
  @override
  void send(Map<String, dynamic> message) {}
}

class _Store implements TokenStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String token) async {}
  @override
  Future<void> clear() async {}
}
