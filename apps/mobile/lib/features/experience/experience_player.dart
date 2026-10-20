import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import '../playback/widgets/player_library_view.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../playback/player_page.dart';
import 'chat_panel.dart';
import 'episode_sheet.dart';
import 'invite_pages.dart';
import 'settings_pages.dart';
import 'conversation.dart';

class ExperiencePlayer extends StatefulWidget {
  const ExperiencePlayer({
    super.key,
    this.film,
    required this.library,
    this.episode = 1,
    this.resume,
  });
  final Film? film;
  final LibraryState library;
  final int episode;
  final WatchEntry? resume;
  @override
  State<ExperiencePlayer> createState() => _ExperiencePlayerState();
}

class _ExperiencePlayerState extends State<ExperiencePlayer> {
  Film get film => widget.film!;
  int tab = 0;
  late int episode = widget.episode;
  int? resumedGeneration;
  int? volumeGeneration;
  PlayerPresentation? player;
  late final intent = WatchIntent()
    ..manuallyPaused = widget.library.scenario == 'manual-pause'
    ..peerReady = ![
      'peer-buffering',
      'peer-offline',
    ].contains(widget.library.scenario);
  bool get shared =>
      widget.library.preview && widget.library.scenario != 'private-chat-empty';
  @override
  void dispose() {
    intent.dispose();
    final s = player?.session;
    if (s?.source != null && s!.core.playerDuration > Duration.zero) {
      unawaited(
        widget.library
            .record(
              WatchEntry(
                film.id,
                s.core.playerPosition.inSeconds,
                episode,
                // 个人播放只更新个人进度；真实同看使用独立房间路由。
                shared:
                    widget.library.preview && (widget.resume?.shared ?? false),
              ),
            )
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  Future<void> invite() async {
    // 打开房间会创建新的播放会话，先暂停个人会话，防止两个路由同时发声。
    await player?.session.pause();
    if (!mounted) return;
    await showInvite(
      context,
      film: film,
      library: widget.library,
      episode: episode,
      position: player?.session.core.playerPosition.inSeconds ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) => widget.film == null
      ? const PlayerPage(roomName: '个人观看')
      : PlayerPage(
          roomName: film.title,
          initialSource: designSource(film),
          onManualPause: () {
            intent.pause();
            if (mounted)
              setState(() => widget.library.scenario = 'manual-pause');
          },
          canStartPlayback: () {
            if (!intent.peerReady) {
              tell(context, '等待好友准备，当前为同步状态预览。');
              return false;
            }
            intent.play();
            return true;
          },
          presentation: (context, controls, surface) {
            // 输入法展开时收起媒体区，为输入框和消息列表保留可用高度。
            final composing = MediaQuery.viewInsetsOf(context).bottom > 0;
            player = controls;
            final s = controls.session;
            if (!s.loading &&
                s.source != null &&
                s.core.mediaPlayer != null &&
                volumeGeneration != s.generation) {
              volumeGeneration = s.generation;
              unawaited(
                s.core.mediaPlayer!.setVolume(widget.library.movieVolume * 100),
              );
            }
            if (widget.resume != null &&
                !s.loading &&
                s.source != null &&
                s.core.playerDuration > Duration.zero &&
                resumedGeneration != s.generation) {
              resumedGeneration = s.generation;
              unawaited(s.seek(Duration(seconds: widget.resume!.seconds)));
            }
            return Forest(
              child: Column(
                children: [
                  if (!intent.peerReady)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            intent.peer(true);
                            setState(
                              () => widget.library.scenario =
                                  intent.manuallyPaused
                                  ? 'manual-pause'
                                  : 'normal',
                            );
                          },
                          child: const Text('模拟好友恢复 · 保持暂停'),
                        ),
                        TextButton(
                          onPressed: () {
                            intent.peer(true);
                            setState(
                              () => widget.library.scenario =
                                  'private-chat-empty',
                            );
                          },
                          child: const Text('结束同看'),
                        ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                    child: Row(
                      children: [
                        IconTap(
                          'arrow-left',
                          '返回',
                          () => Navigator.pop(context),
                        ),
                        const Expanded(child: Text('正在观看', style: DS.toolbar)),
                        IconTap('ellipsis', '播放器更多功能', () => _more(controls)),
                      ],
                    ),
                  ),
                  if (!composing)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: s.source == null
                          ? PlayerEmptySurface(
                              player: controls,
                              cover: film.id == 'mountains'
                                  ? 'assets/design/media/media-mountains-landscape.png'
                                  : film.image,
                            )
                          : surface,
                    ),
                  if (controls.error != null)
                    Text(
                      controls.error!,
                      style: TextStyle(color: DSPalette.of(context).amber),
                    ),
                  if (!composing)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Image.asset(
                              film.image,
                              width: 52,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.source?.title ?? film.title,
                                  style: const TextStyle(
                                    fontSize: DS.sectionSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${film.genre} · 2026${film.episodes > 1 ? ' · 第 $episode 集' : ''}',
                                  style: DS.smallFor(context),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed:
                                s.source == null && !widget.library.preview
                                ? null
                                : invite,
                            child: const Text('邀请一起看'),
                          ),
                        ],
                      ),
                    ),
                  if (!composing && shared)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          const MountainAvatar(initial: '满', size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_status(), style: DS.smallFor(context)),
                          ),
                          Text('同步预览', style: DS.smallFor(context)),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: DSTabs(
                          labels: const ['交流', '简介'],
                          index: tab,
                          onChanged: (i) {
                            FocusScope.of(context).unfocus();
                            setState(() => tab = i);
                          },
                        ),
                      ),
                      if (film.episodes > 1)
                        TextButton(
                          onPressed: () async {
                            final next = await showEpisodes(
                              context,
                              film,
                              episode,
                              shared: shared,
                            );
                            if (next != null && mounted)
                              setState(() => episode = next);
                          },
                          child: Text('选集 · $episode'),
                        ),
                      IconTap(
                        'sliders-horizontal',
                        '播放与音频',
                        () => openPage(
                          context,
                          AudioSettingsPage(
                            library: widget.library,
                            player: controls,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: MotionTabs(
                      index: tab,
                      children: [
                        ChatPanel(
                          library: widget.library,
                          onInvite: invite,
                          onVolumeChanged: (v) =>
                              s.core.mediaPlayer?.setVolume(v * 100),
                        ),
                        ListView(
                          padding: const EdgeInsets.all(DS.pageInset),
                          children: [
                            Text(
                              s.source?.title ?? film.title,
                              style: DS.section,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              film.synopsis,
                              style: DS.body.copyWith(
                                color: DSPalette.of(context).muted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '片目为设计预览，选择的视频以实际文件为准。',
                              style: DS.smallFor(context),
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
        );
  String _status() => switch (widget.library.scenario) {
    'peer-buffering' => '小满正在缓冲 · 等待准备',
    'peer-offline' => '小满已断线 · 等待重连',
    'manual-pause' => '已手动暂停 · 等待你点击播放',
    _ => shared ? '你和小满 · 预览同看状态' : '好看的，想和你聊聊',
  };
  Future<void> _more(PlayerPresentation p) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('播放器功能', style: DS.heading),
              MenuRow(
                'sliders-horizontal',
                '全部设置 ›',
                subtitle: '倍速、画幅、字幕、音轨、解码、着色器、休眠、后台播放',
                onTap: () {
                  Navigator.pop(c);
                  p.settings();
                },
              ),
              MenuRow(
                'link',
                '视频地址',
                onTap: () {
                  Navigator.pop(c);
                  p.network();
                },
              ),
              MenuRow(
                'list-video',
                '本地视频',
                onTap: () {
                  Navigator.pop(c);
                  p.local();
                },
              ),
              MenuRow(
                'bookmark',
                '截取当前画面',
                onTap: () {
                  Navigator.pop(c);
                  p.capture();
                },
              ),
              MenuRow(
                'notebook',
                '挑选截图',
                onTap: () {
                  Navigator.pop(c);
                  p.screenshots();
                },
              ),
              MenuRow(
                'minimize',
                '画中画',
                onTap: () {
                  Navigator.pop(c);
                  p.pip();
                },
              ),
              MenuRow(
                'volume-2',
                '播放与音频',
                onTap: () {
                  Navigator.pop(c);
                  openPage(
                    context,
                    AudioSettingsPage(library: widget.library, player: p),
                  );
                },
              ),
              if (p.session.playlist.isNotEmpty) ...[
                const Divider(),
                const Text('播放列表'),
                for (var i = 0; i < p.session.playlist.length; i++)
                  ListTile(
                    title: Text(p.session.playlist[i].title),
                    selected: i == p.session.playlistIndex,
                    onTap: () {
                      Navigator.pop(c);
                      p.session.setPlaylist(p.session.playlist, index: i);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
