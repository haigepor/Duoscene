import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../design/components.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../auth/session.dart';
import '../playback/playback_session.dart';
import '../playback/player_page.dart';
import '../playback/widgets/player_library_view.dart';
import '../voice/room_voice.dart';
import 'room_connection.dart';
import 'room_playback.dart';

class RoomWatchPage extends StatefulWidget {
  const RoomWatchPage({
    super.key,
    required this.room,
    required this.auth,
    this.connection,
    this.playback,
    this.voice,
  });
  final Room room;
  final Session auth;
  final RoomConnection? connection;
  final PlaybackSession? playback;
  final RoomVoice? voice;
  @override
  State<RoomWatchPage> createState() => _RoomWatchPageState();
}

class _RoomWatchPageState extends State<RoomWatchPage>
    with WidgetsBindingObserver {
  late final room =
      widget.connection ?? RoomConnection(widget.auth, widget.room.id);
  late final playback = widget.playback ?? PlaybackSession();
  late final voice = widget.voice ?? RoomVoice(room);
  late final sync = RoomPlayback(room, playback);
  int tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync;
    if (!room.connected) unawaited(room.connect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(voice.leave());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(sync.dispose());
    if (widget.voice == null) voice.dispose();
    if (widget.connection == null) room.dispose();
    if (widget.playback == null) playback.dispose();
    super.dispose();
  }

  void audio() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => AnimatedBuilder(
      animation: Listenable.merge([voice, playback]),
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('播放与语音', style: DS.heading),
              Text(voice.error ?? voice.state, style: DS.smallFor(context)),
              const SizedBox(height: 12),
              const Text('好友语音音量'),
              Slider(
                value: voice.volume,
                onChanged: (v) => unawaited(voice.setVolume(v)),
              ),
              const Text('影片音量'),
              Slider(
                value: (playback.core.playerVolume / 100).clamp(0, 1),
                onChanged: (v) {
                  // 影片音量只作用于 mpv，不调整设备总音量，避免同时改变好友语音。
                  unawaited(playback.core.mediaPlayer?.setVolume(v * 100));
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('扬声器播放语音'),
                value: voice.speaker,
                onChanged: (_) => unawaited(voice.toggleSpeaker()),
              ),
              if (voice.enabled)
                TextButton(
                  onPressed: () => unawaited(voice.leave()),
                  child: const Text('结束语音'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([room, voice]),
    builder: (context, _) => PlayerPage(
      roomId: widget.room.id,
      roomName: widget.room.name,
      session: playback,
      presentation: (context, controls, surface) {
        final state = room.snapshot;
        final peers = (state?['peers'] as List? ?? []);
        final ready = (state?['ready'] as Map? ?? {});
        final composing = MediaQuery.viewInsetsOf(context).bottom > 0;
        return Forest(
          child: Column(
            children: [
              SizedBox(
                height: DS.toolbarHeight,
                child: Row(
                  children: [
                    IconTap(
                      'arrow-left',
                      '返回房间',
                      () => Navigator.maybePop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.room.name,
                        style: DS.toolbar,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconTap('sliders-horizontal', '同看设置', controls.settings),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: DSMotion.duration(context),
                height: composing
                    ? 88
                    : MediaQuery.sizeOf(context).width * 9 / 16,
                color: DSPalette.media,
                alignment: Alignment.center,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: playback.source == null
                      ? PlayerEmptySurface(player: controls)
                      : surface,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: room.connected
                            ? DSPalette.of(context).success
                            : DSPalette.of(context).amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !room.connected
                            ? (room.notice ?? '正在连接房间…')
                            : '${peers.length}/2 人在线 · ${state?['playing'] == true
                                  ? '同步播放中'
                                  : state?['wanted'] == true
                                  ? '等待双方缓冲'
                                  : '已暂停'}',
                        key: const Key('live-room-status'),
                        style: DS.smallFor(context),
                      ),
                    ),
                    if (!room.connected)
                      TextButton(
                        onPressed: () => unawaited(room.reconnect()),
                        child: const Text('重连'),
                      ),
                    IconTap('volume-2', '播放与语音', audio),
                  ],
                ),
              ),
              if (!composing && room.connected)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final p in peers)
                        Expanded(
                          child: Text(
                            '${p['displayName']} · ${ready[p['userId']] == true ? '已准备' : '待准备'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DS.smallFor(context),
                          ),
                        ),
                    ],
                  ),
                ),
              if (room.notice != null && room.connected)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    room.notice!,
                    style: TextStyle(
                      color: DSPalette.of(context).amber,
                      fontSize: DS.captionSize,
                    ),
                  ),
                ),
              if (controls.error != null || playback.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    controls.error ?? playback.error!,
                    style: TextStyle(color: DSPalette.of(context).amber),
                  ),
                ),
              DSTabs(
                labels: const ['交流', '视频'],
                index: tab,
                onChanged: (i) {
                  FocusScope.of(context).unfocus();
                  setState(() => tab = i);
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: MotionTabs(
                  index: tab,
                  children: [
                    LiveRoomChat(room: room, voice: voice, onAudio: audio),
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          playback.source?.title ?? '选择双方都能访问的视频',
                          style: DS.section,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '播放、暂停、拖动和倍速对双方生效。暂不支持共享本地文件或私有请求头。',
                          style: DS.smallFor(context),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: controls.network,
                              child: const Text('更换视频地址'),
                            ),
                            OutlinedButton(
                              onPressed: () => unawaited(room.reconnect()),
                              child: const Text('重新连接'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        PlayerQuickActions(player: controls),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class LiveRoomChat extends StatefulWidget {
  const LiveRoomChat({
    super.key,
    required this.room,
    required this.voice,
    required this.onAudio,
  });
  final RoomConnection room;
  final RoomVoice voice;
  final VoidCallback onAudio;
  @override
  State<LiveRoomChat> createState() => _LiveRoomChatState();
}

class _LiveRoomChatState extends State<LiveRoomChat> {
  final input = TextEditingController(), scroll = ScrollController();
  int unread = 0;
  int followGeneration = 0;
  ({double extent, double offset, GlobalKey? key, double? y})? historyAnchor;
  final messageKeys = <String, GlobalKey>{};
  late final StreamSubscription<Map<String, dynamic>> events;
  @override
  void initState() {
    super.initState();
    input.addListener(update);
    events = widget.room.events.stream.listen((e) {
      if (e['type'] == 'history' && e['initial'] == true) {
        bottom();
      } else if (e['type'] == 'history' && historyAnchor != null) {
        final anchor = historyAnchor!;
        historyAnchor = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scroll.hasClients) return;
          scroll.jumpTo(
            (anchor.offset + scroll.position.maxScrollExtent - anchor.extent)
                .clamp(0, scroll.position.maxScrollExtent),
          );
          // 先按长度估算，让旧消息进入布局；再用消息的实际位置修正懒布局估算误差。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final box = anchor.key?.currentContext?.findRenderObject();
            if (mounted &&
                scroll.hasClients &&
                box is RenderBox &&
                box.attached &&
                anchor.y != null) {
              scroll.jumpTo(
                (scroll.offset + box.localToGlobal(Offset.zero).dy - anchor.y!)
                    .clamp(0, scroll.position.maxScrollExtent),
              );
            }
          });
        });
      } else if (e['type'] == 'chat') {
        // 阅读历史时不抢走滚动位置；靠近底部才自动跟随。
        if (!scroll.hasClients || scroll.position.extentAfter < 80) {
          bottom();
        } else if (mounted) {
          setState(() => unread++);
        }
      }
    });
  }

  void update() {
    if (mounted) setState(() {});
  }

  void bottom() {
    final generation = ++followGeneration;
    if (unread != 0 && mounted) setState(() => unread = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !scroll.hasClients || generation != followGeneration)
        return;
      await scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: DSMotion.duration(context),
        curve: DSMotion.curve,
      );
      // 懒布局和未读提示收起会改变终点；仅在用户没有开始阅读历史时校准。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients && generation == followGeneration) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    });
  }

  void older() {
    if (!scroll.hasClients) return;
    final viewport = scroll.position.context.notificationContext
        ?.findRenderObject();
    final top = viewport is RenderBox
        ? viewport.localToGlobal(Offset.zero).dy
        : 0.0;
    GlobalKey? key;
    double? y;
    for (final candidate in messageKeys.values) {
      final box = candidate.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached) {
        final dy = box.localToGlobal(Offset.zero).dy;
        if (dy >= top && (y == null || dy < y)) {
          key = candidate;
          y = dy;
        }
      }
    }
    historyAnchor = (
      extent: scroll.position.maxScrollExtent,
      offset: scroll.offset,
      key: key,
      y: y,
    );
    try {
      widget.room.older();
    } catch (_) {
      historyAnchor = null;
      tell(context, '暂时无法加载历史消息，请重连后重试。');
    }
  }

  void send() {
    if (input.text.trim().isEmpty || !widget.room.connected) return;
    widget.room.chat(input.text.trim());
    input.clear();
    bottom();
  }

  @override
  void dispose() {
    unawaited(events.cancel());
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.room, widget.voice]),
    builder: (context, _) {
      final room = widget.room, voice = widget.voice;
      final rows = [
        ...room.messages,
        ...room.pending.values.map((m) => {...m, 'userId': room.auth.user?.id}),
      ];
      return Column(
        children: [
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: (_) {
                followGeneration++;
                return false;
              },
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  Center(
                    child: TextButton(
                      onPressed: room.connected && room.messages.length >= 50
                          ? older
                          : null,
                      child: const Text('查看更早消息'),
                    ),
                  ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '只有房间内的两个人可见。说说此刻的想法。',
                        style: DS.smallFor(context),
                      ),
                    ),
                  for (final m in rows)
                    Align(
                      key: messageKeys.putIfAbsent(
                        (m['id'] ?? m['clientMessageId']).toString(),
                        GlobalKey.new,
                      ),
                      alignment: m['userId'] == room.auth.user?.id
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: m['userId'] == room.auth.user?.id
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (m['userId'] != room.auth.user?.id)
                              Text(
                                m['displayName']?.toString() ?? '好友',
                                style: DS.smallFor(context),
                              ),
                            Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * .76,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: m['userId'] == room.auth.user?.id
                                    ? DSPalette.of(context).tint
                                    : DSPalette.of(context).panel,
                                borderRadius: BorderRadius.circular(
                                  DS.radiusMedium,
                                ),
                              ),
                              child: Text(
                                m['text'] as String,
                                style: TextStyle(
                                  color: m['userId'] == room.auth.user?.id
                                      ? DSPalette.of(context).onTint
                                      : DSPalette.of(context).ink,
                                ),
                              ),
                            ),
                            if (m['delivery'] == 'failed')
                              TextButton(
                                onPressed: room.connected
                                    ? () {
                                        room.chat(
                                          m['text'] as String,
                                          retryId:
                                              m['clientMessageId'] as String,
                                        );
                                        bottom();
                                      }
                                    : null,
                                child: const Text('发送失败，点击重试'),
                              )
                            else if (m['userId'] == room.auth.user?.id)
                              Text(
                                m['delivery'] == 'sending' ? '发送中…' : '已发送',
                                style: DS.smallFor(context),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (unread > 0)
            TextButton.icon(
              onPressed: bottom,
              icon: const Icon(Icons.arrow_downward, size: 16),
              label: Text('$unread 条新消息'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('live-chat-input'),
                    controller: input,
                    maxLength: 2000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: '和好友说点什么…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('live-chat-send'),
                  tooltip: '发送消息',
                  onPressed: room.connected && input.text.trim().isNotEmpty
                      ? send
                      : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                TextButton.icon(
                  key: const Key('voice-toggle'),
                  onPressed: room.connected && !voice.busy
                      ? () {
                          if (voice.enabled) {
                            voice.toggleMute();
                          } else {
                            unawaited(voice.join());
                          }
                        }
                      : null,
                  icon: Icon(
                    !voice.enabled || voice.muted
                        ? Icons.mic_off_outlined
                        : Icons.mic_none,
                    size: 20,
                  ),
                  label: Text(
                    voice.busy
                        ? '请求麦克风…'
                        : !voice.enabled
                        ? '开启语音'
                        : voice.muted
                        ? '解除静音'
                        : '麦克风已开启',
                  ),
                ),
                Expanded(
                  child: Text(
                    voice.error ?? (voice.enabled ? voice.state : '默认关闭麦克风'),
                    style: DS.smallFor(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconTap('volume-2', '语音设置', widget.onAudio),
              ],
            ),
          ),
        ],
      );
    },
  );
}
