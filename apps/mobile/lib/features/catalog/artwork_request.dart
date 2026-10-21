class ArtworkRequest {
  const ArtworkRequest(this.uri, {this.headers = const {}});
  final Uri uri;
  final Map<String, String> headers;

  static const _httpsUpgrades = {'m.ykimg.com', 'pic7.iqiyipic.com'};
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
    // 仅升级已逐条实测支持 HTTPS 的精确图片域，不放开全局明文网络。
    if (uri.scheme == 'http' &&
        _httpsUpgrades.contains(uri.host) &&
        uri.port == 80) {
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
