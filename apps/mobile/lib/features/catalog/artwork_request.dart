class ArtworkRequest {
  const ArtworkRequest(this.uri, {this.headers = const {}});
  final Uri uri;
  final Map<String, String> headers;

  static const browserAgent =
      'Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  static ArtworkRequest? parse(String? value) {
    if (value == null ||
        value.length > 8192 ||
        RegExp(r'[\x00-\x1f]').hasMatch(value))
      return null;
    var uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment)
      return null;
    // 来源会增加新的图片 CDN：统一尝试 HTTPS，保留签名路径/查询，不降级明文或忽略证书。
    // 非标准 HTTP 端口无法推断对应 TLS 入口；协议相对地址只采用标准 HTTPS 端口。
    if (uri.scheme.isEmpty && (!uri.hasPort || uri.port == 443)) {
      uri = uri.replace(scheme: 'https');
    } else if (uri.scheme == 'http' && uri.port == 80) {
      uri = uri.replace(scheme: 'https', port: 443);
    }
    if (uri.scheme != 'https') return null;
    return ArtworkRequest(
      uri,
      headers:
          {'img1.doubanio.com', 'img2.doubanio.com'}.contains(uri.host) &&
              uri.port == 443
          ? const {
              'User-Agent': browserAgent,
              'Referer': 'https://movie.douban.com/',
            }
          : const {},
    );
  }
}
