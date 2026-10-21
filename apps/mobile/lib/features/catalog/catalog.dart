import 'package:flutter/foundation.dart';

import '../playback/playback_source.dart';

class Film {
  const Film(
    this.id,
    this.title,
    this.kind,
    this.genre,
    this.minutes, {
    this.episodes = 1,
    this.art,
    this.posterUrl,
    this.remarks = '',
    this.synopsis = '越过山海，恰好遇见你。沿着记忆中的路，寻找那些值得一起留下的瞬间。',
  });
  final String id, title, kind, genre, synopsis;
  final String? art, posterUrl;
  final String remarks;
  final int minutes, episodes;
  bool get short => kind == '短剧';
  bool get remote => id.startsWith('whisklet:');
  Film withEpisodes(int count) => Film(
    id,
    title,
    kind,
    genre,
    minutes,
    episodes: count,
    art: art,
    posterUrl: posterUrl,
    remarks: remarks,
    synopsis: synopsis,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind,
    'genre': genre,
    'minutes': minutes,
    'episodes': episodes,
    'art': art,
    'posterUrl': posterUrl,
    'remarks': remarks,
    'synopsis': synopsis,
  };
  factory Film.fromJson(Map<String, dynamic> row) => Film(
    row['id'] as String,
    row['title'] as String,
    row['kind'] as String,
    row['genre'] as String,
    row['minutes'] as int,
    episodes: row['episodes'] as int,
    art: row['art'] as String?,
    posterUrl: row['posterUrl'] as String?,
    remarks: row['remarks'] as String? ?? '',
    synopsis: row['synopsis'] as String? ?? '',
  );
  String get image =>
      'assets/design/media/${art ?? (short ? 'frame-short-drama' : 'poster-$id')}.webp';
  String get meta => remote
      ? '$kind${remarks.isEmpty ? '' : ' · $remarks'}'
      : '$kind · ${episodes == 1 ? '$minutes 分钟' : '$episodes 集'}';
  String get durationLabel => episodes == 1 ? '完整正片' : '每集 $minutes 分钟';
}

const films = [
  Film('mountains', '山海之间', '电影', '剧情', 108),
  Film('summer', '风起的夏天', '电视剧', '治愈', 45, episodes: 12),
  Film('stars', '星海回声', '电影', '科幻', 126),
  Film('clouds', '云的另一边', '动漫', '冒险', 24, episodes: 12),
  Film(
    'short',
    '回到风起时',
    '短剧',
    '都市情感',
    2,
    episodes: 60,
    synopsis: '在熟悉的街角重逢，那些没说出口的话，终于有了答案。',
  ),
  Film('river', '沿河慢行', '电影', '治愈', 98, art: 'poster-mountains'),
  Film('orbit', '最后一道星光', '电影', '科幻', 112, art: 'poster-stars'),
  Film('rain', '雨后见晴', '电视剧', '情感', 42, episodes: 16, art: 'poster-summer'),
  Film(
    'letter',
    '未寄出的信',
    '电视剧',
    '悬疑',
    40,
    episodes: 8,
    art: 'poster-mountains',
  ),
  Film('island', '风的岛屿', '动漫', '冒险', 24, episodes: 12, art: 'poster-clouds'),
  Film('starlight', '星空邮局', '动漫', '治愈', 22, episodes: 10, art: 'poster-stars'),
  Film(
    'tomorrow',
    '明天再说喜欢你',
    '短剧',
    '都市情感',
    2,
    episodes: 48,
    art: 'frame-short-drama',
  ),
  Film('again', '重逢的第七天', '短剧', '悬疑', 3, episodes: 36, art: 'poster-summer'),
];

abstract interface class CatalogRepository {
  Future<List<Film>> search(String query);
}

class DesignCatalog implements CatalogRepository {
  @override
  Future<List<Film>> search(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return films
        .where(
          (f) =>
              f.title.contains(query.trim()) ||
              f.genre.contains(query.trim()) ||
              f.kind.contains(query.trim()),
        )
        .toList();
  }
}

// 受控测试地址只在调试构建注入；虚构片目的海报不提供可播放媒体。
PlaybackSource? designSource(Film film) {
  const url = String.fromEnvironment('UI_MEDIA_URL');
  if (!kDebugMode || url.isEmpty) return null;
  return PlaybackSource.network(url, title: '${film.title} · 测试样片');
}
