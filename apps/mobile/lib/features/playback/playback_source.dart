import 'dart:convert';

/// 来源身份与短期拉流地址分离，媒体请求头不继承账户 API 的鉴权信息。
class PlaybackSource {
  PlaybackSource._(
    this.uri,
    this.title,
    this.identity,
    this.headers,
    this.isHls,
  );
  final Uri uri;
  final String title;
  final String identity;
  final Map<String, String> headers;
  final bool isHls;

  factory PlaybackSource.network(
    String value, {
    String title = '正在播放',
    String? identity,
    Map<String, String> headers = const {},
    bool? hls,
  }) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        value.length > 4096) {
      throw const FormatException('请输入有效的 HTTP/HTTPS 视频地址，不要包含账户密码或片段。');
    }
    if (headers.length > 20) throw const FormatException('请求头过多。');
    for (final entry in headers.entries) {
      if (!RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(entry.key) ||
          entry.value.length > 4096 ||
          RegExp(r'[\r\n\x00]').hasMatch(entry.value)) {
        throw const FormatException('媒体请求头格式无效。');
      }
    }
    final id =
        identity ??
        'url:${base64Url.encode(utf8.encode(uri.replace(query: '').toString()))}';
    if (id.length > 1024 || RegExp(r'[\x00-\x1f]').hasMatch(id))
      throw const FormatException('媒体标识无效。');
    return PlaybackSource._(
      uri,
      title.trim().isEmpty ? '正在播放' : title.trim(),
      id,
      Map.unmodifiable(headers),
      hls ?? uri.path.toLowerCase().endsWith('.m3u8'),
    );
  }
  factory PlaybackSource.local(String filename, {String? title}) {
    final uri = Uri.file(filename);
    if (!uri.hasAbsolutePath) throw const FormatException('本地文件路径无效。');
    return PlaybackSource._(
      uri,
      title ?? uri.pathSegments.last,
      'local:${uri.pathSegments.last}',
      const {},
      false,
    );
  }
  String get displayLocation => uri.scheme == 'file'
      ? uri.pathSegments.last
      : '${uri.scheme}://${uri.authority}${uri.path}';
  Map<String, Object> toRoomMedia() {
    if (uri.scheme == 'file' || headers.isNotEmpty)
      throw const FormatException('同步使用双方均可访问、无需私有请求头的视频地址。');
    return {
      'uri': uri.toString(),
      'identity': identity,
      'title': title,
      'hls': isHls,
    };
  }
}
