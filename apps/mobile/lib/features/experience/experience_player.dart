import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import '../../design/adaptive_watch_layout.dart';
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
import 'short_feed.dart';
import 'conversation.dart';
import 'watch_controls.dart';

/// 首页等入口的快速播放：先落播放器页再解析，把网络等待放进播放器的加载态，
/// 避免入口按钮长时间转圈、页面无响应的空窗。
Future<void> openCatalogPlayer(
  BuildContext context,
  Film film,
  LibraryState library,
) async {
  if (!film.remote) {
    await openPage(context, ExperiencePlayer(film: film, library: library));
    return;
  }
  // 短剧是竖屏信息流：任何入口点击观看都进短剧播放器，横屏播放器只留给长视频。
  if (film.short) {
    await openPage(
      context,
      ShortFeed(library: library, active: true, initialFilm: film),
    );
    return;
  }
  await openPage(
    context,
    ExperiencePlayer(film: film, library: library, autoResolve: true),
  );
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
    this.autoResolve = false,
  });
  final Film? film;
  final LibraryState library;
  final int episode;
  final WatchEntry? resume;
  final PlaybackSource? initialSource;
  final String? lineCode;
  final List<MediaLine> lines;

  /// 无预解析源时进入页面自动选线解析（首页轮播等快速入口）。
  final bool autoResolve;
  @override
  State<ExperiencePlayer> createState() => _ExperiencePlayerState();
}

class _ExperiencePlayerState extends State<ExperiencePlayer> {
  // 集数统一为最多集数线路的数量，切换线路时展示层不再收窄。
  Film? _resolvedFilm;
  Film get film => _resolvedFilm ?? widget.film!;
  late String? lineCode = widget.lineCode;
  int tab = 0;
  late int episode = widget.episode;
  int? resumedGeneration;
  int? volumeGeneration;
  bool applyResume = true, selectingEpisode = false;
  bool _autoResolving = false;
  String? _resolveError;
  PlaybackSource? _pendingAutoSource;
  List<MediaLine> _autoLines = const [];
  PlayerPresentation? player;
  final controlsKey = GlobalKey<WatchControlsState>();

  @override
  void initState() {
    super.initState();
    // 快速入口或详情页立即进入：无预解析源且是远程片源时，进入播放器后自动解析
    if (widget.autoResolve &&
        widget.initialSource == null &&
        film.remote) {
      unawaited(_autoResolve());
    }
  }

  /// 拉详情选线并解析目标集，完成后替换播放源；解析中及失败均有明确界面反馈。
  Future<void> _autoResolve() async {
    if (_autoResolving) return;
    setState(() {
      _autoResolving = true;
      _resolveError = null;
    });
    try {
      final provider = widget.library.provider;
      if (provider == null) return;
      final lines = widget.lines.isNotEmpty ? widget.lines : _autoLines;
      MediaDetail detail;
      if (lines.isNotEmpty) {
        detail = MediaDetail(film, lines);
      } else {
        detail = await provider.detail(film.id);
        if (!mounted) return;
        widget.library.remember([detail.unifiedFilm]);
        setState(() {
          _resolvedFilm = detail.unifiedFilm;
          _autoLines = detail.lines;
        });
      }
      final currentLines = detail.lines;
      final line = (lineCode != null
              ? currentLines.where((l) => l.code == lineCode).firstOrNull
              : null) ??
          preferredPlaybackLine(currentLines) ??
          (currentLines.isNotEmpty ? currentLines.first : null);
      if (line == null || line.episodes.isEmpty) return;
      final targetEpisode = episode.clamp(1, line.episodes.length);
      final source = await provider.resolve(
        film.id,
        episode: targetEpisode,
        lineCode: line.code,
        cachedDetail: detail,
      );
      if (!mounted) return;
      String? actualLine = line.code;
      final identity = source.identity;
      if (identity.startsWith('${film.id}:')) {
        actualLine = identity.split(':')[2];
      }
      setState(() {
        if (_autoLines.isEmpty) _autoLines = detail.lines;
        lineCode = actualLine;
        episode = targetEpisode;
      });
      if (player != null) {
        await player!.session.setPlaylist([source]);
      } else {
        _pendingAutoSource = source;
      }
    } catch (e) {
      if (mounted) setState(() => _resolveError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _autoResolving = false);
    }
  }

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
      final entry = WatchEntry(
        film.id,
        s.core.playerPosition.inSeconds,
        episode,
        lineCode: lineCode,
        // 个人播放只更新个人进度；真实同看使用独立房间路由。
        shared: widget.library.preview && (widget.resume?.shared ?? false),
      );
      final library = widget.library;
      // dispose 处于 BuildOwner.lockState 阶段，微任务延后通知避免锁定树时触发 markNeedsBuild。
      Future.microtask(() {
        unawaited(library.record(entry).catchError((Object _) {}));
      });
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
      lineCode: lineCode,
      sourceIdentity: player?.session.source?.identity,
    );
  }

  String _formatSubtitle(Film f, int ep) {
    if (f.episodes > 1) {
      return '${f.genre} · 第 $ep 集 · 共 ${f.episodes} 集';
    }
    if (f.remote) {
      return '${f.genre} · ${f.meta}';
    }
    return '${f.genre} · ${f.minutes} 分钟';
  }

  @override
  Widget build(BuildContext context) {
    final filmTitle = player?.session.source?.title ?? film.title;
    final filmSubtitle = _formatSubtitle(film, episode);
    return widget.film == null
        ? const PlayerPage(roomName: '个人观看')
        : PlayerPage(
            roomName: film.title,
            title: filmTitle,
            subtitle: filmSubtitle,
            onMore: () {
              if (player != null) _more(player!);
            },
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
              if (_pendingAutoSource != null) {
                final pending = _pendingAutoSource!;
                _pendingAutoSource = null;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  controls.session.setPlaylist([pending]);
                });
              }
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
              // 竖屏源（AI 漫剧/短剧）按视频自身比例展示；宽高未知时回落 16:9。
              final vp = s.core.mediaPlayer?.state.videoParams;
              final videoW = vp?.w ?? 0;
              final videoH = vp?.h ?? 0;
              final portrait = videoW > 0 && videoH > 0 && videoW < videoH;
              // 手机与平板设备均使用无边距通铺播放器，占满媒体区完整可用宽度。
              const mediaInset = 0.0;
              final currentSubtitle = _formatSubtitle(film, episode);
              return Forest(
                child: LayoutBuilder(
                  builder: (context, bounds) => AdaptiveWatchLayout(
                    showMedia: !composing && bounds.maxHeight >= 400,
                    mediaAspectRatio: portrait ? videoW / videoH : 16 / 9,
                    mediaInset: mediaInset,
                    header: const SizedBox.shrink(),
                    media: SizedBox.expand(
                      child: s.source == null
                          ? WatchCover(
                              cover: homeArtwork(film, landscape: true),
                              onChoose: () => controlsKey.currentState
                                  ?.chooseSource(),
                              film: film,
                              resolving: _autoResolving,
                              error: _resolveError,
                              onRetry: () =>
                                  unawaited(_autoResolve()),
                              episode: episode,
                              title: s.source?.title ?? film.title,
                              subtitle: currentSubtitle,
                              onBack: () => Navigator.pop(context),
                              onMore: () => _more(controls),
                            )
                          : surface,
                    ),
                  controls: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                          lines: widget.lines.isEmpty
                              ? _autoLines
                              : widget.lines,
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
                    ],
                  ),
                  conversation: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            0,
                            0,
                            0,
                            DS.space12,
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: Column(
                              children: [
                                // 标签条通铺到屏幕边缘，不留左右间距。
                                Row(
                                  children: [
                                    // 标签条与「私密交流」按 2:1 分栏：两枚标签与
                                    // 私密交流各自居中在三分之一处，间距均匀。
                                    Expanded(
                                      flex: 2,
                                      child: DSTabs(
                                        labels: const ['交流', '简介'],
                                        index: tab,
                                        dense: true,
                                        onChanged: (i) {
                                          FocusScope.of(context).unfocus();
                                          setState(() => tab = i);
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
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
                                const Divider(height: 1),
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
              ),
            );
          },
        );
  }

  Future<void> _selectEpisode() async {
    if (selectingEpisode || _autoResolving) return;
    final next = await showEpisodes(context, film, episode, shared: shared);
    if (next == null || !mounted || next == episode) return;
    if (!film.remote) {
      setState(() => episode = next);
      return;
    }
    setState(() => selectingEpisode = true);
    try {
      final source = await widget.library.provider!.resolve(
        film.id,
        episode: next,
        lineCode: lineCode,
        // 线路表已在手，跳过 resolve 内部的详情往返。
        cachedDetail: MediaDetail(
          film,
          widget.lines.isEmpty ? _autoLines : widget.lines,
        ),
      );
      if (!mounted) return;
      applyResume = false;
      await player?.session.setPlaylist([source]);
      if (mounted) setState(() => episode = next);
    } catch (error) {
      if (mounted) tell(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => selectingEpisode = false);
    }
  }

  Future<void> _selectLine(String code) async {
    if (selectingEpisode || _autoResolving || code == lineCode) return;
    final lines = widget.lines.isEmpty ? _autoLines : widget.lines;
    final line = lines.where((line) => line.code == code).firstOrNull;
    if (line == null || line.episodes.isEmpty) return;
    setState(() => selectingEpisode = true);
    try {
      final next = episode.clamp(1, line.episodes.length);
      final source = await widget.library.provider!.resolve(
        film.id,
        episode: next,
        lineCode: code,
        cachedDetail: MediaDetail(film, lines),
      );
      if (!mounted) return;
      String actualLine = code;
      final identity = source.identity;
      if (identity.startsWith('${film.id}:')) {
        final parts = identity.split(':');
        if (parts.length >= 3) actualLine = parts[2];
      }
      applyResume = false;
      await player?.session.setPlaylist([source]);
      if (mounted)
        setState(() {
          lineCode = actualLine;
          episode = next;
        });
    } catch (error) {
      if (mounted) tell(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => selectingEpisode = false);
    }
  }

  String _status() {
    // 换集/换线/自动解析中给一个明确反馈，避免弹层关闭后界面静默无响应。
    if (selectingEpisode || _autoResolving) return '正在解析片源，请稍候…';
    return switch (widget.library.scenario) {
      'peer-buffering' => '小满正在缓冲 · 等待准备',
      'peer-offline' => '小满已断线 · 等待重连',
      'manual-pause' => '已手动暂停 · 等待你点击播放',
      _ => shared ? '你和小满 · 预览同看状态' : '个人观看 · 尚未加入房间',
    };
  }

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
