class ArtworkRequest {
  const ArtworkRequest(this.uri, {this.headers = const {}});
  final Uri uri;
  final Map<String, String> headers;

  static const _httpsUpgrades = {
    'm.ykimg.com',
    'pic0.iqiyipic.com',
    'pic1.iqiyipic.com',
    'pic2.iqiyipic.com',
    'pic3.iqiyipic.com',
    'pic4.iqiyipic.com',
    'pic5.iqiyipic.com',
    'pic6.iqiyipic.com',
    'pic7.iqiyipic.com',
    'pic8.iqiyipic.com',
    'pic9.iqiyipic.com',
    'puui.qpic.cn',
    'i0.hdslb.com',
    'images.imgzy1.com',
  };
  // 2026-10-24 上游 293 张海报全量扫描后仅此域名需要明文：https 443 对
  // Dart/schannel/openssl 多套 TLS 栈握手均失败（服务端侧问题），而 http
  // 明文实测 200 image/jpeg。仅精确放行该域名的 http，其余仍强制 https。
  static const _plaintextImageHosts = {'snzypic.com'};
  // 豆瓣对无 Referer 请求返回 418；img9 与 img1-3 同策略（img9 已实测加头后 200）。
  static const _doubanHosts = {
    'img1.doubanio.com',
    'img2.doubanio.com',
    'img3.doubanio.com',
    'img9.doubanio.com',
  };
  static const browserAgent =
      'Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  // parse 在每个封面 build 里都会调用；正则只编译一次。
  static final _controlChars = RegExp(r'[\x00-\x1f]');

  static ArtworkRequest? parse(String? value) {
    if (value == null ||
        value.length > 8192 ||
        _controlChars.hasMatch(value))
      return null;
    var uri = Uri.tryParse(value.trim());
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
      final target = Uri.tryParse(uri.queryParameters['url'] ?? '');
      if (target != null &&
          target.scheme == 'https' &&
          target.port == 443 &&
          _doubanHosts.contains(target.host)) {
        uri = target;
      }
    }
    // 仅升级已逐条实测支持 HTTPS 的精确图片域（2026-10-23 用上游真实图片路径复测
    // pic0-pic9 全部 200 image/jpeg；2026-10-24 扫描补入 puui/hdslb/imgzy1 各 200），
    // 不放开全局明文网络，也不做子域通配。
    if (uri.scheme == 'http' &&
        _httpsUpgrades.contains(uri.host) &&
        uri.port == 80) {
      uri = uri.replace(scheme: 'https', port: 443);
    }
    final plaintextAllowed =
        uri.scheme == 'http' &&
        _plaintextImageHosts.contains(uri.host) &&
        uri.port == 80;
    if (uri.scheme != 'https' && !plaintextAllowed) return null;
    return ArtworkRequest(
      uri,
      headers: _doubanHosts.contains(uri.host) && uri.port == 443
          ? const {
              'User-Agent': browserAgent,
              'Referer': 'https://movie.douban.com/',
            }
          : const {},
    );
  }
}
