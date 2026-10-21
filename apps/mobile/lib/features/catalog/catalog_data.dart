import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'media_provider.dart';

const catalogKinds = ['电影', '电视剧', '动漫', '短剧'];
const categoryIds = {'电影': 1, '电视剧': 2, '动漫': 4, '短剧': 21};

class CatalogFeed extends ChangeNotifier {
  CatalogFeed({this.fetch, this.onItems, this.items = const []});
  Future<CatalogPage> Function(int page)? fetch;
  final void Function(Iterable<Film>)? onItems;
  List<Film> items;
  bool loading = false, loaded = false, hasMore = false, _disposed = false;
  String? error;
  int page = 0;
  int _generation = 0;

  Future<void> replace(Future<CatalogPage> Function(int page) loader) async {
    ++_generation;
    fetch = loader;
    items = const [];
    loading = loaded = hasMore = false;
    page = 0;
    error = null;
    await load();
  }

  Future<void> load({bool next = false, bool refresh = false}) async {
    if (_disposed || fetch == null || loading) return;
    if (next ? !hasMore : loaded && !refresh) return;
    loading = true;
    final request = ++_generation;
    error = null;
    notifyListeners();
    try {
      final value = await fetch!(next ? page + 1 : 1);
      if (_disposed || request != _generation) return;
      items = {
        if (next)
          for (final film in items) film.id: film,
        for (final film in value.items) film.id: film,
      }.values.toList();
      page = value.page;
      hasMore = value.hasMore;
      loaded = true;
      onItems?.call(items);
    } catch (_) {
      if (!_disposed && request == _generation) error = '片库加载失败，请检查网络后重试';
    } finally {
      if (!_disposed && request == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class CatalogData extends ChangeNotifier {
  CatalogData(this.provider, void Function(Iterable<Film>) remember) {
    final provider = this.provider;
    const order = ['mountains', 'stars', 'summer', 'clouds'];
    home = CatalogFeed(
      items: provider == null
          ? [for (final id in order) films.firstWhere((film) => film.id == id)]
          : const [],
      fetch: provider == null
          ? null
          : (_) async => CatalogPage(
              await provider.recommendations(),
              page: 1,
              pages: 1,
            ),
      onItems: remember,
    );
    for (final kind in catalogKinds) {
      categories[kind] = CatalogFeed(
        items: provider == null
            ? films.where((film) => film.kind == kind).toList()
            : const [],
        fetch: provider == null
            ? null
            : (page) => provider.browse(categoryIds[kind]!, page: page),
        onItems: remember,
      );
    }
    for (final feed in [home, ...categories.values]) {
      feed.addListener(notifyListeners);
    }
  }
  late final CatalogFeed home;
  final MediaProvider? provider;
  final filterOptions = <int, Map<String, List<String>>>{};
  bool _disposed = false, _navLoading = false;
  String? navigationError;
  bool get remoteFilters => provider is FilteredMediaProvider;
  final categories = <String, CatalogFeed>{};
  CatalogFeed category(String kind) => categories[kind]!;
  Future<void> loadFilters() async {
    if (!remoteFilters || _disposed || _navLoading || filterOptions.isNotEmpty)
      return;
    _navLoading = true;
    navigationError = null;
    try {
      final values = await provider!.categories();
      if (!_disposed) {
        for (final value in values) {
          filterOptions[value.id] = value.filters;
        }
      }
    } catch (_) {
      if (!_disposed) navigationError = '筛选条件加载失败';
    } finally {
      _navLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> filter(String kind, CatalogFilter filter) async {
    final source = provider;
    if (source is! FilteredMediaProvider || _disposed) return;
    await category(kind).replace(
      (page) => source.browseFiltered(categoryIds[kind]!, filter, page: page),
    );
  }

  Future<void> load() async {
    await Future.wait([home.load(), loadFilters()]);
    if (_disposed) return;
    for (final feed in categories.values) {
      await feed.load();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final feed in [home, ...categories.values]) {
      feed.removeListener(notifyListeners);
      feed.dispose();
    }
    super.dispose();
  }
}
