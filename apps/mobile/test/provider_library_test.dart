import 'dart:convert';

import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'provider metadata and progress survive restart without media tokens',
    () async {
      const film = Film(
        'whisklet:42',
        'Remote sample',
        '电视剧',
        '剧情',
        40,
        episodes: 5,
        posterUrl: 'https://example.com/poster.jpg',
      );
      final first = LibraryState(accountId: 'a');
      await first.toggleFavorite(film);
      await first.record(
        const WatchEntry('whisklet:42', 24, 2, lineCode: 'direct'),
      );
      final restored = LibraryState(accountId: 'a');
      await restored.restore();
      expect(restored.filmById('whisklet:42').title, film.title);
      expect(restored.history.single.episode, 2);
      expect(restored.history.single.lineCode, 'direct');
      final stored = (await SharedPreferences.getInstance()).getString(
        restored.storageKey,
      )!;
      expect(stored, isNot(contains('parse_api')));
      expect(stored, isNot(contains('token')));
      final another = LibraryState(accountId: 'b');
      await another.restore();
      expect(another.favorites, isEmpty);
      first.dispose();
      restored.dispose();
      another.dispose();
    },
  );
  test('old v1 records and removed items remain readable', () async {
    SharedPreferences.setMockInitialValues({
      'duoscene.library.v1.old': jsonEncode({
        'favorites': ['missing'],
        'history': [
          {'film': 'missing', 'seconds': 5, 'episode': 1, 'shared': false},
        ],
      }),
    });
    final library = LibraryState(accountId: 'old');
    await library.restore();
    expect(library.filmById('missing').title, '片目暂不可用');
    expect(library.history.single.seconds, 5);
    library.dispose();
  });
}
