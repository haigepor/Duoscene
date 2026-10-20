import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';
import '../../core/models.dart';
import 'token_store.dart';

class Session extends ChangeNotifier {
  Session(this.api, this.store);
  final ApiClient api;
  final TokenStore store;
  Credentials? _credentials;
  Future<void>? _refreshing;
  Future<void> _storageQueue = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  bool initialized = false;
  bool busy = false;
  String? notice;
  User? get user => _credentials?.user;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _storage<T>(Future<T> Function() operation) {
    final next = _storageQueue.then((_) => operation());
    _storageQueue = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<void> restore() async {
    if (initialized || busy) return;
    busy = true;
    try {
      final token = await _storage(store.read);
      if (token != null) await _rotate(token, _generation);
    } catch (_) {
      _credentials = null;
      notice = '无法恢复登录，请重新输入账户和密码。';
      try {
        await _storage(store.clear);
      } catch (_) {
        notice = '安全存储暂不可用，请解锁设备后重试。';
      }
    } finally {
      busy = false;
      initialized = true;
      _changed();
    }
  }

  Future<void> login(String username, String password) async {
    if (busy) return;
    busy = true;
    notice = null;
    _changed();
    final generation = ++_generation;
    try {
      await _storage(store.clear);
      final json = await api.request(
        'POST',
        '/auth/login',
        body: {
          'username': username.trim(),
          'password': password,
          'deviceLabel': 'Duoscene ${defaultTargetPlatform.name}',
        },
      );
      await _accept(Credentials.fromJson(json), generation);
    } finally {
      busy = false;
      initialized = true;
      _changed();
    }
  }

  Future<void> _accept(Credentials credentials, int generation) async {
    if (generation != _generation || _disposed) {
      await _revoke(credentials.accessToken);
      return;
    }
    try {
      await _storage(() => store.write(credentials.refreshToken));
    } catch (_) {
      await _revoke(credentials.accessToken);
      throw const ApiException('SECURE_STORAGE', '无法安全保存登录信息，请解锁设备后重试。');
    }
    // 退出可能发生在安全存储写入期间，不允许迟到的登录恢复旧会话。
    if (generation != _generation || _disposed) {
      await _storage(store.clear);
      await _revoke(credentials.accessToken);
      return;
    }
    _credentials = credentials;
  }

  Future<void> _rotate(String token, int generation) async {
    // 后端刷新重放会撤销整个会话：发送前删除旧值，响应丢失后只能重新登录。
    await _storage(store.clear);
    final json = await api.request(
      'POST',
      '/auth/refresh',
      body: {'refreshToken': token},
    );
    await _accept(Credentials.fromJson(json), generation);
  }

  Future<void> _refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final credentials = _credentials;
    if (credentials == null)
      return Future<void>.error(
        const ApiException('UNAUTHORIZED', '请先登录。', status: 401),
      );
    final generation = _generation;
    final task = () async {
      try {
        await _rotate(credentials.refreshToken, generation);
      } catch (_) {
        if (generation == _generation) {
          _credentials = null;
          ++_generation;
          notice = '登录已失效或刷新结果未确认，请重新登录。';
          try {
            await _storage(store.clear);
          } catch (_) {
            /* 保持退出状态，绝不重放旧 token。 */
          }
          _changed();
        }
        throw const ApiException('UNAUTHORIZED', '登录已失效，请重新登录。', status: 401);
      }
    }();
    _refreshing = task;
    // 完成后清理同一任务；返回的 Future 包含错误处理，避免悬空异常。
    return task.whenComplete(() {
      if (identical(_refreshing, task)) _refreshing = null;
    });
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final original = _credentials;
    final generation = _generation;
    if (original == null)
      throw const ApiException('UNAUTHORIZED', '请先登录。', status: 401);
    try {
      return await api.request(
        method,
        path,
        body: body,
        query: query,
        accessToken: original.accessToken,
      );
    } on ApiException catch (error) {
      if (error.status != 401) rethrow;
      if (generation != _generation) rethrow;
      // 迟到的旧 access 401 不能触发第二次 refresh，使用已经轮换后的凭据。
      if (_credentials?.accessToken == original.accessToken) await _refresh();
      if (generation != _generation || _credentials == null) rethrow;
      try {
        return await api.request(
          method,
          path,
          body: body,
          query: query,
          accessToken: _credentials!.accessToken,
        );
      } on ApiException catch (retryError) {
        if (retryError.status == 401 && generation == _generation) {
          _credentials = null;
          ++_generation;
          notice = '会话已被撤销，请重新登录。';
          await _storage(store.clear);
          _changed();
        }
        rethrow;
      }
    }
  }

  Future<void> _revoke(String accessToken, {String? refreshToken}) async {
    try {
      await api.request('POST', '/auth/logout', accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.status == 401 && refreshToken != null) {
        // access 已过期时仍撤销 refresh 会话；此分支不保存新凭据，也不重试不确定的刷新。
        try {
          final rotated = Credentials.fromJson(
            await api.request(
              'POST',
              '/auth/refresh',
              body: {'refreshToken': refreshToken},
            ),
          );
          await api.request(
            'POST',
            '/auth/logout',
            accessToken: rotated.accessToken,
          );
        } catch (_) {
          /* 本地已清理，网络恢复后需重新登录。 */
        }
      }
    } catch (_) {
      /* 本地退出优先；服务端凭据按既有有效期失效。 */
    }
  }

  Future<void> logout() async {
    if (busy) return;
    busy = true;
    final credentials = _credentials;
    final refreshing = _refreshing;
    _credentials = null;
    ++_generation;
    notice = null;
    _changed();
    _refreshing = null;
    try {
      await _storage(store.clear);
    } catch (_) {
      notice = '设备安全存储清理失败，请解锁设备并重试退出。';
    }
    if (credentials != null) {
      await _revoke(
        credentials.accessToken,
        refreshToken: refreshing == null ? credentials.refreshToken : null,
      );
    }
    // 已发送的刷新交给代际检查撤销新凭据，绝不重放它使用过的旧 refresh token。
    if (refreshing != null) {
      try {
        await refreshing;
      } catch (_) {
        /* 退出状态保持不变。 */
      }
    }
    busy = false;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    api.close();
    super.dispose();
  }
}
