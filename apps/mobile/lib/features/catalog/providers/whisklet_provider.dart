import 'dart:convert';

import '../catalog.dart';
import '../artwork_request.dart';
import '../media_provider.dart';
import '../../playback/playback_source.dart';
import 'whisklet_client.dart';
import 'whisklet_codec.dart';

class WhiskletProvider implements FilteredMediaProvider {
  WhiskletProvider({WhiskletClient? client})
    : client = client ?? WhiskletClient();
  final WhiskletClient client;
  @override
  String get id => 'whisklet';
  @override
  String get name => '第一播放源 · Whisklet';
  static const kinds = {
    1: '电影',
    2: '电视剧',
    4: '动漫',
    5: '综艺',
    20: '电视直播',
    21: '短剧',
    22: 'AI漫剧',
  };

  int _vodId(String value) {
    if (!RegExp(r'^whisklet:[1-9]\d*$').hasMatch(value))
      throw const ProviderException('identity', '片源标识无效');
    return int.parse(value.split(':').last);
  }

  static String _plain(Object? value) => (value?.toString() ?? '')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
  static int _number(Object? value, [int fallback = 0]) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;

  static Film _film(Map<String, dynamic> row, {int? episodes}) {
    final vodId = _number(row['vod_id']);
    final title = _plain(row['vod_name']);
    if (vodId <= 0 || title.isEmpty)
      throw const ProviderException('protocol', '片目数据不完整');
    final remarks = _plain(row['vod_remarks']);
    final count = RegExp(r'(\d+)\s*集').firstMatch(remarks)?.group(1);
    return Film(
      'whisklet:$vodId',
      title,
      kinds[_number(row['type_id_1']) > 0
              ? _number(row['type_id_1'])
              : _number(row['type_id'])] ??
          '影片',
      _plain(row['vod_class']),
      _number(row['vod_duration']),
      episodes: (episodes ?? _number(count, 1)).clamp(1, 100000),
      posterUrl: _poster(row['vod_pic']),
      remarks: remarks,
      synopsis: _plain(row['vod_content'] ?? row['vod_blurb']),
    );
  }

  static String? _poster(Object? value) {
    return ArtworkRequest.parse(value?.toString())?.uri.toString();
  }

  static List<Film> _items(List<dynamic> rows) {
    final items = <String, Film>{};
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        final film = _film(row);
        items.putIfAbsent(film.id, () => film);
      }
    }
    return items.values.toList();
  }

  static CatalogPage _page(Map<String, dynamic> response, int page) =>
      CatalogPage(
        _items(response['data'] as List),
        page: _number(response['page'], page),
        pages: _number(response['pagecount'], page),
      );

  @override
  Future<List<MediaCategory>> categories() async => [
    for (final row in (await client.nav())['data'] as List)
      if (row is Map && _number(row['type_id']) > 0)
        MediaCategory(
          _number(row['type_id']),
          _plain(row['type_name']),
          filters: _filters(row['type_extend']),
        ),
  ];
  static Map<String, List<String>> _filters(Object? value) {
    if (value is! Map) return const {};
    return Map.unmodifiable({
      for (final key in ['class', 'area', 'lang', 'year'])
        key: List<String>.unmodifiable(
          (value[key]?.toString() ?? '')
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty && item.length <= 200)
              .toSet(),
        ),
    });
  }

  @override
  Future<List<Film>> recommendations() async {
    final data = (await client.recommend())['data'] as Map;
    final groups = data['videos'];
    if (groups is! List) throw const ProviderException('protocol', '推荐片目不完整');
    return _items([
      for (final group in groups)
        if (group is Map && group['vlist'] is List) ...group['vlist'] as List,
    ]);
  }

  @override
  Future<CatalogPage> browse(int category, {int page = 1}) async =>
      _page(await client.videoList(category, page), page);
  @override
  Future<CatalogPage> browseFiltered(
    int category,
    CatalogFilter filter, {
    int page = 1,
  }) async => _page(
    await client.videoList(category, page, filters: filter.parameters),
    page,
  );
  @override
  Future<CatalogPage> searchPage(String query, {int page = 1}) async {
    if (query.trim().isEmpty)
      return CatalogPage(await recommendations(), page: 1, pages: 1);
    return _page(await client.search(query.trim(), page), page);
  }

  @override
  Future<List<Film>> search(String query) async =>
      (await searchPage(query)).items;

  static MediaLine parseLine(Map<String, dynamic> row) {
    final code = _plain(row['code']);
    final parser = (row['parse_api'] ?? '').toString().trim();
    if (code.isEmpty) throw const ProviderException('protocol', '播放线路缺少标识');
    final episodes = <MediaEpisode>[];
    for (final entry in (row['url'] ?? '').toString().split('#')) {
      final split = entry.indexOf(r'$');
      if (split <= 0 || split == entry.length - 1) continue;
      final token = entry.substring(split + 1).trim();
      if (parser.isEmpty) {
        try {
          PlaybackSource.network(token);
        } catch (_) {
          throw const ProviderException('protocol', '线路包含无效媒体地址');
        }
      }
      episodes.add(MediaEpisode(_plain(entry.substring(0, split)), token));
    }
    final headers = <String, String>{};
    Object? rawHeaders = row['headers'];
    if (rawHeaders is String && rawHeaders.trim().startsWith('{')) {
      try {
        rawHeaders = jsonDecode(rawHeaders);
      } catch (_) {
        rawHeaders = null;
      }
    }
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if ({
              'referer',
              'user-agent',
              'origin',
            }.contains(entry.key.toString().toLowerCase()) &&
            entry.value is String)
          headers[entry.key.toString()] = entry.value as String;
      }
    }
    return MediaLine(
      code: code,
      name: _plain(row['name']),
      episodes: episodes,
      parser: parser,
      headers: Map.unmodifiable(headers),
    );
  }

  @override
  Future<MediaDetail> detail(String filmId) async {
    final response = await client.detail(_vodId(filmId));
    final info = (response['data'] as Map)['vod_info'];
    if (info is! Map<String, dynamic> ||
        _number(info['vod_id']) != _vodId(filmId) ||
        info['vod_url_with_player'] is! List)
      throw const ProviderException('protocol', '影片详情不完整，请重试');
    final lines = {
      for (final row in info['vod_url_with_player'] as List)
        if (row is Map<String, dynamic>) parseLine(row).code: parseLine(row),
    }.values.where((line) => line.episodes.isNotEmpty).toList();
    return MediaDetail(
      _film(info, episodes: lines.isEmpty ? 1 : lines.first.episodes.length),
      lines,
    );
  }

  @override
  Future<PlaybackSource> resolve(
    String filmId, {
    required int episode,
    String? lineCode,
  }) async {
    final current = await detail(filmId);
    final selected = current.lines
        .where((line) => lineCode == null || line.code == lineCode)
        .firstOrNull;
    if (selected == null || episode < 1 || episode > selected.episodes.length)
      throw const ProviderException('unavailable', '线路或剧集已更新，请重新选择');
    final entry = selected.episodes[episode - 1];
    String url = entry.token;
    if (!selected.direct) {
      final parser = Uri.tryParse(selected.parser);
      if (parser == null ||
          !['http', 'https'].contains(parser.scheme) ||
          parser.userInfo.isNotEmpty)
        throw const ProviderException('parser', '解析地址无效');
      Uri target;
      if (parser.path.contains('/ajiami/')) {
        if (parser.host != WhiskletProfile.host ||
            parser.port != WhiskletProfile.port)
          throw const ProviderException('parser', '平台解析地址不在允许范围');
        const lengths = {
          'BBA': 800,
          'co': 88,
          'NBY': 288,
          'zijianm3u8': 172,
          'rose': 232,
          'youku': 144,
          'qq': 144,
        };
        final expected = lengths[selected.code];
        if (expected == null)
          throw const ProviderException('parser', '暂不支持此解析线路，请换线');
        String? param;
        for (var attempt = 0; attempt < 8; attempt++) {
          final response = await client.secretParse(entry.token, selected.code);
          final value = response['data'] as String;
          if (value.length == expected) {
            param = value;
            break;
          }
          if (attempt < 7)
            await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        if (param == null)
          throw const ProviderException('incomplete', '解析参数持续不完整，请重试或换线');
        target = parser.replace(
          queryParameters: {...parser.queryParameters, 'url': param},
        );
      } else {
        if (!selected.parser.endsWith('='))
          throw const ProviderException('parser', '外部解析模板不受支持');
        target = Uri.parse(selected.parser + Uri.encodeComponent(entry.token));
      }
      url = (await client.parse(target))['url'] as String;
    }
    try {
      return PlaybackSource.network(
        url,
        title: '${current.film.title} · ${selected.name} · ${entry.name}',
        identity: '$filmId:${selected.code}:$episode',
        headers: selected.headers,
      );
    } catch (_) {
      throw const ProviderException('media', '解析未返回有效媒体地址，请换线');
    }
  }

  @override
  void close() => client.close();
}
