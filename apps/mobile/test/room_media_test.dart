import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/playback/playback_source.dart';
import 'package:duoscene/features/realtime/room_media.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_playback_test.dart' show TestRoom;

const film = Film('whisklet:7', 'Test film', '电视剧', '', 40, episodes: 9);

class DeviceProvider extends Fake implements MediaProvider {
  DeviceProvider(this.device, {this.fallback = false});
  final String device;
  final bool fallback;
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
    identity: '$filmId:${fallback ? 'backup' : lineCode}:$episode',
    headers: {'Referer': 'https://$device.example'},
  );
}

class InvitationRoom extends TestRoom {
  InvitationRoom({
    bool occupied = false,
    this.failConnect = false,
    this.failCommand = false,
  }) {
    connected = !failConnect;
    snapshot = {
      'media': occupied ? {'identity': 'already-selected'} : null,
    };
  }
  final bool failConnect, failCommand;
  bool closed = false;
  final commands = <Map<String, dynamic>>[];
  @override
  Future<void> connect() async => throw StateError('offline');
  @override
  Future<void> command(
    String type, [
    Map<String, dynamic> values = const {},
  ]) async {
    commands.add({'type': type, ...values});
    if (failCommand) throw StateError('not acknowledged');
    snapshot = {'media': values['media'], 'positionMs': values['positionMs']};
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

void main() {
  test('handoff uses the actual fallback line and episode without copying a URL or headers', () {
    final media = catalogRoomMedia(
      film: film,
      episode: 2,
      lineCode: 'main',
      sourceIdentity: 'whisklet:7:actual:3',
    );
    expect(media, {
      'provider': 'whisklet',
      'filmId': 'whisklet:7',
      'episode': 3,
      'lineCode': 'actual',
      'identity': 'whisklet:7:actual:3',
      'title': 'Test film',
    });
    for (final line in ['', 'white space', '\u007f', 'main\n']) {
      expect(
        () => catalogRoomMedia(film: film, episode: 1, lineCode: line),
        throwsFormatException,
      );
    }
  });

  test('two devices resolve the same logical media into independent signed sources', () async {
    final media = catalogRoomMedia(film: film, episode: 3, lineCode: 'main');
    final first = await resolveRoomMedia(
      media,
      provider: DeviceProvider('first'),
    );
    final second = await resolveRoomMedia(
      media,
      provider: DeviceProvider('second'),
    );
    expect(first.identity, second.identity);
    expect(first.uri, isNot(second.uri));
    expect(first.headers, isNot(second.headers));
    expect(media.keys, isNot(contains('uri')));
    expect(media.keys, isNot(contains('headers')));
    expect(() => first.toRoomMedia(), throwsFormatException);
  });

  test('a selected room line rejects local fallback to another edit', () async {
    final media = catalogRoomMedia(film: film, episode: 3, lineCode: 'main');
    await expectLater(
      resolveRoomMedia(
        media,
        provider: DeviceProvider('first', fallback: true),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('线路'),
        ),
      ),
    );
  });

  test('legacy URL media stays compatible without a provider', () async {
    final source = await resolveRoomMedia({
      'uri': 'https://example.com/a.m3u8',
      'identity': 'legacy',
      'title': 'Legacy',
      'hls': true,
    });
    expect(source.uri.toString(), 'https://example.com/a.m3u8');
    expect(source.identity, 'legacy');
    expect(source.isHls, true);
  });

  test('invitation initialization includes progress and closes the temporary connection', () async {
    final room = InvitationRoom();
    final media = catalogRoomMedia(film: film, episode: 3, lineCode: 'main');
    await initializeRoomMedia(room, media: media, positionMs: 42500);
    expect(room.commands, [
      {'type': 'media', 'media': media, 'positionMs': 42500},
    ]);
    expect(room.snapshot!['positionMs'], 42500);
    expect(room.closed, true);
    expect(room.events.hasListener, false);
  });

  test(
    'retrying initialization preserves media already chosen in the room',
    () async {
      final room = InvitationRoom(occupied: true);
      await initializeRoomMedia(
        room,
        media: catalogRoomMedia(film: film, episode: 3, lineCode: 'main'),
        positionMs: 42500,
      );
      expect(room.commands, isEmpty);
      expect(room.snapshot!['media'], {'identity': 'already-selected'});
      expect(room.closed, true);
    },
  );

  test(
    'connection and command failures dispose the initial snapshot listener',
    () async {
      for (final room in [
        InvitationRoom(failConnect: true),
        InvitationRoom(failCommand: true),
      ]) {
        await expectLater(
          initializeRoomMedia(
            room,
            media: catalogRoomMedia(film: film, episode: 3),
            positionMs: 42500,
          ),
          throwsStateError,
        );
        expect(room.closed, true);
        expect(room.events.hasListener, false);
      }
    },
  );
}
