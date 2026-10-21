import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:duoscene/features/catalog/providers/whisklet_client.dart';
import 'package:duoscene/features/catalog/providers/whisklet_codec.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/player_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('first provider native catalog and rendered media', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final provider = WhiskletProvider(
      client: WhiskletClient(transport: _CaptureClient()),
    );
    addTearDown(provider.close);
    final categories = await provider.categories();
    expect(categories.length, greaterThanOrEqualTo(4));
    final config = await provider.client.appConfig();
    expect((config['data'] as Map).length, 14);
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(((await provider.client.appConfig())['data'] as Map).length, 14);
    }
    final recommended = await provider.recommendations();
    expect(recommended, isNotEmpty);
    final listing = await provider.browse(2);
    expect(listing.items, isNotEmpty);
    expect(listing.hasMore, isTrue);
    final detail = await provider.detail(listing.items.first.id);
    final direct = detail.lines.where((line) => line.direct).first;
    final source = await provider.resolve(
      detail.film.id,
      episode: 1,
      lineCode: direct.code,
    );
    expect(source.identity.startsWith('whisklet:'), isTrue);
    expect(source.headers.containsKey('authorization'), isFalse);
    final session = PlaybackSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: PlayerPage(
          roomName: detail.film.title,
          initialSource: source,
          session: session,
        ),
      ),
    );
    Future<void> until(bool Function() ready, String reason) async {
      for (var attempt = 0; attempt < 300; attempt++) {
        if (ready()) return;
        await tester.pump(const Duration(milliseconds: 200));
      }
      fail('$reason: ${session.error}');
    }

    await until(
      () => !session.loading && session.core.playerDuration > Duration.zero,
      'provider media did not load',
    );
    expect(session.error, isNull);
    await session.play();
    await until(
      () => session.core.playerPosition > const Duration(seconds: 1),
      'media position did not advance',
    );
    await session.core.videoController!.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 25),
    );
    await until(
      () => session.debug.playerWidth > 0,
      'native dimensions unavailable',
    );
    final frame = await session.core.screenshotPng();
    expect(frame, isNotNull);
    expect(frame!.length, greaterThan(1000));
    final output = await getExternalStorageDirectory();
    await File('${output!.path}/provider-native-frame.png').writeAsBytes(frame);
    final proof = {
      'provider': provider.id,
      'film': detail.film.id,
      'line': direct.code,
      'categories': categories.length,
      'recommendations': recommended.length,
      'positionMs': session.core.playerPosition.inMilliseconds,
      'durationMs': session.core.playerDuration.inMilliseconds,
      'width': session.debug.playerWidth,
      'height': session.debug.playerHeight,
      'frameBytes': frame.length,
    };
    await File('${output.path}/provider-native-proof.json')
        .writeAsString(jsonEncode(proof), encoding: utf8);
    binding.reportData = proof;
    const captureBase = String.fromEnvironment('PROVIDER_CAPTURE_BASE');
    if (captureBase.isNotEmpty) {
      await http.post(
        Uri.parse('$captureBase/capture/provider-native-frame.png'),
        body: frame,
      );
      await http.post(
        Uri.parse('$captureBase/capture/provider-native-proof.json'),
        body: jsonEncode(proof),
      );
    }
    await session.pause();
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 4)));
}

class _CaptureClient extends http.BaseClient {
  final inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await http.Response.fromStream(await inner.send(request));
    if (request is http.Request && request.method == 'POST') {
      final method =
          WhiskletCodec().decryptRequest(request.body)['method'] as String;
      final temporary = await getTemporaryDirectory();
      await File('${temporary.path}/provider-$method.wire.txt')
          .writeAsBytes(response.bodyBytes);
      const captureBase = String.fromEnvironment('PROVIDER_CAPTURE_BASE');
      if (captureBase.isNotEmpty) {
        await http.post(
          Uri.parse('$captureBase/capture/$method.wire.txt'),
          body: response.bodyBytes,
        );
      }
      final decoded = WhiskletCodec().decode(
        utf8.decode(response.bodyBytes),
        method,
      );
      debugPrint(
        'PROVIDER_CAPTURE method=$method code=${decoded['code']} keys=${decoded.keys.join(',')} meta=${decoded['_meta']}',
      );
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close() => inner.close();
}
