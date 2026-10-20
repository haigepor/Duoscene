import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(
    this.code,
    this.message, {
    this.status = 0,
    this.requestId,
  });
  final String code;
  final String message;
  final int status;
  final String? requestId;
  @override
  String toString() => message;
}

/// http.Client 可注入；不自动重试写操作，也不跟随携带凭据的重定向。
/// Source: https://docs.flutter.dev/cookbook/testing/unit/mocking
class ApiClient {
  ApiClient(
    this.baseUrl, {
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client() {
    if (!baseUrl.hasAuthority ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        (baseUrl.path.isNotEmpty && baseUrl.path != '/') ||
        !['http', 'https'].contains(baseUrl.scheme)) {
      throw ArgumentError('API_BASE_URL must be an http(s) origin');
    }
  }
  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
    Map<String, String>? query,
  }) async {
    final request =
        http.Request(
            method,
            baseUrl.resolve('/api/v1$path').replace(queryParameters: query),
          )
          ..followRedirects = false
          ..headers['accept'] = 'application/json';
    if (accessToken != null)
      request.headers['authorization'] = 'Bearer $accessToken';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final requestId = decoded['requestId'] as String?;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final code = error is Map<String, dynamic>
            ? error['code'] as String?
            : null;
        throw ApiException(
          code ?? 'SERVER_ERROR',
          errorMessage(code, response.statusCode),
          status: response.statusCode,
          requestId: requestId,
        );
      }
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('NETWORK_ERROR', '连接超时。若刚提交过操作，请先刷新房间确认结果。');
    } on http.ClientException {
      throw const ApiException(
        'NETWORK_ERROR',
        '无法连接服务，请检查网络和服务地址。若刚提交过操作，请先刷新确认结果。',
      );
    } on FormatException {
      throw const ApiException('INVALID_RESPONSE', '服务返回了无法识别的数据，请稍后重试。');
    } on TypeError {
      throw const ApiException('INVALID_RESPONSE', '服务返回的数据格式不匹配。');
    }
  }

  void close() => _client.close();
}

String errorMessage(String? code, int status) => switch (code) {
  'USERNAME_UNAVAILABLE' => '该账户名已被使用，请换一个。',
  'RECOVERY_INVALID' => '账户或恢复码不正确，或恢复码已失效。',
  'UNAUTHORIZED' || 'TOKEN_REPLAY' => '登录信息无效或已过期，请重新登录。',
  'ROOM_FULL' => '房间已有两位成员，无法加入。',
  'ROOM_CLOSED' => '这个房间已关闭。',
  'INVITE_UNAVAILABLE' || 'INVITE_NOT_FOUND' => '邀请码已失效、已使用或不存在，请向房主索取新邀请。',
  'ROOM_NOT_FOUND' => '房间不存在，或你已不在该房间中。',
  'OWNER_REQUIRED' => '只有房主可以执行此操作。',
  'OWNER_MUST_CLOSE' => '房主需要关闭房间，不能直接退出。',
  'RESOURCE_CONFLICT' => '房间状态已变化，请刷新后重试。',
  'VALIDATION_ERROR' => '输入不符合要求，请检查后重试。',
  'RATE_LIMITED' || 'AUTH_BUSY' => '操作过于频繁，请稍后再试。',
  _ => status == 503 ? '服务暂时不可用，请稍后重试。' : '操作失败，请稍后重试。',
};
