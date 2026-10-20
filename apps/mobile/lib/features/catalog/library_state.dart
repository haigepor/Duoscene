import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/session.dart';
import 'catalog.dart';

class WatchEntry {
  const WatchEntry(
    this.filmId,
    this.seconds,
    this.episode, {
    this.shared = false,
  });
  final String filmId;
  final int seconds, episode;
  final bool shared;
  String get key => '$filmId:${shared ? 'shared' : 'personal'}';
  Map<String, Object> toJson() => {
    'film': filmId,
    'seconds': seconds,
    'episode': episode,
    'shared': shared,
  };
}

class LibraryState extends ChangeNotifier {
  LibraryState({required this.accountId, this.session, this.preview = false}) {
    if (preview) {
      favorites.addAll(films.take(5).map((f) => f.id));
      history.addAll([
        const WatchEntry('summer', 1122, 3),
        const WatchEntry('short', 46, 8, shared: true),
        const WatchEntry('mountains', 2180, 1),
      ]);
    }
  }
  final String accountId;
  final Session? session;
  final bool preview;
  final Set<String> favorites = {};
  final List<WatchEntry> history = [];
  bool loaded = false, _disposed = false;
  double movieVolume = .7, voiceVolume = .6;
  String scenario = 'normal';
  Future<void> _writes = Future.value();
  String get displayName =>
      preview ? '知夏' : session?.user?.displayName ?? '私有账户';
  String get initial => displayName.isEmpty
      ? '我'
      : String.fromCharCodes(displayName.runes.take(1));
  String get storageKey => 'duoscene.library.v1.$accountId';

  Future<void> restore() async {
    if (loaded) return;
    if (!preview) {
      try {
        final raw = (await SharedPreferences.getInstance()).getString(
          storageKey,
        );
        if (raw != null) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          favorites.addAll((data['favorites'] as List).cast<String>());
          for (final row in (data['history'] as List)) {
            history.add(
              WatchEntry(
                row['film'] as String,
                row['seconds'] as int,
                row['episode'] as int,
                shared: row['shared'] as bool,
              ),
            );
          }
        }
      } catch (_) {
        /* 本机损坏数据不影响账户或网络登录。 */
      }
    }
    loaded = true;
    changed();
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> persist() {
    if (preview) return Future.value();
    final value = jsonEncode({
      'favorites': favorites.toList(),
      'history': history.map((e) => e.toJson()).toList(),
    });
    // 串行存储防止较早的清理或进度写入覆盖较新的用户操作。
    final operation = _writes.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, value))
        throw StateError('本机记录保存失败');
    });
    _writes = operation;
    return operation;
  }

  Future<void> toggleFavorite(Film film) async {
    if (!favorites.remove(film.id)) favorites.add(film.id);
    changed();
    await persist();
  }

  Future<void> record(WatchEntry entry) async {
    history.removeWhere((e) => e.key == entry.key);
    history.insert(0, entry);
    changed();
    await persist();
  }

  Future<void> removeHistory(Set<String> keys) async {
    history.removeWhere((e) => keys.contains(e.key));
    changed();
    await persist();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SearchState extends ChangeNotifier {
  SearchState(this.repository);
  final CatalogRepository repository;
  int _generation = 0;
  bool _disposed = false;
  bool loading = false;
  String query = '';
  String? error;
  List<Film> results = [];
  Future<void> search(String value) async {
    query = value;
    final current = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final items = await repository.search(value);
      if (_disposed || current != _generation) return;
      results = items;
    } catch (_) {
      if (_disposed || current != _generation) return;
      error = '搜索暂时不可用，请重试';
      results = [];
    } finally {
      if (!_disposed && current == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
