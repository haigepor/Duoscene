import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'whisklet_codec.dart';

class ProviderException implements Exception {
  const ProviderException(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

enum WhiskletMethod {
  appConfig('app_config'),
  advert('advert'),
  nav('nav'),
  topNotice('top_notice'),
  recommend('index_recommend'),
  lastVersion('last_version'),
  notice('notice'),
  videoList('video_list'),
  search('search'),
  ranks('rank_list'),
  noticeDetail('notice_detail'),
  advertDetail('advert_detail'),
  detail('video_detail'),
  secretParse('secret_parse_api_url'),
  comments('comment_list'),
  danmaku('dm_list'),
  heat('vod_heat_add');

  const WhiskletMethod(this.wireName);
  final String wireName;
}

class WhiskletClient {
  WhiskletClient({
    http.Client? transport,
    this.timeout = const Duration(seconds: 12),
  }) : _transport = transport ?? http.Client();
  final http.Client _transport;
  final Duration timeout;
  final _pending = <Completer<void>>{};
  bool _closed = false;
  static final endpoint = Uri.http(
    '${WhiskletProfile.host}:${WhiskletProfile.port}',
    WhiskletProfile.entry,
  );

  Future<Uint8List> _request(
    String method,
    Uri uri, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    if (_closed) throw const ProviderException('closed', '播放源已关闭');
    final abort = Completer<void>();
    _pending.add(abort);
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final request = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      )..headers.addAll(headers);
      if (body != null) request.body = body;
      final response = await _transport.send(request).timeout(timeout);
      if (response.statusCode != 200)
        throw ProviderException('http', '播放源请求失败（HTTP ${response.statusCode}）');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > 4 * 1024 * 1024)
          throw const ProviderException('size', '播放源响应过大');
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } on ProviderException {
      rethrow;
    } on TimeoutException {
      throw const ProviderException('timeout', '播放源响应超时，请重试或换线');
    } on http.RequestAbortedException {
      throw ProviderException(
        _closed ? 'cancelled' : 'timeout',
        _closed ? '播放源请求已取消' : '播放源响应超时，请重试或换线',
      );
    } catch (_) {
      throw const ProviderException('network', '无法连接播放源，请检查网络后重试');
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      _pending.remove(abort);
    }
  }

  Future<Map<String, dynamic>> call(
    WhiskletMethod method, [
    Map<String, dynamic> data = const {'token': ''},
  ]) async {
    _validateInput(method, data);
    final payload = WhiskletCodec().encrypt({
      'method': method.wireName,
      'data': data,
      'csrf': DateTime.now().millisecondsSinceEpoch,
    });
    final bytes = await _request(
      'POST',
      endpoint,
      body: payload,
      headers: WhiskletProfile.headers,
    );
    try {
      final result = await compute(decodeWhiskletResponse, (
        utf8.decode(bytes),
        method.wireName,
      ));
      if (method == WhiskletMethod.heat &&
          result['_meta']?['mode'] == 'receipt')
        return result;
      if (result['code'] != 1)
        throw const ProviderException('business', '播放源拒绝了请求，请稍后重试');
      final value = result['data'];
      final valid = switch (method) {
        WhiskletMethod.appConfig ||
        WhiskletMethod.advert ||
        WhiskletMethod.recommend ||
        WhiskletMethod.detail => value is Map,
        WhiskletMethod.topNotice => value is Map || value is List,
        WhiskletMethod.noticeDetail ||
        WhiskletMethod.advertDetail => value is String,
        WhiskletMethod.secretParse => value is String && value.length >= 32,
        WhiskletMethod.heat => value == null,
        _ => value is List,
      };
      if (!valid) throw const FormatException('Unexpected response data');
      return result;
    } on ProviderException {
      rethrow;
    } catch (_) {
      throw const ProviderException('protocol', '播放源返回不完整或格式已变更，请重试');
    }
  }

  static void _validateInput(WhiskletMethod method, Map<String, dynamic> data) {
    final allowed = switch (method) {
      WhiskletMethod.videoList => {
        'tid',
        'pg',
        'limit',
        'class',
        'area',
        'lang',
        'year',
      },
      WhiskletMethod.search => {'text', 'pg', 'token'},
      WhiskletMethod.detail ||
      WhiskletMethod.advertDetail ||
      WhiskletMethod.noticeDetail => {'id'},
      WhiskletMethod.secretParse => {'url', 'player_code', 'token'},
      WhiskletMethod.comments => {'vid', 'token'},
      WhiskletMethod.danmaku => {'group_key', 'token'},
      WhiskletMethod.heat => {'id', 'token'},
      WhiskletMethod.ranks => <String>{},
      _ => {'token'},
    };
    bool valid =
        allowed.containsAll(data.keys) &&
        (!data.containsKey('token') || data['token'] == '');
    for (final key in ['id', 'vid', 'tid', 'pg', 'limit']) {
      if (data.containsKey(key))
        valid =
            valid &&
            data[key] is int &&
            (data[key] as int) > 0 &&
            (data[key] as int) <= 10000000;
    }
    final required = switch (method) {
      WhiskletMethod.videoList => {'tid', 'pg', 'limit'},
      WhiskletMethod.search => {'text', 'pg'},
      WhiskletMethod.detail ||
      WhiskletMethod.advertDetail ||
      WhiskletMethod.heat => {'id'},
      WhiskletMethod.comments => {'vid'},
      WhiskletMethod.danmaku => {'group_key'},
      WhiskletMethod.secretParse => {'url', 'player_code'},
      _ => <String>{},
    };
    valid = valid && data.keys.toSet().containsAll(required);
    for (final key in [
      'text',
      'url',
      'player_code',
      'group_key',
      'class',
      'area',
      'lang',
      'year',
    ]) {
      if (data.containsKey(key))
        valid =
            valid &&
            data[key] is String &&
            (data[key] as String).trim().isNotEmpty &&
            (data[key] as String).length <= (key == 'url' ? 8192 : 200);
    }
    if (data.containsKey('group_key'))
      valid =
          valid &&
          RegExp(r'^[a-f0-9]{20}$').hasMatch(data['group_key'].toString());
    if (!valid) throw const ProviderException('input', '播放源请求参数无效');
  }

  Future<Map<String, dynamic>> appConfig() => call(WhiskletMethod.appConfig);
  Future<Map<String, dynamic>> advert() => call(WhiskletMethod.advert);
  Future<Map<String, dynamic>> nav() => call(WhiskletMethod.nav);
  Future<Map<String, dynamic>> topNotice() => call(WhiskletMethod.topNotice);
  Future<Map<String, dynamic>> recommend() => call(WhiskletMethod.recommend);
  Future<Map<String, dynamic>> lastVersion() =>
      call(WhiskletMethod.lastVersion);
  Future<Map<String, dynamic>> notices() => call(WhiskletMethod.notice);
  Future<Map<String, dynamic>> videoList(
    int category,
    int page, {
    Map<String, String> filters = const {},
  }) => call(WhiskletMethod.videoList, {
    'tid': category,
    'pg': page,
    'limit': 20,
    ...filters,
  });
  Future<Map<String, dynamic>> search(String query, int page) =>
      call(WhiskletMethod.search, {'text': query, 'pg': page, 'token': ''});
  Future<Map<String, dynamic>> ranks() => call(WhiskletMethod.ranks, {});
  Future<Map<String, dynamic>> noticeDetail([int? id]) =>
      call(WhiskletMethod.noticeDetail, id == null ? {} : {'id': id});
  Future<Map<String, dynamic>> advertDetail(int id) =>
      call(WhiskletMethod.advertDetail, {'id': id});
  Future<Map<String, dynamic>> detail(int id) =>
      call(WhiskletMethod.detail, {'id': id});
  Future<Map<String, dynamic>> secretParse(String token, String code) => call(
    WhiskletMethod.secretParse,
    {'url': token, 'player_code': code, 'token': ''},
  );
  Future<Map<String, dynamic>> comments(int id) =>
      call(WhiskletMethod.comments, {'vid': id, 'token': ''});
  Future<Map<String, dynamic>> danmaku(String groupKey) =>
      call(WhiskletMethod.danmaku, {'group_key': groupKey, 'token': ''});
  Future<Map<String, dynamic>> heat(int id) =>
      call(WhiskletMethod.heat, {'id': id, 'token': ''});

  Future<Map<String, dynamic>> parse(Uri uri) async {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        uri.toString().length > 8192)
      throw const ProviderException('parser', '解析地址无效');
    final Uint8List raw;
    try {
      raw = await _request(
        'GET',
        uri,
        headers: {'user-agent': WhiskletProfile.headers['user-agent']!},
      );
    } on ProviderException catch (error) {
      if (error.code == 'closed' || error.code == 'cancelled') rethrow;
      // 单条线路的解析器超时或 5xx 归为 parser 失败，允许上层自动回退到其余线路。
      throw const ProviderException('parser', '该线路解析失败，请切换其他线路');
    }
    try {
      final result = jsonDecode(utf8.decode(raw));
      if (result is! Map<String, dynamic> ||
          result['code'] != 200 ||
          result['url'] is! String ||
          (result['url'] as String).trim().isEmpty)
        throw const FormatException();
      return result;
    } catch (_) {
      throw const ProviderException('parser', '该线路解析失败，请切换其他线路');
    }
  }

  void close() {
    _closed = true;
    for (final abort in _pending) {
      if (!abort.isCompleted) abort.complete();
    }
    _transport.close();
  }
}
