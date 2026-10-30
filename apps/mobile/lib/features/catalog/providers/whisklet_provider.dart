import 'dart:async';
import 'dart:convert';

import '../catalog.dart';
import '../artwork_request.dart';
import '../media_provider.dart';
import '../../playback/playback_source.dart';
import 'whisklet_client.dart';
import 'whisklet_codec.dart';

class WhiskletProvider implements FilteredMediaProvider {
  WhiskletProvider({
    WhiskletClient? client,
    this.detailTtl = const Duration(seconds: 30),
    this.detailCacheCapacity = 24,
    DateTime Function()? now,
  }) : assert(detailCacheCapacity > 0),
       assert(!detailTtl.isNegative),
       client = client ?? WhiskletClient(),
       _now = now ?? DateTime.now;
  final WhiskletClient client;
  final Duration detailTtl;
  final int detailCacheCapacity;
  final DateTime Function() _now;
  final _details = <String, ({DateTime at, MediaDetail value})>{};
  final _pendingDetails = <String, Future<MediaDetail>>{};
  bool _closed = false;
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

  /// 同一线路同一集的直链短时缓存：上游 ajiami 解析耗时且波动大（重试
  /// 至多 8 轮），看门狗重试、换线再换回、连播回跳都是同一地址，命中即免
  /// 整段解析往返。容量很小，超出按插入序淘汰。
  final _resolvedCache = <String, PlaybackSource>{};
  static const _resolvedCacheLimit = 12;
  static const _resolvedCacheTtl = Duration(minutes: 10);
  final _resolvedCacheAt = <String, DateTime>{};

  PlaybackSource? _cacheGet(String identity) {
    final at = _resolvedCacheAt[identity];
    final value = _resolvedCache[identity];
    if (at == null || value == null) return null;
    if (DateTime.now().difference(at) > _resolvedCacheTtl) {
      _resolvedCache.remove(identity);
      _resolvedCacheAt.remove(identity);
      return null;
    }
    return value;
  }

  void _cachePut(String identity, PlaybackSource source) {
    if (_resolvedCache.length >= _resolvedCacheLimit &&
        !_resolvedCache.containsKey(identity)) {
      final oldest = _resolvedCacheAt.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _resolvedCache.remove(oldest);
      _resolvedCacheAt.remove(oldest);
    }
    _resolvedCache[identity] = source;
    _resolvedCacheAt[identity] = DateTime.now();
  }

  static final _htmlTags = RegExp(r'<[^>]*>');
  static final _escapedAmp = RegExp(r'&(?:amp;)+');

  static String _plain(Object? value) => (value?.toString() ?? '')
      .replaceAll(_htmlTags, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(_escapedAmp, '&')
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
    final raw = value?.toString();
    ArtworkRequest.observeCatalogUrl(raw);
    return ArtworkRequest.parse(raw)?.uri.toString();
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

  // 上游偶发把未配 parse_api 的 B 站/腾讯/爱奇艺/优酷/芒果网页播放页当作直链下发，
  // 若直接当作直连媒体源会被选为首选线路并导致播放器拉流报错。
  static const _webpageOnlyHosts = {
    'www.bilibili.com',
    'bilibili.com',
    'm.bilibili.com',
    'b23.tv',
    'v.qq.com',
    'm.v.qq.com',
    'www.iqiyi.com',
    'iqiyi.com',
    'm.iqiyi.com',
    'v.youku.com',
    'youku.com',
    'm.youku.com',
    'www.mgtv.com',
    'mgtv.com',
    'm.mgtv.com',
  };

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
        final PlaybackSource source;
        try {
          source = PlaybackSource.network(token);
        } catch (_) {
          throw const ProviderException('protocol', '线路包含无效媒体地址');
        }
        if (_webpageOnlyHosts.contains(source.uri.host.toLowerCase())) {
          continue;
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
      episodes: List.unmodifiable(episodes),
      parser: parser,
      headers: Map.unmodifiable(headers),
    );
  }

  @override
  Future<MediaDetail> detail(String filmId, {bool refresh = false}) async {
    if (_closed) throw const ProviderException('closed', '播放源已关闭');
    _vodId(filmId);
    final cached = _details.remove(filmId);
    if (!refresh && cached != null) {
      final age = _now().difference(cached.at);
      if (!age.isNegative && age < detailTtl) {
        _details[filmId] = cached;
        return cached.value;
      }
    }
    // 参照 Playra 的目录缓存与 pending 合并；不缓存解析后的时效媒体地址。
    return _pendingDetails.putIfAbsent(filmId, () => _fetchDetail(filmId));
  }

  Future<MediaDetail> _fetchDetail(String filmId) async {
    try {
      final value = await _readDetail(filmId);
      if (_closed) throw const ProviderException('closed', '播放源已关闭');
      _details[filmId] = (at: _now(), value: value);
      while (_details.length > detailCacheCapacity) {
        _details.remove(_details.keys.first);
      }
      return value;
    } finally {
      // 失败不缓存；同键等待者收到同一个失败后，下一次可重新请求。
      unawaited(_pendingDetails.remove(filmId));
    }
  }

  Future<MediaDetail> _readDetail(String filmId) async {
    final response = await client.detail(_vodId(filmId));
    final info = (response['data'] as Map)['vod_info'];
    if (info is! Map<String, dynamic> ||
        _number(info['vod_id']) != _vodId(filmId) ||
        info['vod_url_with_player'] is! List)
      throw const ProviderException('protocol', '影片详情不完整，请重试');
    final lines = <String, MediaLine>{};
    ProviderException? lastLineError;
    for (final row in info['vod_url_with_player'] as List) {
      if (row is! Map<String, dynamic>) continue;
      try {
        final line = parseLine(row);
        lines[line.code] = line;
      } on ProviderException catch (error) {
        // 单条脏线路不阻断其余可用线路；仅当所有线路均解析异常时上抛。
        lastLineError = error;
      }
    }
    if (lines.isEmpty && lastLineError != null) throw lastLineError;
    final usable = List<MediaLine>.unmodifiable(
      lines.values.where((line) => line.episodes.isNotEmpty),
    );
    return MediaDetail(
      _film(
        info,
        // 各线路集数表不齐，集数统一以拥有最新集数的线路为准（取最大值），
        // 播放侧由 resolve 按集号跨线路落点，展示层不再按当前线路收窄。
        episodes: usable.isEmpty
            ? 1
            : usable
                  .map((line) => line.episodes.length)
                  .reduce((a, b) => a > b ? a : b),
      ),
      usable,
    );
  }

  @override
  Future<PlaybackSource> resolve(
    String filmId, {
    required int episode,
    String? lineCode,
    MediaDetail? cachedDetail,
  }) async {
    // 上游详情接口较慢：调用方已持有详情（详情页/选集切换）时直接复用，
    // 省掉一次重复的网络往返。
    final current = cachedDetail ?? await detail(filmId);
    // 各线路集数表独立；只有真正拥有该集的线路才参与解析。
    final playable = current.lines
        .where((line) => episode >= 1 && episode <= line.episodes.length)
        .toList();
    if (playable.isEmpty)
      throw const ProviderException('unavailable', '线路或剧集已更新，请重新选择');
    final selected = lineCode == null
        ? playable.first
        : playable.where((line) => line.code == lineCode).firstOrNull ??
              playable.first;
    // 同线路同集命中短时缓存直接返回（直链短时有效，TTL 10 分钟内）。
    final identity = '$filmId:${selected.code}:$episode';
    final cached = _cacheGet(identity);
    if (cached != null) return cached;
    // 上游 ajiami 解析会随机返回截断参数（2026-10-23 实测仅约 16% 为有效长度），
    // 首选线路重试耗尽时依次落到其余可用线路，全部失败才上抛首选线路的错误。
    final candidates = [
      selected,
      ...playable.where((line) => line.code != selected.code),
    ];
    ProviderException? primaryFailure;
    for (final candidate in candidates) {
      try {
        final source = await _resolveOn(current, candidate, filmId, episode);
        if (identical(candidate, selected)) _cachePut(identity, source);
        return source;
      } on ProviderException catch (error) {
        if (identical(candidate, selected)) primaryFailure = error;
        // 连接、超限与输入校验故障换线同样会失败，立即上抛；单线 secretParse 业务或协议
        // 错误则继续回退到其余可用线路（如直连 m3u8 备用线）。
        if (const {
          'network',
          'timeout',
          'http',
          'size',
          'closed',
          'input',
          'identity',
        }.contains(error.code)) {
          rethrow;
        }
      }
    }
    throw primaryFailure!;
  }

  Future<PlaybackSource> _resolveOn(
    MediaDetail current,
    MediaLine selected,
    String filmId,
    int episode,
  ) async {
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
          'qiyi': 120,
          'mgtv': 120,
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
  void close() {
    _closed = true;
    _details.clear();
    client.close();
  }
}
