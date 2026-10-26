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
    'http://unverified.example/cover.jpg',
    'http://m.ykimg.com.evil.example/cover.jpg',
    'http://sub.pic7.iqiyipic.com/cover.jpg',
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
    const url = 'http://snzypic.com/upload/vod/20240103-1/37aa4b49.jpg';
    final request = ArtworkRequest.parse(url)!;
    expect(request.uri.scheme, 'http');
    expect(request.uri.host, 'snzypic.com');
    expect(request.headers, isEmpty);
    for (final url in [
      'http://snzypic.com:8080/upload/vod/x.jpg',
      'http://snzypic.com.evil.example/upload/vod/x.jpg',
      'http://sub.snzypic.com/upload/vod/x.jpg',
    ]) {
      expect(ArtworkRequest.parse(url), isNull, reason: url);
    }
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
    'http://unverified.example/cover.jpg',
    'http://m.ykimg.com.evil.example/cover.jpg',
    'http://sub.m.ykimg.com/cover.jpg',
    'http://sub.pic7.iqiyipic.com/cover.jpg',
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
}
