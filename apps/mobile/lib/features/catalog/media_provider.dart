import '../playback/playback_source.dart';
import 'catalog.dart';

class MediaCategory {
  const MediaCategory(this.id, this.name, {this.filters = const {}});
  final int id;
  final String name;
  final Map<String, List<String>> filters;
}

class CatalogFilter {
  const CatalogFilter({this.genre, this.area, this.language, this.year});
  final String? genre, area, language, year;
  Map<String, String> get parameters => {
    if (genre != null) 'class': genre!,
    if (area != null) 'area': area!,
    if (language != null) 'lang': language!,
    if (year != null) 'year': year!,
  };
}

class CatalogPage {
  const CatalogPage(this.items, {required this.page, required this.pages});
  final List<Film> items;
  final int page, pages;
  bool get hasMore => page < pages;
}

class MediaEpisode {
  const MediaEpisode(this.name, this.token);
  final String name, token;
}

class MediaLine {
  const MediaLine({
    required this.code,
    required this.name,
    required this.episodes,
    required this.parser,
    this.headers = const {},
  });
  final String code, name, parser;
  final List<MediaEpisode> episodes;
  final Map<String, String> headers;
  bool get direct => parser.trim().isEmpty;
}

class MediaDetail {
  const MediaDetail(this.film, this.lines);
  final Film film;
  final List<MediaLine> lines;
}

abstract interface class MediaProvider implements CatalogRepository {
  String get id;
  String get name;
  Future<List<MediaCategory>> categories();
  Future<List<Film>> recommendations();
  Future<CatalogPage> browse(int category, {int page = 1});
  Future<CatalogPage> searchPage(String query, {int page = 1});
  Future<MediaDetail> detail(String filmId);
  Future<PlaybackSource> resolve(
    String filmId, {
    required int episode,
    String? lineCode,
  });
  void close();
}

abstract interface class FilteredMediaProvider implements MediaProvider {
  Future<CatalogPage> browseFiltered(
    int category,
    CatalogFilter filter, {
    int page = 1,
  });
}
