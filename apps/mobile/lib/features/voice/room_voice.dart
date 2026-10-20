import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../realtime/room_connection.dart';

/// 仅音频 WebRTC；信令走房间鉴权连接，音频不经过 WS 或 MySQL。
/// Source: https://flutter-webrtc.org/docs/flutter-webrtc/api-docs/rtc-peerconnection/
class RoomVoice extends ChangeNotifier {
  RoomVoice(this.room) {
    subscription = room.events.stream.listen((event) {
      if (event['type'] == 'snapshot' || event['type'] == 'signal') {
        queue = queue
            .catchError((Object _) {})
            .then((_) => handle(event))
            .catchError((Object _) {
              if (!disposed) {
                error = '语音连接未完成，可关闭后重试';
                changed();
              }
            });
      }
      if (event['type'] == 'disconnected') unawaited(leave(send: false));
    });
  }
  final RoomConnection room;
  late final StreamSubscription<Map<String, dynamic>> subscription;
  RTCPeerConnection? pc;
  MediaStream? stream;
  MediaStreamTrack? remoteTrack;
  bool enabled = false,
      muted = false,
      busy = false,
      disposed = false,
      speaker = true;
  double volume = .6;
  String state = '未开启语音';
  String? error, peerId, callId;
  int lifecycle = 0;
  Future<void> queue = Future.value();
  final ice = <String, List<RTCIceCandidate>>{};
  int bytesSent = 0, bytesReceived = 0;
  void changed() {
    if (!disposed) notifyListeners();
  }

  void signal(String kind, Map<String, dynamic> data) {
    if (room.connected && enabled && peerId != null && callId != null)
      room.send({
        'type': 'signal',
        'kind': kind,
        'data': data,
        'target': peerId,
        'callId': callId,
      });
  }

  Future<void> join() async {
    if (busy || enabled || !room.connected || room.connectionId == null) return;
    busy = true;
    error = null;
    final current = ++lifecycle;
    changed();
    try {
      final audio = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      if (disposed || current != lifecycle || !room.connected) {
        for (final t in audio.getTracks()) {
          await t.stop();
        }
        await audio.dispose();
        return;
      }
      stream = audio;
      enabled = true;
      muted = false;
      state = '等待对方开启语音';
      room.send({'type': 'voice', 'enabled': true});
    } catch (_) {
      error = '未能开启麦克风，请允许录音权限后重试';
      state = '麦克风不可用';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<RTCPeerConnection> create(String target, String id) async {
    await closePeer();
    peerId = target;
    callId = id;
    final current = lifecycle;
    final value = await createPeerConnection({
      'iceServers': room.iceServers,
      'sdpSemantics': 'unified-plan',
      if (room.relayOnly) 'iceTransportPolicy': 'relay',
    });
    if (!enabled || disposed || current != lifecycle) {
      await value.close();
      throw StateError('Voice closed');
    }
    pc = value;
    value.onIceCandidate = (candidate) {
      if (identical(pc, value) && candidate.candidate?.isNotEmpty == true)
        signal('ice', Map<String, dynamic>.from(candidate.toMap() as Map));
    };
    value.onConnectionState = (status) {
      if (!identical(pc, value)) return;
      state = switch (status) {
        RTCPeerConnectionState.RTCPeerConnectionStateConnected => '语音已连接',
        RTCPeerConnectionState.RTCPeerConnectionStateFailed => '语音连接失败，请重试',
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => '语音连接中断',
        _ => '语音连接中…',
      };
      changed();
    };
    value.onTrack = (event) {
      if (event.track.kind == 'audio') {
        remoteTrack = event.track;
        unawaited(Helper.setVolume(volume, event.track));
      }
    };
    for (final t in stream!.getAudioTracks()) {
      t.enabled = !muted;
      await value.addTrack(t, stream!);
    }
    await Helper.setSpeakerphoneOn(speaker);
    return value;
  }

  Future<void> handle(Map<String, dynamic> event) async {
    if (disposed || !enabled) return;
    if (event['type'] == 'snapshot') {
      final peers = (event['peers'] as List)
          .where((p) => p['userId'] != room.auth.user?.id && p['voice'] == true)
          .toList();
      if (peers.isEmpty) {
        await closePeer();
        state = '等待对方开启语音';
        changed();
        return;
      }
      final target = peers.first['connectionId'] as String;
      final owner = (event['room'] as Map)['ownerUserId'] == room.auth.user?.id;
      if (owner && peerId != target) {
        final value = await create(target, messageId());
        final offer = await value.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });
        await value.setLocalDescription(offer);
        signal('offer', Map<String, dynamic>.from(offer.toMap() as Map));
      }
    } else {
      final kind = event['kind'],
          from = event['from'] as String,
          id = event['callId'] as String;
      final data = (event['data'] as Map).cast<String, dynamic>();
      final valid = (room.snapshot?['peers'] as List? ?? []).any(
        (p) => p['connectionId'] == from && p['voice'] == true,
      );
      if (!valid) return;
      if (kind == 'offer') {
        final value = await create(from, id);
        await value.setRemoteDescription(
          RTCSessionDescription(data['sdp'] as String?, 'offer'),
        );
        await drainIce(id);
        final answer = await value.createAnswer();
        await value.setLocalDescription(answer);
        signal('answer', Map<String, dynamic>.from(answer.toMap() as Map));
      } else if (kind == 'answer' &&
          peerId == from &&
          callId == id &&
          pc != null) {
        await pc!.setRemoteDescription(
          RTCSessionDescription(data['sdp'] as String?, 'answer'),
        );
        await drainIce(id);
      } else if (kind == 'ice') {
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (peerId == from &&
            callId == id &&
            pc != null &&
            await pc!.getRemoteDescription() != null) {
          await pc!.addCandidate(candidate);
        } else {
          if (ice.length > 4) ice.remove(ice.keys.first);
          final list = ice.putIfAbsent(id, () => []);
          if (list.length < 64) list.add(candidate);
        }
      }
    }
  }

  Future<void> drainIce(String id) async {
    for (final c in ice.remove(id) ?? <RTCIceCandidate>[]) {
      await pc?.addCandidate(c);
    }
  }

  void toggleMute() {
    if (!enabled) return;
    muted = !muted;
    for (final t in stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    changed();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    if (remoteTrack != null) await Helper.setVolume(volume, remoteTrack!);
    changed();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    changed();
  }

  Future<void> sampleStats() async {
    for (final report in await pc?.getStats() ?? <StatsReport>[]) {
      final values = report.values;
      if (report.type == 'outbound-rtp')
        bytesSent = (values['bytesSent'] as num?)?.toInt() ?? bytesSent;
      if (report.type == 'inbound-rtp')
        bytesReceived =
            (values['bytesReceived'] as num?)?.toInt() ?? bytesReceived;
    }
  }

  Future<void> closePeer() async {
    final old = pc;
    pc = null;
    peerId = null;
    callId = null;
    remoteTrack = null;
    await old?.close();
    await old?.dispose();
  }

  Future<void> leave({bool send = true}) async {
    ++lifecycle;
    enabled = false;
    muted = false;
    if (send && room.connected) {
      // 退出与网络 onDone 可以竞争；通知失败不能阻止释放麦克风和音频轨。
      try {
        room.send({'type': 'voice', 'enabled': false});
      } catch (_) {}
    }
    await closePeer();
    ice.clear();
    final old = stream;
    stream = null;
    for (final t in old?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await old?.dispose();
    state = '未开启语音';
    changed();
  }

  Future<void> close() async {
    disposed = true;
    await subscription.cancel();
    await leave();
    await queue.catchError((Object _) {});
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
