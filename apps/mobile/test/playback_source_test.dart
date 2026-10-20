import 'package:duoscene/features/playback/playback_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network media rejects executable schemes, credentials and malformed headers', () {
    for (final value in [
      'av://lavfi:testsrc',
      'file:///etc/passwd',
      'https://u:p@example.com/a.mp4',
    ]) {
      expect(() => PlaybackSource.network(value), throwsFormatException);
    }
    expect(
      () => PlaybackSource.network(
        'https://example.com/a.mp4',
        headers: {'X-Test': 'a\r\nb'},
      ),
      throwsFormatException,
    );
    final source = PlaybackSource.network(
      'https://example.com/a.m3u8?token=secret',
      headers: {'Referer': 'https://example.com'},
    );
    expect(source.isHls, isTrue);
    expect(source.displayLocation, isNot(contains('secret')));
    expect(source.headers['Referer'], 'https://example.com');
  });
  test(
    'media identity is stable and distinct from signed playback location',
    () {
      final first = PlaybackSource.network(
        'https://example.com/a.mp4?t=1',
        identity: 'film:1',
      );
      final second = PlaybackSource.network(
        'https://cdn.example.com/a.mp4?t=2',
        identity: 'film:1',
      );
      expect(first.identity, second.identity);
      expect(first.toRoomMedia().containsKey('headers'), isFalse);
    },
  );
}
