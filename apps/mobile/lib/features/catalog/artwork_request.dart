import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef ArtworkProbe =
    Future<bool> Function(Uri uri, Map<String, String> headers);

class ArtworkRequest {
  const ArtworkRequest(this.uri, {this.headers = const {}});
  final Uri uri;
  final Map<String, String> headers;

  static const storageKey = 'duoscene.artwork.rules.v1';

  // 2026-10-24 上游 293 张海报全量扫描后仅此域名需要明文：https 443 对
  // Dart/schannel/openssl 多套 TLS 栈握手均失败（服务端侧问题），而 http
  // 明文实测 200 image/jpeg。仅精确放行该域名的 http，其余仍强制 https。
  static const _plaintextImageHosts = {'snzypic.com'};
  // 上游资源站图床域名迁移但存量片单仍返回旧域（旧域已 DNS 污染、TLS 重置或 502），
  // 同一对象存储路径在对应现役 CDN 域名下实测直连 200。仅对标准端口做精确 host 替换。
  static const _migratedImageHosts = {
    'ps.ryzypics.com': 'pic.ry-pic.com', // 如意资源（短剧等）
    'pic.lzzypic.com': 'p.lztutu.com', // 量子资源
    'img.lzzyimg.com': 'p.lztutu.com', // 量子资源
    'viptulz.com': 'p.lztutu.com', // 量子资源
    'vip.dytt-img.com': 'img.dytt-tupian.com', // 电影天堂资源
    'vod.dyttimage.com': 'img.dytt-tupian.com', // 电影天堂资源
  };
  // 现役验证可用的 MacCMS /upload/vod/ 图床种子域，配合目录响应动态采集的活跃域，
  // 在未知旧域失效时按同源家族优先顺序自动探测并落盘自愈映射。
  static const _seedVodCdnHosts = [
    'pic.ry-pic.com',
    'p.lztutu.com',
    'img.dytt-tupian.com',
    'img.lzipic.com',
    'pic3.yzzyimg.online',
    'img.jisuimage.com',
  ];
  // 豆瓣对无 Referer 请求返回 418；img9 与 img1-3 同策略（img9 已实测加头后 200）。
  static const _doubanHosts = {
    'img1.doubanio.com',
    'img2.doubanio.com',
    'img3.doubanio.com',
    'img9.doubanio.com',
  };
  // 网易云音乐图床对默认 Dart UA 返回 403，仅需附带公开浏览器 UA 即可 200。
  static const _browserAgentHosts = {
    'p1.music.126.net',
    'p2.music.126.net',
    'p3.music.126.net',
    'p4.music.126.net',
  };
  static const browserAgent =
      'Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  static final _learnedHostMigrations = <String, String>{};
  static final _learnedBrowserAgentHosts = <String>{};
  static final _observedVodCdnHosts = <String>{..._seedVodCdnHosts};
  static final _failedVodCdnHosts = <String>{};
  static final _pendingHeals = <String, Future<bool>>{};

  /// 供应用状态层挂载本机持久化回调，自愈学习到的域名规则在重启后继续生效。
  static void Function(String rawJson)? onRulesChanged;

  /// 供单测/组件测试注入探测函数，不依赖真实外网套接字。
  static ArtworkProbe? debugProbe;

  static Map<String, String> get learnedHostMigrations =>
      Map.unmodifiable(_learnedHostMigrations);

  static Set<String> get observedVodCdnHosts =>
      Set.unmodifiable(_observedVodCdnHosts);

  // parse 在每个封面 build 里都会调用；正则只编译一次。
  static final _controlChars = RegExp(r'[\x00-\x1f]');
  static final _escapedAmp = RegExp(r'&(?:amp;)+');
  static final _safeHost = RegExp(r'^[a-z0-9.-]+$');

  static bool _isValidHost(String host) =>
      host.isNotEmpty &&
      host.length <= 253 &&
      _safeHost.hasMatch(host) &&
      !host.startsWith('.') &&
      !host.endsWith('.');

  /// 从上游片单原始 URL 中采集现役 `/upload/vod/` 图床域名，作为后续未知旧域
  /// 失效时的自动探测候选池。
  static void observeCatalogUrl(String? value) {
    if (value == null || value.length > 8192 || _controlChars.hasMatch(value)) {
      return;
    }
    final raw = value.trim().replaceAll(_escapedAmp, '&');
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return;
    }
    final host = uri.host.toLowerCase();
    if (!_isValidHost(host) ||
        _plaintextImageHosts.contains(host) ||
        _migratedImageHosts.containsKey(host) ||
        _learnedHostMigrations.containsKey(host) ||
        _failedVodCdnHosts.contains(host)) {
      return;
    }
    final standardPort = !uri.hasPort || uri.port == 443 || uri.port == 80;
    final allowedScheme =
        uri.scheme.isEmpty || uri.scheme == 'https' || uri.scheme == 'http';
    if (allowedScheme && standardPort && uri.path.startsWith('/upload/vod/')) {
      if (_observedVodCdnHosts.length >= 32 &&
          !_observedVodCdnHosts.contains(host)) {
        final removable = _observedVodCdnHosts
            .where((item) => !_seedVodCdnHosts.contains(item))
            .firstOrNull;
        if (removable != null) _observedVodCdnHosts.remove(removable);
      }
      _observedVodCdnHosts.add(host);
    }
  }

  /// 记录已验证可用的图床域名迁移规则，并通知持久化层落盘。
  static void learnHostMigration(String fromHost, String toHost) {
    final from = fromHost.trim().toLowerCase();
    final to = toHost.trim().toLowerCase();
    if (!_isValidHost(from) || !_isValidHost(to) || from == to) return;
    _failedVodCdnHosts.add(from);
    if (!_seedVodCdnHosts.contains(from)) {
      _observedVodCdnHosts.remove(from);
    }
    _observedVodCdnHosts.add(to);
    if (_learnedHostMigrations[from] == to) return;
    _learnedHostMigrations[from] = to;
    _notifyRulesChanged();
  }

  /// 记录需要浏览器 User-Agent 才放行的图床域名。
  static void learnBrowserAgentHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (!_isValidHost(normalized) || _doubanHosts.contains(normalized)) return;
    if (!_learnedBrowserAgentHosts.add(normalized)) return;
    _notifyRulesChanged();
  }

  static String exportLearnedRules() => jsonEncode({
    'migrations': _learnedHostMigrations,
    'browserAgentHosts': _learnedBrowserAgentHosts.toList(),
    'observedVodHosts': _observedVodCdnHosts.toList(),
  });

  static void importLearnedRules(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return;
      final migrations = decoded['migrations'];
      if (migrations is Map) {
        for (final entry in migrations.entries) {
          final from = entry.key.toString().trim().toLowerCase();
          final to = entry.value.toString().trim().toLowerCase();
          if (_isValidHost(from) && _isValidHost(to) && from != to) {
            _learnedHostMigrations[from] = to;
            _failedVodCdnHosts.add(from);
            _observedVodCdnHosts.add(to);
          }
        }
      }
      final browserHosts = decoded['browserAgentHosts'];
      if (browserHosts is List) {
        for (final item in browserHosts) {
          final host = item.toString().trim().toLowerCase();
          if (_isValidHost(host) && !_doubanHosts.contains(host)) {
            _learnedBrowserAgentHosts.add(host);
          }
        }
      }
      final observed = decoded['observedVodHosts'];
      if (observed is List) {
        for (final item in observed) {
          final host = item.toString().trim().toLowerCase();
          if (_isValidHost(host) &&
              !_migratedImageHosts.containsKey(host) &&
              !_learnedHostMigrations.containsKey(host) &&
              !_failedVodCdnHosts.contains(host) &&
              _observedVodCdnHosts.length < 32) {
            _observedVodCdnHosts.add(host);
          }
        }
      }
    } catch (_) {
      // 损坏的缓存规则直接忽略，保留内置静态规则。
    }
  }

  static void resetLearnedRulesForTest() {
    _learnedHostMigrations.clear();
    _learnedBrowserAgentHosts.clear();
    _failedVodCdnHosts.clear();
    _pendingHeals.clear();
    _observedVodCdnHosts
      ..clear()
      ..addAll(_seedVodCdnHosts);
    debugProbe = null;
    onRulesChanged = null;
  }

  static void _notifyRulesChanged() {
    final callback = onRulesChanged;
    if (callback != null) {
      callback(exportLearnedRules());
    }
  }

  static int _familyAffinity(String failedHost, String candidateHost) {
    const families = ['ry', 'lz', 'dytt', 'yz', 'jisu', 'js', 'sn'];
    for (final token in families) {
      if (failedHost.contains(token) && candidateHost.contains(token)) {
        return 0;
      }
    }
    return 1;
  }

  /// 针对失效的 `/upload/vod/` 封面地址生成按同源家族优先级排序的候选新域名地址。
  static List<Uri> candidateFallbackUris(Uri failedUri) {
    if (failedUri.scheme != 'https' ||
        failedUri.port != 443 ||
        !failedUri.path.startsWith('/upload/vod/')) {
      return const [];
    }
    final failedHost = failedUri.host.toLowerCase();
    final orderedHosts = <String>[];
    final known =
        _learnedHostMigrations[failedHost] ?? _migratedImageHosts[failedHost];
    if (known != null && known != failedHost) {
      orderedHosts.add(known);
    }
    final remaining = _observedVodCdnHosts
        .where(
          (host) =>
              host != failedHost &&
              !_failedVodCdnHosts.contains(host) &&
              !orderedHosts.contains(host),
        )
        .toList();
    remaining.sort((a, b) {
      final scoreA = _familyAffinity(failedHost, a);
      final scoreB = _familyAffinity(failedHost, b);
      return scoreA != scoreB ? scoreA.compareTo(scoreB) : a.compareTo(b);
    });
    orderedHosts.addAll(remaining);
    return [
      for (final host in orderedHosts) failedUri.replace(host: host),
    ];
  }

  /// 当封面加载失败时自动探测候选活跃 CDN 域名或浏览器 UA：
  /// 一旦探测到返回有效图片响应的域名，立即写入 `_learnedHostMigrations` 并持久化。
  static Future<bool> healFailedRequest(
    Uri failedUri, {
    ArtworkProbe? probe,
  }) {
    final host = failedUri.host.toLowerCase();
    if (_learnedHostMigrations.containsKey(host)) {
      return Future.value(true);
    }
    final activeProbe = probe ?? debugProbe ?? _defaultProbe;
    return _pendingHeals.putIfAbsent(host, () async {
      try {
        if (failedUri.scheme == 'https' &&
            failedUri.port == 443 &&
            failedUri.path.startsWith('/upload/vod/')) {
          _failedVodCdnHosts.add(host);
          if (!_seedVodCdnHosts.contains(host)) {
            _observedVodCdnHosts.remove(host);
          }
          for (final candidate in candidateFallbackUris(failedUri)) {
            final headers = _headersForHost(candidate.host, candidate.port);
            if (await activeProbe(candidate, headers)) {
              learnHostMigration(host, candidate.host);
              return true;
            }
          }
        }
        if (failedUri.scheme == 'https' &&
            failedUri.port == 443 &&
            !_doubanHosts.contains(host) &&
            !_browserAgentHosts.contains(host) &&
            !_learnedBrowserAgentHosts.contains(host)) {
          if (await activeProbe(
            failedUri,
            const {'User-Agent': browserAgent},
          )) {
            learnBrowserAgentHost(host);
            return true;
          }
        }
        return false;
      } finally {
        unawaited(_pendingHeals.remove(host));
      }
    });
  }

  static Future<bool> _defaultProbe(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 3));
      headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-63');
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        return false;
      }
      final mime = response.headers.contentType?.mimeType.toLowerCase() ?? '';
      if (mime.contains('html') || mime.contains('json') || mime.contains('text')) {
        await response.drain<void>();
        return false;
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= 16) break;
      }
      if (bytes.length < 4) return false;
      return _looksLikeImageBytes(bytes) || mime.startsWith('image/');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static bool _looksLikeImageBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true; // JPEG
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true; // PNG
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true; // GIF
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true; // WebP
    }
    return false;
  }

  static Map<String, String> _headersForHost(String host, int port) {
    if (port != 443) return const {};
    if (_doubanHosts.contains(host)) {
      return const {
        'User-Agent': browserAgent,
        'Referer': 'https://movie.douban.com/',
      };
    }
    if (_browserAgentHosts.contains(host) ||
        _learnedBrowserAgentHosts.contains(host)) {
      return const {'User-Agent': browserAgent};
    }
    return const {};
  }

  static ArtworkRequest? parse(String? value) {
    if (value == null || value.length > 8192 || _controlChars.hasMatch(value))
      return null;
    // 上游 CMS 偶发将查询串中的 & 转义为 &amp;（如百度图片代理），解析前先还原。
    final raw = value.trim().replaceAll(_escapedAmp, '&');
    var uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment)
      return null;
    // 百度图片代理链（上游偶发）：静态解到目标豆瓣图直连。跟着 302 走会丢掉
    // 豆瓣防盗链 Referer 而 403，所以只在目标是已验证的豆瓣图片域时才解。
    if (uri.scheme == 'https' &&
        uri.host == 'image.baidu.com' &&
        uri.path == '/search/down') {
      String targetValue;
      try {
        targetValue = uri.queryParameters['url'] ?? '';
      } on FormatException {
        return null;
      }
      final target = Uri.tryParse(targetValue);
      if (target != null &&
          target.scheme == 'https' &&
          target.port == 443 &&
          _doubanHosts.contains(target.host)) {
        // 代理解包后重新校验，不能让内层地址绕过外层凭据/片段/控制字符规则。
        if (target.userInfo.isNotEmpty ||
            target.hasFragment ||
            _controlChars.hasMatch(targetValue))
          return null;
        uri = target;
      }
    }
    // 新 CDN 保持自动 HTTPS 规范化；仅上游验证的精确图片域使用明文 HTTP 80。
    // 非标准端口不猜测 TLS 入口，也不对 HTTPS 失败进行全局明文回退。
    final isPlaintextHost = _plaintextImageHosts.contains(uri.host);
    if (isPlaintextHost &&
        ((uri.scheme.isEmpty && !uri.hasPort) ||
            (uri.scheme == 'https' && uri.port == 443))) {
      uri = uri.replace(scheme: 'http', port: 80);
    }
    final plaintextAllowed =
        uri.scheme == 'http' && isPlaintextHost && uri.port == 80;
    if (uri.scheme.isEmpty && (!uri.hasPort || uri.port == 443)) {
      uri = uri.replace(scheme: 'https');
    } else if (uri.scheme == 'http' && uri.port == 80 && !plaintextAllowed) {
      uri = uri.replace(scheme: 'https', port: 443);
    }
    if (uri.scheme != 'https' && !plaintextAllowed) return null;
    final migratedHost =
        _migratedImageHosts[uri.host] ?? _learnedHostMigrations[uri.host];
    if (migratedHost != null && uri.scheme == 'https' && uri.port == 443) {
      uri = uri.replace(host: migratedHost);
    }
    return ArtworkRequest(
      uri,
      headers: _headersForHost(uri.host, uri.port),
    );
  }
}
