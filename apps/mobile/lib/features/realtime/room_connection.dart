import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../auth/session.dart';

String messageId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';

class RoomConnection extends ChangeNotifier {
  RoomConnection(this.auth, this.roomId);
  final Session auth;
  final String roomId;
  final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final messages = <Map<String, dynamic>>[];
  final pending = <String, Map<String, dynamic>>{};
  final _deliveryTimers = <String, Timer>{};
  WebSocket? _socket;
  Timer? _retry;
  bool _disposed = false,
      connected = false,
      connecting = false,
      terminal = false;
  int _attempt = 0, _generation = 0;
  String? notice, connectionId;
  Map<String, dynamic>? snapshot;
  List<dynamic> iceServers = [];
  bool relayOnly = false;
  final _commands = <String, Completer<void>>{};
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect() async {
    if (_disposed || connecting || terminal) return;
    connecting = true;
    changed();
    final generation = ++_generation;
    try {
      final ticket = await auth.request(
        'POST',
        '/rooms/$roomId/realtime-ticket',
      );
      if (_disposed || generation != _generation) return;
      final uri = auth.api.baseUrl.replace(
        scheme: auth.api.baseUrl.scheme == 'https' ? 'wss' : 'ws',
        path: '/realtime',
        queryParameters: {'ticket': ticket['ticket'] as String},
      );
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 10));
      if (_disposed || generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      connected = true;
      connecting = false;
      notice = null;
      _attempt = 0;
      socket.pingInterval = const Duration(seconds: 12);
      socket.listen(
        (data) {
          if (_disposed || generation != _generation) return;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _receive(json);
          } catch (_) {
            notice = '收到无法识别的房间消息';
            changed();
          }
        },
        onError: (Object _) => _lost(generation),
        onDone: () {
          if (socket.closeCode == 4001) terminal = true;
          _lost(generation);
        },
      );
      changed();
    } on ApiException catch (error) {
      terminal = [401, 403, 404, 409].contains(error.status);
      notice = error.message;
      _lost(generation);
    } catch (_) {
      notice = '连接中断，正在重连…';
      _lost(generation);
    }
  }

  void _lost(int generation) {
    if (_disposed ||
        generation != _generation ||
        (!connecting && !connected && _retry?.isActive == true))
      return;
    connected = false;
    connecting = false;
    _socket = null;
    notice ??= terminal ? '连接已结束，请返回房间重新进入' : '连接中断，正在重连…';
    for (final c in _commands.values) {
      if (!c.isCompleted) c.completeError(StateError('连接已中断，请确认状态后重试'));
    }
    _commands.clear();
    for (final value in pending.values) {
      value['delivery'] = 'failed';
    }
    events.add({'type': 'disconnected'});
    changed();
    if (!terminal)
      _retry = Timer(
        Duration(seconds: min(8, 1 << min(_attempt++, 3))),
        connect,
      );
  }

  void _receive(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'snapshot':
        final previous = snapshot;
        if (previous != null &&
            event['epoch'] == previous['epoch'] &&
            (event['revision'] as num) < (previous['revision'] as num))
          return;
        snapshot = event;
      case 'welcome':
        connectionId = event['connectionId'] as String;
        iceServers = event['iceServers'] as List;
        relayOnly = event['relayOnly'] == true;
      case 'chat':
        _merge((event['message'] as Map).cast<String, dynamic>());
      case 'history':
        for (final m in event['messages'] as List) {
          _merge((m as Map).cast<String, dynamic>());
        }
        messages.sort(
          (a, b) =>
              BigInt.parse(a['id'].toString())
                  .compareTo(BigInt.parse(b['id'].toString())),
        );
      case 'ack':
        _commands.remove(event['commandId'])?.complete();
      case 'error':
        final id = event['commandId'];
        notice = switch (event['code']) {
          'REVISION_CONFLICT' || 'EPOCH_CHANGED' => '房间状态已更新，请再次操作',
          'NO_MEDIA' => '先选择双方可访问的视频地址',
          _ => '操作未完成，请检查连接后重试',
        };
        _commands.remove(id)?.completeError(StateError(notice!));
    }
    events.add(event);
    changed();
  }

  void _merge(Map<String, dynamic> message) {
    if (message['userId'] == auth.user?.id) {
      pending.remove(message['clientMessageId']);
      _deliveryTimers.remove(message['clientMessageId'])?.cancel();
    }
    if (!messages.any((m) => m['id'] == message['id'])) messages.add(message);
    if (messages.length > 300) messages.removeRange(0, messages.length - 300);
  }

  void send(Map<String, dynamic> message) {
    if (!connected || _socket == null || _socket!.readyState != WebSocket.open)
      throw StateError('房间尚未连接');
    _socket!.add(jsonEncode(message));
  }

  Future<void> command(
    String type, [
    Map<String, dynamic> values = const {},
  ]) async {
    final current = snapshot;
    if (current == null) throw StateError('等待房间状态');
    final id = messageId(), complete = Completer<void>();
    _commands[id] = complete;
    try {
      send({
        'type': type,
        'commandId': id,
        'epoch': current['epoch'],
        'expectedRevision': current['revision'],
        ...values,
      });
      await complete.future.timeout(const Duration(seconds: 8));
    } finally {
      _commands.remove(id);
    }
  }

  void chat(String text, {String? retryId}) {
    final id = retryId ?? messageId();
    _deliveryTimers.remove(id)?.cancel();
    final value = {'clientMessageId': id, 'text': text, 'delivery': 'sending'};
    pending[id] = value;
    try {
      send({'type': 'chat', 'clientMessageId': id, 'text': text});
    } catch (_) {
      value['delivery'] = 'failed';
    }
    _deliveryTimers[id] = Timer(const Duration(seconds: 8), () {
      _deliveryTimers.remove(id);
      if (_disposed) return;
      if (pending[id]?['delivery'] == 'sending') {
        pending[id]!['delivery'] = 'failed';
        changed();
      }
    });
    changed();
  }

  void older() {
    if (messages.isNotEmpty)
      send({'type': 'history', 'before': messages.first['id']});
  }

  Future<void> reconnect() async {
    ++_generation;
    _retry?.cancel();
    await _socket?.close();
    _socket = null;
    connected = false;
    connecting = false;
    terminal = false;
    events.add({'type': 'disconnected'});
    await connect();
  }

  @override
  void dispose() {
    _disposed = true;
    connected = false;
    connecting = false;
    ++_generation;
    _retry?.cancel();
    final socket = _socket;
    for (final timer in _deliveryTimers.values) {
      timer.cancel();
    }
    _deliveryTimers.clear();
    _socket = null;
    unawaited(socket?.close());
    for (final c in _commands.values) {
      if (!c.isCompleted) c.completeError(StateError('房间已退出'));
    }
    _commands.clear();
    unawaited(events.close());
    super.dispose();
  }
}
