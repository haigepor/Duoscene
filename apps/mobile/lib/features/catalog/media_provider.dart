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

  /// 各线路集数表不齐：集数统一以拥有最新集数的线路为准（取最大值）。
  /// 线路是可播集数的事实源；片目自带集数（上游 remark）可能虚标，仅作无线路时兜底。
  int get unifiedEpisodes => lines.isEmpty
      ? film.episodes
      : lines.map((line) => line.episodes.length).reduce((a, b) => a > b ? a : b);
  Film get unifiedFilm => film.withEpisodes(unifiedEpisodes);
}

/// 上游常把直链快取线路命名为「备用/备份/backup」，正片线路反而带解析模板；
/// 默认选线时必须把这类线路压到最后，否则播放器页面默认落在备用上。
bool isBackupLineName(String name) {
  final value = name.trim().toLowerCase();
  return value.contains('备用') ||
      value.contains('备份') ||
      value.contains('backup');
}

/// 播放器默认选线：续播指定线路 → 非备用的直链 → 非备用任意线路 →
/// 备用直链 → 任意可用线路；同档位候选取集数最多的线路（平手保持上游
/// 顺序）。空集数线路一律跳过。
MediaLine? preferredPlaybackLine(
  Iterable<MediaLine> lines, {
  String? resumeCode,
}) {
  final usable = lines.where((line) => line.episodes.isNotEmpty).toList();
  MediaLine? pick(bool Function(MediaLine line) test) {
    final candidates = usable.where(test).toList();
    return candidates.isEmpty
        ? null
        : candidates.reduce(
            (a, b) => b.episodes.length > a.episodes.length ? b : a,
          );
  }
  if (resumeCode != null) {
    final resume = pick((line) => line.code == resumeCode);
    if (resume != null) return resume;
  }
  return pick((line) => !isBackupLineName(line.name) && line.direct) ??
      pick((line) => !isBackupLineName(line.name)) ??
      pick((line) => line.direct) ??
      usable.firstOrNull;
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
    MediaDetail? cachedDetail,
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
