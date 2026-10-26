import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/experience/short_playback.dart';
import 'package:flutter_test/flutter_test.dart';

MediaLine line(
  String code,
  String name, {
  required List<String> episodes,
  String parser = '',
}) => MediaLine(
  code: code,
  name: name,
  parser: parser,
  episodes: [for (final (i, _) in episodes.indexed) MediaEpisode('$name${i + 1}', episodes[i])],
);

void main() {
  test('播放器默认选线：备用直链压到最后，正片解析线路优先', () {
    final detail = [
      line('backup', '备用', episodes: ['http://b/1.m3u8', 'http://b/2.m3u8']),
      line('dj1', '独家①', episodes: ['http://a/1.m3u8'], parser: 'http://p/jx?url='),
    ];
    final picked = preferredPlaybackLine(detail);
    expect(picked?.code, 'dj1');
  });

  test('续播线路优先于默认口味，即使是备用', () {
    final detail = [
      line('dj1', '独家①', episodes: ['http://a/1.m3u8'], parser: 'http://p/jx?url='),
      line('backup', '备用', episodes: ['http://b/1.m3u8']),
    ];
    final picked = preferredPlaybackLine(detail, resumeCode: 'backup');
    expect(picked?.code, 'backup');
  });

  test('只剩备用时仍然可用；空集数线路不参与', () {
    final detail = [
      line('empty', '独家②', episodes: const []),
      line('backup', '备用', episodes: ['http://b/1.m3u8']),
    ];
    expect(preferredPlaybackLine(detail)?.code, 'backup');
  });

  test('非备用里没有直链时取第一条非备用解析线路', () {
    final detail = [
      line('backup', '备用', episodes: ['http://b/1.m3u8']),
      line('dj2', '独家②', episodes: ['http://a/1.m3u8'], parser: 'http://p/jx?url='),
      line('dj1', '独家①', episodes: ['http://a/1.m3u8'], parser: 'http://p/jx?url='),
    ];
    expect(preferredPlaybackLine(detail)?.code, 'dj2');
  });

  test('同档位候选取集数最多的线路，平手保持上游顺序', () {
    final detail = [
      line('dj1', '独家①', episodes: ['http://a/1.m3u8'], parser: 'http://p/jx?url='),
      line(
        'dj2',
        '独家②',
        episodes: [
          'http://a/1.m3u8',
          'http://a/2.m3u8',
          'http://a/3.m3u8',
        ],
        parser: 'http://p/jx?url=',
      ),
      line('dj3', '独家③', episodes: ['http://a/1.m3u8'], parser: 'http://p/jx?url='),
    ];
    expect(preferredPlaybackLine(detail)?.code, 'dj2');
  });

  test('短剧选线：多集正片优先于多集备用', () {
    final detail = [
      line('backup', '备用', episodes: ['http://b/1', 'http://b/2', 'http://b/3']),
      line('dj1', '独家①', episodes: ['http://a/1', 'http://a/2'], parser: 'http://p/jx?url='),
    ];
    expect(preferredShortLine(detail)?.code, 'dj1');
  });

  test('短剧选线：正片只有单集时，多集备用保住连播', () {
    final detail = [
      line('backup', '备用', episodes: ['http://b/1', 'http://b/2', 'http://b/3']),
      line('dj1', '独家①', episodes: ['http://a/1'], parser: 'http://p/jx?url='),
    ];
    expect(preferredShortLine(detail)?.code, 'backup');
  });

  test('短剧选线：全部是备用时退回集数最多的备用', () {
    final detail = [
      line('dj0', '独家①', episodes: const []),
      line('backup', '备用', episodes: ['http://b/1', 'http://b/2']),
    ];
    expect(preferredShortLine(detail)?.code, 'backup');
  });
}
