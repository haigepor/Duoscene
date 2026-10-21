import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:duoscene/features/catalog/providers/whisklet_codec.dart';

void main() {
  const captures = String.fromEnvironment('WHISKLET_CAPTURE_DIR');
  if (captures.isNotEmpty) {
    for (final method in [
      'app_config',
      'video_detail',
      'secret_parse_api_url',
    ]) {
      test('live captured $method agrees with Python SDK', () {
        final raw = File('$captures/$method.wire.txt').readAsStringSync();
        final expected = jsonDecode(
          File('$captures/$method.json').readAsStringSync(),
        );
        expect(WhiskletCodec().decode(raw, method)['data'], expected['data']);
      });
    }
  }
  final vectors = jsonDecode(
    File('test/fixtures/whisklet-vectors.json').readAsStringSync(),
  ) as List;
  for (final vector in vectors) {
    test(
      'independent SDK ${vector['method']} envelope skip=${vector['skip']} lost=${vector['lost']}',
      () {
        final result = WhiskletCodec().decode(
          vector['wire'] as String,
          vector['method'] as String,
        );
        expect(result['data'], vector['expected']);
        expect(result['code'], anyOf(1, isNull));
        expect(result['_meta']['reconstructed_header'], isTrue);
        expect(result['_meta']['verified'], isFalse);
      },
    );
  }
  test('garbage and tampered envelope fail closed', () {
    expect(
      () => WhiskletCodec().decode('not-an-envelope', 'video_detail'),
      throwsFormatException,
    );
    final wire = vectors.first['wire'] as String;
    expect(
      () => WhiskletCodec().decode(
        wire.substring(0, wire.length ~/ 2),
        'app_config',
      ),
      throwsFormatException,
    );
    expect(() => WhiskletCodec().decode(wire, 'nav'), throwsFormatException);
  });
}
