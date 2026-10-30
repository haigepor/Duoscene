import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/session.dart';
import 'artwork_request.dart';
import 'catalog.dart';
import 'catalog_data.dart';
import 'media_provider.dart';
import 'providers/whisklet_provider.dart';

class WatchEntry {
  const WatchEntry(
    this.filmId,
    this.seconds,
    this.episode, {
    this.shared = false,
    this.lineCode,
  });
  final String filmId;
  final int seconds, episode;
  final bool shared;
  final String? lineCode;
  String get key => '$filmId:${shared ? 'shared' : 'personal'}';
  Map<String, Object> toJson() => {
    'film': filmId,
    'seconds': seconds,
    'episode': episode,
    'shared': shared,
    if (lineCode != null) 'line': lineCode!,
  };
}

class LibraryState extends ChangeNotifier {
  LibraryState.guest({MediaProvider? provider})
    : this(accountId: 'local-guest', provider: provider ?? WhiskletProvider());

  LibraryState({
    required this.accountId,
    this.session,
    this.preview = false,
    MediaProvider? provider,
  }) : provider = preview
           ? null
           : provider ?? (session == null ? null : WhiskletProvider()) {
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
  bool get isGuest => !preview && accountId == 'local-guest';
  final MediaProvider? provider;
  late final catalog = CatalogData(provider, remember);
  final Map<String, Film> snapshots = {};
  Iterable<Film> get knownFilms => {
    for (final id in {
      ...films.map((film) => film.id),
      ...snapshots.keys,
      ...favorites,
    })
      id: filmById(id),
  }.values;
  Film filmById(String id) =>
      snapshots[id] ??
      films.where((film) => film.id == id).firstOrNull ??
      Film(id, '片目暂不可用', '影片', '', 0);
  void remember(Iterable<Film> items) {
    for (final film in items) {
      snapshots[film.id] = film;
    }
  }

  final Set<String> favorites = {};
  final List<WatchEntry> history = [];
  bool loaded = false, _disposed = false;
  double movieVolume = .7, voiceVolume = .6;
  String scenario = 'normal';
  Future<void> _writes = Future.value();
  String get displayName => preview
      ? '知夏'
      : isGuest
      ? '访客'
      : session?.user?.displayName ?? '私有账户';
  String get initial => displayName.isEmpty
      ? '我'
      : String.fromCharCodes(displayName.runes.take(1));
  String get storageKey => 'duoscene.library.v1.$accountId';

  Future<void> restore() async {
    if (loaded) return;
    if (!preview) {
      try {
        final prefs = await SharedPreferences.getInstance();
        ArtworkRequest.importLearnedRules(
          prefs.getString(ArtworkRequest.storageKey),
        );
        ArtworkRequest.onRulesChanged ??= (rawJson) {
          unawaited(
            SharedPreferences.getInstance()
                .then((p) => p.setString(ArtworkRequest.storageKey, rawJson))
                .catchError((Object _) => false),
          );
        };
        final raw = prefs.getString(
          storageKey,
        );
        if (raw != null) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          for (final row in (data['snapshots'] as List? ?? const [])) {
            try {
              final film = Film.fromJson(Map<String, dynamic>.from(row as Map));
              snapshots[film.id] = film;
            } catch (_) {}
          }
          favorites.addAll((data['favorites'] as List).cast<String>());
          for (final row in (data['history'] as List)) {
            history.add(
              WatchEntry(
                row['film'] as String,
                row['seconds'] as int,
                row['episode'] as int,
                shared: row['shared'] as bool,
                lineCode: row['line'] as String?,
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
      'snapshots': [
        for (final film in snapshots.values)
          if (favorites.contains(film.id) ||
              history.any((entry) => entry.filmId == film.id))
            film.toJson(),
      ],
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
    remember([film]);
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

  /// 双击当前底栏标签回顶：由壳层递增，页面自行订阅并滚动到顶部。
  /// 用信号而不是直接持有各页的 ScrollController，避免壳层依赖子页实现。
  final scrollTopRequest = ValueNotifier(0);
  void requestScrollTop() => scrollTopRequest.value++;

  @override
  void dispose() {
    _disposed = true;
    scrollTopRequest.dispose();
    catalog.dispose();
    provider?.close();
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
  int page = 0;
  bool hasMore = false;
  String? kind;
  void invalidate() {
    ++_generation;
  }

  Future<void> search(String value, {bool next = false}) async {
    if (next && (loading || !hasMore)) return;
    query = value;
    final current = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final repo = repository;
      final CatalogPage? response;
      if (repo is MediaProvider) {
        response = value.trim().isEmpty
            ? kind == null
                  ? CatalogPage(await repo.recommendations(), page: 1, pages: 1)
                  : await repo.browse(
                      categoryIds[kind]!,
                      page: next ? page + 1 : 1,
                    )
            : await repo.searchPage(value, page: next ? page + 1 : 1);
      } else {
        response = null;
      }
      final items = response?.items ?? await repository.search(value);
      if (_disposed || current != _generation) return;
      results = {
        if (next)
          for (final film in results) film.id: film,
        for (final film in items) film.id: film,
      }.values.toList();
      page = response?.page ?? 1;
      hasMore = response?.hasMore ?? false;
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
