import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import '../playback/widgets/player_library_view.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/posters.dart';
import '../catalog/media_provider.dart';
import '../playback/player_page.dart';
import '../playback/playback_source.dart';
import 'chat_panel.dart';
import 'episode_sheet.dart';
import 'invite_pages.dart';
import 'settings_pages.dart';
import 'conversation.dart';
import 'watch_controls.dart';

Future<void> openCatalogPlayer(
  BuildContext context,
  Film film,
  LibraryState library,
) async {
  if (!film.remote) {
    await openPage(context, ExperiencePlayer(film: film, library: library));
    return;
  }
  try {
    final provider = library.provider!;
    final detail = await provider.detail(film.id);
    final line =
        detail.lines.where((line) => line.direct).firstOrNull ??
        detail.lines.firstOrNull;
    if (line == null || line.episodes.isEmpty) throw StateError('暂无可用片源');
    final source = await provider.resolve(
      film.id,
      episode: 1,
      lineCode: line.code,
    );
    if (!context.mounted) return;
    library.remember([detail.film]);
    await openPage(
      context,
      ExperiencePlayer(
        film: detail.film.withEpisodes(line.episodes.length),
        library: library,
        initialSource: source,
        lineCode: line.code,
        lines: detail.lines,
      ),
    );
  } catch (_) {
    if (context.mounted) tell(context, '片源解析失败，请进入详情重试。');
  }
}

class ExperiencePlayer extends StatefulWidget {
  const ExperiencePlayer({
    super.key,
    this.film,
    required this.library,
    this.episode = 1,
    this.resume,
    this.initialSource,
    this.lineCode,
    this.lines = const [],
  });
  final Film? film;
  final LibraryState library;
  final int episode;
  final WatchEntry? resume;
  final PlaybackSource? initialSource;
  final String? lineCode;
  final List<MediaLine> lines;
  @override
  State<ExperiencePlayer> createState() => _ExperiencePlayerState();
}

class _ExperiencePlayerState extends State<ExperiencePlayer> {
  Film get film => widget.film!.withEpisodes(
    widget.lines
            .where((line) => line.code == lineCode)
            .firstOrNull
            ?.episodes
            .length ??
        widget.film!.episodes,
  );
  late String? lineCode = widget.lineCode;
  int tab = 0;
  late int episode = widget.episode;
  int? resumedGeneration;
  int? volumeGeneration;
  bool applyResume = true, selectingEpisode = false;
  PlayerPresentation? player;
  final controlsKey = GlobalKey<WatchControlsState>();
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
                lineCode: lineCode,
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
          initialSource: widget.initialSource ?? designSource(film),
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
            // Scaffold 的内容区可能已消费 MediaQuery 键盘内边距，同时检查原始视图。
            final composing =
                MediaQuery.viewInsetsOf(context).bottom > 0 ||
                View.of(context).viewInsets.bottom > 0;
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
            if (applyResume &&
                widget.resume != null &&
                !s.loading &&
                s.source != null &&
                s.core.playerDuration > Duration.zero &&
                resumedGeneration != s.generation) {
              resumedGeneration = s.generation;
              unawaited(s.seek(Duration(seconds: widget.resume!.seconds)));
            }
            final p = DSPalette.of(context);
            return Forest(
              child: LayoutBuilder(
                builder: (context, bounds) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DS.space4,
                        vertical: DS.space4,
                      ),
                      child: Row(
                        children: [
                          IconTap(
                            'arrow-left',
                            '返回',
                            () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.source?.title ?? film.title,
                                  key: const Key('watch-header-title'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DS.toolbar,
                                ),
                                const SizedBox(height: DS.space2),
                                Text(
                                  '${film.genre} · ${film.episodes > 1
                                      ? '第 $episode 集 · 共 ${film.episodes} 集'
                                      : film.remote
                                      ? film.meta
                                      : '${film.minutes} 分钟'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DS.smallFor(context),
                                ),
                              ],
                            ),
                          ),
                          IconTap('ellipsis', '播放器更多功能', () => _more(controls)),
                        ],
                      ),
                    ),
                    if (!composing && bounds.maxHeight >= 400)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DS.pageInset,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: bounds.maxHeight * .4,
                            ),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  DS.panelRadius,
                                ),
                                child: s.source == null
                                    ? WatchCover(
                                        cover: homeArtwork(
                                          film,
                                          landscape: true,
                                        ),
                                        onChoose: () => controlsKey.currentState
                                            ?.chooseSource(),
                                      )
                                    : surface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (controls.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DS.pageInset,
                        ),
                        child: Text(
                          controls.error!,
                          style: DS.small.copyWith(color: p.amber),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DS.pageInset,
                        DS.space4,
                        DS.pageInset,
                        DS.space12,
                      ),
                      child: WatchControls(
                        key: controlsKey,
                        player: controls,
                        library: widget.library,
                        shared: shared,
                        status: _status(),
                        onInvite: invite,
                        lines: widget.lines,
                        lineCode: lineCode,
                        onLine: _selectLine,
                        onPeerReady: !intent.peerReady
                            ? () {
                                intent.peer(true);
                                setState(
                                  () => widget.library.scenario =
                                      intent.manuallyPaused
                                      ? 'manual-pause'
                                      : 'normal',
                                );
                              }
                            : null,
                        onEndPreview: shared
                            ? () {
                                intent.peer(true);
                                setState(
                                  () => widget.library.scenario =
                                      'private-chat-empty',
                                );
                              }
                            : null,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, DS.space12),
                        child: Material(
                          type: MaterialType.transparency,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: DS.pageInset + DS.space12,
                                ),
                                child: Row(
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
                                    const SizedBox(width: DS.space8),
                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          DSIcon(
                                            'lock-keyhole',
                                            size: DS.chevronSize,
                                            color: p.muted,
                                          ),
                                          const SizedBox(width: DS.space4),
                                          Flexible(
                                            child: Text(
                                              '私密交流',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: DS.smallFor(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: DS.pageInset + DS.space12,
                                ),
                                child: Divider(height: 1),
                              ),
                              Expanded(
                                child: MotionTabs(
                                  index: tab,
                                  children: [
                                    ChatPanel(
                                      library: widget.library,
                                      compact: true,
                                      onInvite: invite,
                                      composerHeader: WatchComposerBar(
                                        player: controls,
                                        shared: shared,
                                        episode: film.episodes > 1
                                            ? episode
                                            : null,
                                        onTogether: () => controlsKey
                                            .currentState
                                            ?.showTogether(),
                                        onEpisode: _selectEpisode,
                                        onQuality: () => controlsKey
                                            .currentState
                                            ?.chooseQuality(),
                                      ),
                                    ),
                                    ListView(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            DS.pageInset + DS.panelPadding,
                                        vertical: DS.panelPadding,
                                      ),
                                      children: [
                                        Text(
                                          film.synopsis,
                                          style: DS.body.copyWith(
                                            color: p.muted,
                                          ),
                                        ),
                                        const SizedBox(height: DS.space12),
                                        Text(
                                          film.remote
                                              ? '第一播放源 · 线路不可用时可返回详情换线。'
                                              : '片目为设计预览，选择的视频以实际文件为准。',
                                          style: DS.smallFor(context),
                                        ),
                                        const SizedBox(height: DS.space12),
                                        PlayerQuickActions(player: controls),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

  Future<void> _selectEpisode() async {
    if (selectingEpisode) return;
    final next = await showEpisodes(context, film, episode, shared: shared);
    if (next == null || !mounted || next == episode) return;
    if (!film.remote) {
      setState(() => episode = next);
      return;
    }
    selectingEpisode = true;
    try {
      final source = await widget.library.provider!.resolve(
        film.id,
        episode: next,
        lineCode: lineCode,
      );
      if (!mounted) return;
      applyResume = false;
      await player?.session.setPlaylist([source]);
      if (mounted) setState(() => episode = next);
    } catch (error) {
      if (mounted) tell(context, error.toString());
    } finally {
      selectingEpisode = false;
    }
  }

  Future<void> _selectLine(String code) async {
    if (selectingEpisode || code == lineCode) return;
    final line = widget.lines.where((line) => line.code == code).firstOrNull;
    if (line == null || line.episodes.isEmpty) return;
    selectingEpisode = true;
    try {
      final next = episode.clamp(1, line.episodes.length);
      final source = await widget.library.provider!.resolve(
        film.id,
        episode: next,
        lineCode: code,
      );
      if (!mounted) return;
      applyResume = false;
      await player?.session.setPlaylist([source]);
      if (mounted)
        setState(() {
          lineCode = code;
          episode = next;
        });
    } catch (_) {
      if (mounted) tell(context, '切换片源失败，请重试。');
    } finally {
      selectingEpisode = false;
    }
  }

  String _status() => switch (widget.library.scenario) {
    'peer-buffering' => '小满正在缓冲 · 等待准备',
    'peer-offline' => '小满已断线 · 等待重连',
    'manual-pause' => '已手动暂停 · 等待你点击播放',
    _ => shared ? '你和小满 · 预览同看状态' : '个人观看 · 尚未加入房间',
  };
  Future<void> _more(PlayerPresentation p) => showDSSheet<void>(
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
