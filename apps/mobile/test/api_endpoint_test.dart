import 'package:duoscene/core/api_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LAN HTTP is explicit debug-only and limited to private IPv4', () {
    for (final host in [
      '192.168.0.4',
      '10.1.2.3',
      '172.16.0.2',
      '172.31.255.254',
    ]) {
      final value = 'http://$host:3000';
      expect(apiEndpoint(value, debug: true, allowLanHttp: true)?.host, host);
      expect(apiEndpoint(value, debug: true), isNull);
      expect(apiEndpoint(value, debug: false, allowLanHttp: true), isNull);
    }
    for (final host in [
      '8.8.8.8',
      '172.32.0.1',
      '172.15.0.1',
      '169.254.1.1',
      '0.0.0.0',
      '192.168.0.4.evil.example',
      'example.com',
    ]) {
      expect(
        apiEndpoint('http://$host:3000', debug: true, allowLanHttp: true),
        isNull,
      );
    }
  });
  test('existing HTTPS and loopback policy remain unchanged', () {
    expect(
      apiEndpoint('https://api.example.com', debug: false)?.scheme,
      'https',
    );
    expect(
      apiEndpoint('http://127.0.0.1:3000', debug: true)?.host,
      '127.0.0.1',
    );
    expect(apiEndpoint('http://127.0.0.1:3000', debug: false), isNull);
    for (final value in [
      'https://name:secret@api.example.com',
      'https://api.example.com/path',
      'https://api.example.com?token=x',
      'https://api.example.com#x',
      'file:///private',
    ]) {
      expect(apiEndpoint(value, debug: true, allowLanHttp: true), isNull);
    }
  });
}
