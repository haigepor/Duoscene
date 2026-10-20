import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/realtime/room_connection.dart';
import 'package:duoscene/features/realtime/room_watch_page.dart';
import 'package:duoscene/features/voice/room_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' show MemoryTokenStore;

void main() {
  testWidgets(
    'incoming chat preserves history and older pages retain the reading anchor',
    (t) async {
      final auth = Session(
        ApiClient(Uri.parse('http://localhost:3000')),
        MemoryTokenStore(),
      );
      final room = _Room(auth)..connected = true;
      Map<String, dynamic> message(int i) => {
        'id': '$i',
        'text': '消息 $i',
        'userId': 'peer',
        'displayName': '好友',
      };
      room.messages.addAll(List.generate(60, message));
      final voice = RoomVoice(room);
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: LiveRoomChat(room: room, voice: voice, onAudio: () {}),
          ),
        ),
      );
      await t.pumpAndSettle();
      final list = find.byType(ListView);
      final controller = t.widget<ListView>(list).controller!;
      controller.jumpTo(240);
      await t.pumpAndSettle();
      final original = controller.offset;
      room.messages.add(message(61));
      room.events.add({'type': 'chat'});
      room.changed();
      await t.pumpAndSettle();
      expect(controller.offset, closeTo(original, 1));
      expect(find.text('1 条新消息'), findsOneWidget);
      await t.tap(find.text('1 条新消息'));
      await t.pumpAndSettle();
      expect(controller.position.extentAfter, lessThan(1));
      expect(find.text('1 条新消息'), findsNothing);
      controller.jumpTo(0);
      await t.pumpAndSettle();
      await t.tap(find.text('查看更早消息'));
      final originalY = t.getTopLeft(find.text('消息 0')).dy;
      room.messages.insertAll(0, List.generate(10, (i) => message(i - 10)));
      room.events.add({'type': 'history', 'initial': false});
      room.changed();
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('消息 0')).dy, closeTo(originalY, 1));
      expect(t.takeException(), isNull);
      room.connected = false;
      await t.pumpWidget(const SizedBox());
      voice.dispose();
      room.dispose();
      auth.dispose();
    },
  );
}

class _Room extends RoomConnection {
  _Room(Session auth) : super(auth, 'test');
  @override
  void older() {}
}
