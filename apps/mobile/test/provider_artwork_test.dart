import 'dart:convert';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/artwork_request.dart';
import 'package:duoscene/features/catalog/artwork_image.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<Film> _filmWithPoster(String? url) async {
  final provider = WhiskletProvider(
    client: WhiskletClient(
      transport: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 1,
            'page': 1,
            'pagecount': 1,
            'data': [
              {
                'vod_id': 42,
                'vod_name': 'Poster policy fixture',
                'type_id': 1,
                'vod_pic': url,
              },
            ],
          }),
          200,
        ),
      ),
    ),
  );
  try {
    return (await provider.browse(1)).items.single;
  } finally {
    provider.close();
  }
}

void main() {
  test('verified img1 artwork uses the same isolated header loader', () {
    final request = ArtworkRequest.parse(
      'https://img1.doubanio.com/view/photo/s/public/p2557589889.jpg',
    )!;
    expect(request.headers['Referer'], 'https://movie.douban.com/');
    expect(request.headers['User-Agent'], ArtworkRequest.browserAgent);
    expect(
      ArtworkRequest.parse('https://img1.doubanio.com.evil.example/poster.jpg')!
          .headers,
      isEmpty,
    );
  });
  const browserAgent =
      'Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
  test(
    'artwork request preserves ordinary HTTPS query without site headers',
    () {
      const url = 'https://img.lzipic.com/cover.webp?width=480&quality=85';
      final request = ArtworkRequest.parse(url)!;
      expect(request.uri.toString(), url);
      expect(request.headers, isEmpty);
    },
  );

  for (final host in [
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
  ]) {
    for (final port in ['', ':80']) {
      test('verified artwork $host$port upgrades to standard HTTPS port', () {
        final request = ArtworkRequest.parse(
          'http://$host$port/cover.image?width=480',
        )!;
        expect(request.uri.toString(), 'https://$host/cover.image?width=480');
        expect(request.uri.port, 443);
        expect(request.headers, isEmpty);
      });
    }
    test('unverified artwork port on $host remains rejected', () {
      expect(ArtworkRequest.parse('http://$host:8080/cover.jpg'), isNull);
    });
  }

  test('only exact HTTPS Douban image host gets verified public headers', () {
    final request = ArtworkRequest.parse(
      'https://img2.doubanio.com/view/photo/poster.jpg?width=480',
    )!;
    expect(request.headers, {
      'User-Agent': browserAgent,
      'Referer': 'https://movie.douban.com/',
    });
    expect(
      request.headers.keys.map((key) => key.toLowerCase()).toSet().intersection(
        {'authorization', 'cookie', 'token', 'pk-id'},
      ),
      isEmpty,
    );
    for (final url in [
      'https://img2.doubanio.com.evil.example/poster.jpg',
      'https://sub.img2.doubanio.com/poster.jpg',
      'https://img2.doubanio.com:8443/poster.jpg',
      'https://pic3.yzzyimg.online/poster.jpg',
    ]) {
      expect(ArtworkRequest.parse(url)!.headers, isEmpty, reason: url);
    }
  });

  for (final url in <String?>[
    null,
    '',
    'http://unverified.example:8080/cover.jpg',
    'http://user:secret@cdn.example/cover.jpg',
    'http://cdn.example/cover.jpg#fragment',
    'https://account:secret@img2.doubanio.com/cover.jpg',
    'file:///storage/emulated/0/private.jpg',
    'data:image/png;base64,AA==',
    'javascript:alert(1)',
  ]) {
    test('artwork request rejects invalid or credentialed input $url', () {
      expect(ArtworkRequest.parse(url), isNull);
    });
  }

  test('baidu image proxy resolves to verified douban target with headers', () {
    const proxyUrl =
        'https://image.baidu.com/search/down?url=https://img3.doubanio.com/view/photo/s_ratio_poster/public/p2928250933.jpg';
    final request = ArtworkRequest.parse(proxyUrl)!;
    expect(
      request.uri.toString(),
      'https://img3.doubanio.com/view/photo/s_ratio_poster/public/p2928250933.jpg',
    );
    expect(request.headers, {
      'User-Agent': browserAgent,
      'Referer': 'https://movie.douban.com/',
    });
  });

  test('verified img3 artwork gets the same douban headers', () {
    final request = ArtworkRequest.parse(
      'https://img3.doubanio.com/view/photo/s_ratio_poster/public/p2928250933.jpg',
    )!;
    expect(request.headers, {
      'User-Agent': browserAgent,
      'Referer': 'https://movie.douban.com/',
    });
  });

  test('img9 douban host gets the same verified anti-hotlink headers', () {
    final request = ArtworkRequest.parse(
      'https://img9.doubanio.com/view/photo/s_ratio_poster/public/p2935035734.jpg',
    )!;
    expect(request.headers, {
      'User-Agent': browserAgent,
      'Referer': 'https://movie.douban.com/',
    });
    expect(
      ArtworkRequest.parse('https://img9.doubanio.com:8443/p.jpg')!.headers,
      isEmpty,
    );
  });

  test('snzypic plaintext image host is the only verified http allowance', () {
    for (final url in [
      'http://snzypic.com/upload/vod/20240103-1/37aa4b49.jpg',
      'https://snzypic.com/upload/vod/20240103-1/37aa4b49.jpg',
      '//snzypic.com/upload/vod/20240103-1/37aa4b49.jpg',
    ]) {
      final request = ArtworkRequest.parse(url)!;
      expect(request.uri.scheme, 'http', reason: url);
      expect(request.uri.host, 'snzypic.com', reason: url);
      expect(request.uri.port, 80, reason: url);
      expect(request.headers, isEmpty, reason: url);
    }
    expect(
      ArtworkRequest.parse('http://snzypic.com:8080/upload/vod/x.jpg'),
      isNull,
    );
    for (final url in [
      'http://snzypic.com.evil.example/upload/vod/x.jpg',
      'http://sub.snzypic.com/upload/vod/x.jpg',
    ]) {
      final request = ArtworkRequest.parse(url)!;
      expect(request.uri.scheme, 'https', reason: url);
      expect(request.headers, isEmpty, reason: url);
    }
  });

  test('migrated resource station image hosts rewrite to active CDN hosts', () {
    for (final sample in [
      (
        'https://ps.ryzypics.com/upload/vod/20251029-1/8079c5eb73230ca931b9834b1cb148ef.png',
        'https://pic.ry-pic.com/upload/vod/20251029-1/8079c5eb73230ca931b9834b1cb148ef.png',
      ),
      (
        'http://ps.ryzypics.com/upload/vod/20251029-1/8079c5eb73230ca931b9834b1cb148ef.png',
        'https://pic.ry-pic.com/upload/vod/20251029-1/8079c5eb73230ca931b9834b1cb148ef.png',
      ),
      (
        'https://pic.lzzypic.com/upload/vod/20260711-1/ef0294435d26386997a5fe7e9a3d5394.jpg',
        'https://p.lztutu.com/upload/vod/20260711-1/ef0294435d26386997a5fe7e9a3d5394.jpg',
      ),
      (
        'https://img.lzzyimg.com/upload/vod/20220329-1/d760d846c60a9aa2ef0a527dd6a9fe68.jpg',
        'https://p.lztutu.com/upload/vod/20220329-1/d760d846c60a9aa2ef0a527dd6a9fe68.jpg',
      ),
      (
        'https://viptulz.com/upload/vod/20250908-1/6fa89c8bc7c7f7c2685a2cf1df832a8a.jpg',
        'https://p.lztutu.com/upload/vod/20250908-1/6fa89c8bc7c7f7c2685a2cf1df832a8a.jpg',
      ),
      (
        'https://vip.dytt-img.com/upload/vod/20250304-1/ed94e4c49c2463a5f5ed0ab8fc6bc9cb.jpg',
        'https://img.dytt-tupian.com/upload/vod/20250304-1/ed94e4c49c2463a5f5ed0ab8fc6bc9cb.jpg',
      ),
      (
        'https://vod.dyttimage.com/upload/vod/20260126-1/a19947b699e08365b8b4986d6aa26cb3.jpg',
        'https://img.dytt-tupian.com/upload/vod/20260126-1/a19947b699e08365b8b4986d6aa26cb3.jpg',
      ),
    ]) {
      final request = ArtworkRequest.parse(sample.$1)!;
      expect(request.uri.toString(), sample.$2, reason: sample.$1);
      expect(request.headers, isEmpty, reason: sample.$1);
    }
    expect(
      ArtworkRequest.parse('https://ps.ryzypics.com:8443/upload/vod/a.png')!
          .uri
          .host,
      'ps.ryzypics.com',
    );
  });

  test('unescapes HTML &amp; entities in upstream poster query strings', () {
    const escaped =
        'https://gimg0.baidu.com/gimg/app=2001&amp;n=0&amp;g=0n&amp;fmt=webp&amp;src=img.jisuimage.com/cover/234c04f19f239b6d91cf473d6738deeb.jpg';
    final request = ArtworkRequest.parse(escaped)!;
    expect(
      request.uri.toString(),
      'https://gimg0.baidu.com/gimg/app=2001&n=0&g=0n&fmt=webp&src=img.jisuimage.com/cover/234c04f19f239b6d91cf473d6738deeb.jpg',
    );
  });

  test('netease music image hosts get public browser User-Agent header', () {
    final request = ArtworkRequest.parse(
      'https://p2.music.126.net/Y3I39-aBO3196L5G5mG2kA==/109951172268203468.jpg',
    )!;
    expect(request.headers, {'User-Agent': browserAgent});
    expect(
      ArtworkRequest.parse('https://p2.music.126.net:8443/a.jpg')!.headers,
      isEmpty,
    );
    expect(
      ArtworkRequest.parse('https://p2.music.126.net.evil.example/a.jpg')!
          .headers,
      isEmpty,
    );
  });

  test('baidu proxy with unverified target keeps the proxy url bare', () {
    const proxyUrl =
        'https://image.baidu.com/search/down?url=https://img3.doubanio.com.evil.example/poster.jpg';
    final request = ArtworkRequest.parse(proxyUrl)!;
    expect(request.uri.toString(), proxyUrl);
    expect(request.headers, isEmpty);
  });

  test('provider retains normal HTTPS artwork path and query', () async {
    const url = 'https://img.lzipic.com/cover.webp?width=480&quality=85';
    expect((await _filmWithPoster(url)).posterUrl, url);
  });

  for (final original in [
    'http://m.ykimg.com/058400006AD1B9FD13FA2B1479067535?width=480',
    'http://pic7.iqiyipic.com/image/20260909/47/13/a_101467435_m_601_579_772.jpg',
    'http://pic4.iqiyipic.com/image/cover.jpg?size=579_772&version=2',
    'http://pic8.iqiyipic.com/image/cover.jpg?size=579_772',
    'http://pic9.iqiyipic.com/image/cover.jpg?size=579_772',
    'http://pic4.iqiyipic.com/image/20260109/d1/1e/a_100459186_m_601_m36_1248_702.jpg',
    'http://pic1.iqiyipic.com/image/20261022/b0/8e/a_101698406_m_601_579_772.jpg',
  ]) {
    test('provider upgrades verified artwork endpoint $original', () async {
      expect(
        (await _filmWithPoster(original)).posterUrl,
        original.replaceFirst('http:', 'https:'),
      );
    });
  }

  for (final url in <String?>[
    null,
    '',
    'http://pic8.iqiyipic.com:8080/cover.jpg',
    'https://account:secret@img.lzipic.com/cover.jpg',
    'file:///storage/emulated/0/private.jpg',
    'data:image/png;base64,AA==',
    'javascript:alert(1)',
  ]) {
    test('provider rejects unsupported or credentialed artwork $url', () async {
      expect((await _filmWithPoster(url)).posterUrl, isNull);
    });
  }

  for (final sample in [
    (
      'http://new-cdn.example/cover.webp?token=a%2Fb%2Bc&quality=85',
      'https://new-cdn.example/cover.webp?token=a%2Fb%2Bc&quality=85',
    ),
    (
      '//pic9.iqiyipic.com/cover.jpg?width=579',
      'https://pic9.iqiyipic.com/cover.jpg?width=579',
    ),
    (
      'http://img1.doubanio.com.evil.example/cover.jpg',
      'https://img1.doubanio.com.evil.example/cover.jpg',
    ),
  ]) {
    test('provider automatically normalizes ${sample.$1}', () async {
      expect((await _filmWithPoster(sample.$1)).posterUrl, sample.$2);
    });
  }
  test('automatic HTTPS does not grant lookalike hosts trusted headers', () {
    final request = ArtworkRequest.parse(
      'http://img1.doubanio.com.evil.example/cover.jpg',
    )!;
    expect(request.uri.scheme, 'https');
    expect(request.headers, isEmpty);
    expect(ArtworkRequest.parse('//user:secret@cdn.example/a.jpg'), isNull);
    expect(ArtworkRequest.parse('//cdn.example:8080/a.jpg'), isNull);
  });

  for (final sample in [
    (
      original: 'https://img2.doubanio.com/view/photo/poster.jpg?width=480',
      normalized: 'https://img2.doubanio.com/view/photo/poster.jpg?width=480',
      headers: <String, String>{
        'User-Agent': browserAgent,
        'Referer': 'https://movie.douban.com/',
      },
    ),
    (
      original: 'http://m.ykimg.com/cover.image',
      normalized: 'https://m.ykimg.com/cover.image',
      headers: <String, String>{},
    ),
  ]) {
    testWidgets(
      'FilmArtwork forwards safe normalized request ${sample.original}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: duosceneTheme,
            home: Scaffold(
              body: FilmArtwork(
                Film(
                  'whisklet:42',
                  'Artwork fixture',
                  '电影',
                  '',
                  0,
                  posterUrl: sample.original,
                ),
                width: 64,
                height: 90,
                cacheWidth: 192,
              ),
            ),
          ),
        );
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.width, 64);
        expect(image.height, 90);
        expect(image.fit, BoxFit.cover);
        final resized = image.image as ResizeImage;
        expect(resized.width, 192);
        if (sample.headers.isNotEmpty) {
          final network = resized.imageProvider as ArtworkImage;
          expect(network.request.uri.toString(), sample.normalized);
          expect(network.request.headers, sample.headers);
        } else {
          final network = resized.imageProvider as NetworkImage;
          expect(network.url, sample.normalized);
          expect(network.headers, sample.headers);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('重试封面'), findsOneWidget);
        await tester.tap(find.byTooltip('重试封面'));
        await tester.pumpAndSettle();
        expect(tester.widget<Image>(find.byType(Image)).key, const ValueKey(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'automatic domain self-healing probes active CDN hosts, learns working domain, and persists rules',
    () async {
      ArtworkRequest.resetLearnedRulesForTest();
      addTearDown(ArtworkRequest.resetLearnedRulesForTest);

      String? persistedJson;
      ArtworkRequest.onRulesChanged = (rawJson) {
        persistedJson = rawJson;
      };

      // 模拟目录加载过程中观测到上游新启用的活跃图床域名。
      ArtworkRequest.observeCatalogUrl(
        'https://cdn-next.ry-pic.example/upload/vod/20261030-1/active.jpg',
      );
      expect(
        ArtworkRequest.observedVodCdnHosts,
        contains('cdn-next.ry-pic.example'),
      );

      const brokenUrl =
          'https://legacy.ry-broken.example/upload/vod/20251029-1/cover.png';
      final initial = ArtworkRequest.parse(brokenUrl)!;
      expect(initial.uri.host, 'legacy.ry-broken.example');
      // 同家族（含 ry）候选域排在普通候选域之前优先探测。
      expect(
        ArtworkRequest.candidateFallbackUris(
          initial.uri,
        ).take(2).map((u) => u.host),
        containsAll(['pic.ry-pic.com', 'cdn-next.ry-pic.example']),
      );

      final probedHosts = <String>[];
      final healed = await ArtworkRequest.healFailedRequest(
        initial.uri,
        probe: (candidate, _) async {
          probedHosts.add(candidate.host);
          return candidate.host == 'cdn-next.ry-pic.example';
        },
      );
      expect(healed, isTrue);
      expect(probedHosts, contains('cdn-next.ry-pic.example'));
      expect(
        ArtworkRequest.learnedHostMigrations['legacy.ry-broken.example'],
        'cdn-next.ry-pic.example',
      );
      expect(persistedJson, isNotNull);

      // 自愈后再次解析同一旧域名，直接自动替换为新域名。
      final rewritten = ArtworkRequest.parse(brokenUrl)!;
      expect(
        rewritten.uri.toString(),
        'https://cdn-next.ry-pic.example/upload/vod/20251029-1/cover.png',
      );

      // 模拟应用重启后从持久化 JSON 恢复自愈规则。
      ArtworkRequest.resetLearnedRulesForTest();
      ArtworkRequest.importLearnedRules(persistedJson);
      expect(
        ArtworkRequest.parse(brokenUrl)!.uri.host,
        'cdn-next.ry-pic.example',
      );
    },
  );

  testWidgets(
    'FilmArtwork automatically heals broken /upload/vod/ domain and reloads cover',
    (tester) async {
      ArtworkRequest.resetLearnedRulesForTest();
      addTearDown(ArtworkRequest.resetLearnedRulesForTest);

      ArtworkRequest.debugProbe = (candidate, _) async =>
          candidate.host == 'pic.ry-pic.com';

      const brokenPoster =
          'https://dead-ry.example/upload/vod/20251029-1/8079c5eb.png';
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: const Scaffold(
            body: FilmArtwork(
              Film(
                'whisklet:999',
                'Self heal fixture',
                '短剧',
                '',
                0,
                posterUrl: brokenPoster,
              ),
              width: 96,
              height: 144,
              cacheWidth: 192,
            ),
          ),
        ),
      );

      final before =
          (tester.widget<Image>(find.byType(Image)).image as ResizeImage)
              .imageProvider as NetworkImage;
      expect(before.url, brokenPoster);

      // 触发封面加载失败，验证 FilmArtwork 自动探测并切换到可用 CDN 域名。
      final image = tester.widget<Image>(find.byType(Image));
      image.errorBuilder!(
        tester.element(find.byType(Image)),
        NetworkImageLoadException(
          statusCode: 502,
          uri: Uri.parse(brokenPoster),
        ),
        null,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final afterImage = tester.widget<Image>(find.byType(Image));
      expect(afterImage.key, const ValueKey(1));
      final after =
          (afterImage.image as ResizeImage).imageProvider as NetworkImage;
      expect(
        after.url,
        'https://pic.ry-pic.com/upload/vod/20251029-1/8079c5eb.png',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
