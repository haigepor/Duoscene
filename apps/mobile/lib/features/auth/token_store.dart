import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// 仅保存 refresh token；不同环境隔离，防止把本地凭据发送给生产服务。
/// Source: https://pub.dev/packages/flutter_secure_storage
class SecureTokenStore implements TokenStore {
  SecureTokenStore(Uri origin)
    : _key = 'duoscene.refresh.${base64Url.encode(utf8.encode(origin.origin))}';
  final String _key;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
