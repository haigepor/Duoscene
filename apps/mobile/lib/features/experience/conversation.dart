import 'package:flutter/foundation.dart';

enum Delivery { pending, sent, failed }

class ChatMessage {
  ChatMessage(
    this.id,
    this.text, {
    this.mine = true,
    this.delivery = Delivery.pending,
  });
  final int id;
  final String text;
  final bool mine;
  Delivery delivery;
}

abstract interface class ChatAdapter {
  Future<void> send(int id, String text);
}

class PreviewChatAdapter implements ChatAdapter {
  bool fail = false;
  @override
  Future<void> send(int id, String text) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (fail) throw StateError('预览发送失败');
  }
}

class Conversation extends ChangeNotifier {
  Conversation(this.adapter, {bool seed = false}) {
    if (seed)
      messages.addAll([
        ChatMessage(1, '这一集反转好突然！', mine: false, delivery: Delivery.sent),
        ChatMessage(2, '先别剧透，一起看完～', delivery: Delivery.sent),
        ChatMessage(3, '好，我等你。', mine: false, delivery: Delivery.sent),
      ]);
  }
  final ChatAdapter adapter;
  final List<ChatMessage> messages = [];
  int _id = 10;
  bool _disposed = false;
  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    final message = ChatMessage(++_id, text.trim());
    messages.add(message);
    await retry(message);
  }

  Future<void> retry(ChatMessage message) async {
    if (_disposed) return;
    message.delivery = Delivery.pending;
    notifyListeners();
    try {
      await adapter.send(message.id, message.text);
      message.delivery = Delivery.sent;
    } catch (_) {
      message.delivery = Delivery.failed;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 预览只表达同步意图；网络恢复、好友就绪不会覆盖用户的暂停意图。
class WatchIntent extends ChangeNotifier {
  bool manuallyPaused = false, peerReady = true;
  bool get mayPlay => !manuallyPaused && peerReady;
  void pause() {
    manuallyPaused = true;
    notifyListeners();
  }

  void play() {
    manuallyPaused = false;
    notifyListeners();
  }

  void peer(bool ready) {
    peerReady = ready;
    notifyListeners();
  }
}
