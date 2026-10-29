import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/window_layout.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/search_page.dart';
import '../catalog/media_provider.dart';
import '../catalog/posters.dart';
import '../playback/player_page.dart';
import '../playback/playback_source.dart';
import 'chat_panel.dart';
import 'episode_sheet.dart';
import 'invite_pages.dart';
import 'short_playback.dart';

class ShortFeed extends StatefulWidget {
  const ShortFeed({super.key, required this.library, required this.active});
  final LibraryState library;
  final bool active;
  @override
  State<ShortFeed> createState() => _ShortFeedState();
}

class _ShortFeedState extends State<ShortFeed> {
  late final pager = PageController(initialPage: remote ? 0 : 7);
  late int episode = remote ? 1 : 8;
  PlayerPresentation? current;
  bool get remote => widget.library.provider != null;
  Film? remoteFilm;
  MediaLine? line;
  List<MediaLine> lines = const [];
  PlaybackSource? source;
  bool loading = false;
  String? error;
  int generation = 0;
  final resolvedEpisodes = <String, int>{};
  WatchEntry? pausedEntry;
  int? resumedGeneration;
  Object? resumedSession;
  Film get film => remote
      ? remoteFilm ?? const Film('whisklet:pending', '正在加载短剧…', '短剧', '', 0)
      : films.last;

  @override
  void initState() {
    super.initState();
    if (remote) unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final provider = widget.library.provider!;
      final page = await provider.browse(21);
      if (page.items.isEmpty) throw StateError('暂无短剧');
      final detail = await provider.detail(page.items.first.id);
      final preferred = preferredShortLine(detail.lines);
      if (preferred == null || preferred.episodes.isEmpty)
        throw StateError('暂无片源');
      if (!mounted) return;
      setState(() {
        remoteFilm = detail.film.withEpisodes(preferred.episodes.length);
        line = preferred;
        lines = detail.lines;
        loading = false;
      });
      widget.library.remember([film]);
      if (widget.active) await resolveEpisode(episode);
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = '短剧加载失败，点击重试';
        });
    }
  }

  void recordProgress() {
    final session = current?.session;
    if (!remote ||
        remoteFilm == null ||
        session == null ||
        session.loading ||
        session.core.playerDuration <= Duration.zero)
      return;
    final loadedEpisode = resolvedEpisodes[session.source?.identity];
    if (loadedEpisode == null) return;
    // 解析期间 UI 已切集，进度必须归属真正装载的片源而非当前页码。
    final entry = WatchEntry(
      film.id,
      session.core.playerPosition.inSeconds,
      loadedEpisode,
      lineCode: line?.code,
    );
    pausedEntry = entry;
    resumedSession = session;
    resumedGeneration = session.generation;
    unawaited(widget.library.record(entry).catchError((Object _) {}));
  }

  Future<void> resolveEpisode(int next) async {
    if (remoteFilm == null) return;
    final request = ++generation;
    final continuePlaying = current?.session.core.playerPlaying ?? false;
    recordProgress();
    await current?.session.pause();
    if (!mounted || request != generation) return;
    setState(() {
      episode = next;
      loading = true;
      error = null;
    });
    try {
      final value = await widget.library.provider!.resolve(
        film.id,
        episode: next,
        lineCode: line?.code,
      );
      if (!mounted || request != generation) return;
      resolvedEpisodes.removeWhere(
        (identity, _) => identity != current?.session.source?.identity,
      );
      resolvedEpisodes[value.identity] = next;
      source = value;
      if (widget.active) {
        final session = current?.session;
        await session?.setPlaylist([value]);
        if (mounted &&
            request == generation &&
            widget.active &&
            TickerMode.valuesOf(context).enabled &&
            (ModalRoute.isCurrentOf(context) ?? true) &&
            continuePlaying) {
          await session?.play();
        }
      }
      if (mounted && request == generation) setState(() => loading = false);
    } catch (_) {
      if (mounted && request == generation)
        setState(() {
          loading = false;
          error = '片源解析失败，点击重试';
        });
    }
  }

  @override
  void didUpdateWidget(covariant ShortFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      recordProgress();
      unawaited(current?.session.pause());
      current = null;
    } else if (widget.active &&
        !oldWidget.active &&
        remote &&
        source == null &&
        !loading) {
      unawaited(remoteFilm == null ? load() : resolveEpisode(episode));
    }
  }

  @override
  void dispose() {
    recordProgress();
    ++generation;
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = remote ? source : designSource(film);
    // 路由覆盖时让短剧停止持有媒体，避免搜索页后面继续播放。
    final visible =
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (media != null && visible)
      return MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: PlayerPage(
          key: const ValueKey('short-player-owner'),
          roomName: film.title,
          initialSource: media,
          presentation: (context, p, surface) {
            current = p;
            final entry = pausedEntry;
            final session = p.session;
            if (remote &&
                entry != null &&
                entry.episode == episode &&
                !session.loading &&
                session.source?.identity == media.identity &&
                session.core.playerDuration > Duration.zero &&
                (!identical(resumedSession, session) ||
                    resumedGeneration != session.generation)) {
              resumedSession = session;
              resumedGeneration = session.generation;
              unawaited(session.seek(Duration(seconds: entry.seconds)));
            }
            return _content(
              bottomInset: bottomInset,
              player: remote ? p : null,
              surface: remote
                  ? ShortVideoSurface(
                      player: p,
                      onRetry: () => resolveEpisode(episode),
                    )
                  : surface,
            );
          },
        ),
      );
    // 原稿帧仅作预览封面；没有真实片源时明确标注，绝不推进假视频进度。
    return _content();
  }

  Future<void> _selectEpisode() async {
    final next = await showEpisodes(
      context,
      film,
      episode,
      shared: widget.library.preview,
    );
    if (next == null || !mounted) return;
    if (!remote) setState(() => episode = next);
    if (!pager.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      pager.jumpToPage(next - 1);
    } else {
      pager.animateToPage(
        next - 1,
        duration: DSMotion.navigation,
        curve: DSMotion.curve,
      );
    }
  }

  Future<void> _selectLine() async {
    final selected = await showModalBottomSheet<MediaLine>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final value in lines)
              ListTile(
                title: Text(value.name),
                subtitle: Text('${value.episodes.length} 集'),
                selected: value.code == line?.code,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null || selected.code == line?.code) return;
    recordProgress();
    await current?.session.pause();
    if (!mounted) return;
    current = null;
    pausedEntry = null;
    setState(() {
      line = selected;
      remoteFilm = film.withEpisodes(selected.episodes.length);
      episode = episode.clamp(1, selected.episodes.length);
      source = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pager.hasClients) pager.jumpToPage(episode - 1);
    });
    await resolveEpisode(episode);
  }

  Widget _content({
    Widget? surface,
    double? bottomInset,
    PlayerPresentation? player,
  }) => ColoredBox(
    color: DSPalette.media,
    child: PortraitMediaFrame(
      child: _feedContent(
        surface: surface,
        bottomInset: bottomInset,
        player: player,
      ),
    ),
  );

  Widget _feedContent({
    Widget? surface,
    double? bottomInset,
    PlayerPresentation? player,
  }) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        surface: DSPalette.media,
        onSurface: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      extensions: [DSPalette.dark],
      textTheme: Theme.of(context).textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
    ),
    // Theme 不会替换外层 Material 已设置的 DefaultTextStyle，媒体覆盖层显式指定白色。
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bottom = bottomInset ?? MediaQuery.paddingOf(context).bottom;
          final favorite = widget.library.favorites.contains(film.id);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (surface != null && !remote)
                Positioned.fill(child: surface)
              else
                PageView.builder(
                  controller: pager,
                  scrollDirection: Axis.vertical,
                  itemCount: film.episodes,
                  onPageChanged: (index) {
                    if (remote) {
                      unawaited(resolveEpisode(index + 1));
                    } else {
                      setState(() => episode = index + 1);
                    }
                  },
                  itemBuilder: (_, i) => surface != null && i == episode - 1
                      ? surface
                      : FilmArtwork(
                          film,
                          cacheWidth: null,
                          excludeFromSemantics: true,
                        ),
                ),
              if (remote && (loading || error != null))
                Center(
                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : TextButton(
                          onPressed: () => remoteFilm == null
                              ? load()
                              : resolveEpisode(episode),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Colors.transparent,
                        Color(0x24000000),
                        Color(0xED101216),
                      ],
                      stops: [0, .28, .54, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 16,
                right: 8,
                child: Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      tooltip: '搜索短剧',
                      onPressed: () {
                        recordProgress();
                        openPage(
                          context,
                          SearchPage(
                            library: widget.library,
                            initialKind: '短剧',
                          ),
                        );
                      },
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const DSIcon(
                        'search',
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                top: 116,
                bottom: bottom + 24,
                end: 8,
                width: 56,
                child: Align(
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    child: Column(
                      key: const Key('short-action-rail'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _action(
                          'favorite',
                          favorite ? 'bookmark-check' : 'bookmark',
                          '收藏',
                          () async {
                            try {
                              await widget.library.toggleFavorite(film);
                              if (mounted) setState(() {});
                            } catch (_) {
                              if (mounted) tell(context, '收藏保存失败，请重试。');
                            }
                          },
                          selected: favorite,
                        ),
                        const SizedBox(height: 6),
                        _action(
                          'chat',
                          'message-circle',
                          '私聊',
                          () => showPrivateChat(context, widget.library),
                          unread: widget.library.scenario == 'short-unread',
                        ),
                        const SizedBox(height: 6),
                        _action('episodes', 'list-video', '选集', _selectEpisode),
                        if (remote && lines.length > 1) ...[
                          const SizedBox(height: 6),
                          _action('source', 'refresh-cw', '换源', _selectLine),
                        ],
                        const SizedBox(height: 6),
                        _action(
                          'invite',
                          'users-round',
                          '一起看',
                          () => showInvite(
                            context,
                            film: film,
                            library: widget.library,
                            episode: episode,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 16,
                end: 80,
                bottom: bottom + 12,
                child: ConstrainedBox(
                  key: const Key('short-details'),
                  // 控件与信息分别占位；大字体或矮屏时信息可滚动，不覆盖顶部导航。
                  constraints: BoxConstraints(
                    maxHeight: (constraints.maxHeight - bottom - 96).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          film.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 10,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '第 $episode 集 · 共 ${film.episodes} 集',
                          key: const Key('short-episode-label'),
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.white70,
                          ),
                        ),
                        if (film.genre.isNotEmpty)
                          Text(
                            film.genre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: Colors.white60,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          remote ? film.synopsis : '有些重逢，是命中注定。',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.white70,
                          ),
                        ),
                        if (player != null)
                          ShortPlaybackControls(player: player),
                        if (widget.library.preview) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.library.scenario == 'peer-offline'
                                ? '小满已断线 · 预览'
                                : '与小满一起看 · 预览',
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.4,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _action(
    String id,
    String icon,
    String text,
    VoidCallback tap, {
    bool selected = false,
    bool unread = false,
  }) => Semantics(
    selected: selected,
    child: TextButton(
      key: Key('short-$id'),
      onPressed: remote && remoteFilm == null
          ? null
          : () {
              recordProgress();
              tap();
            },
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 64),
        padding: const EdgeInsets.symmetric(vertical: 4),
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white.withValues(alpha: .24)
                      : Colors.black.withValues(alpha: .22),
                ),
                child: Center(
                  child: DSIcon(icon, size: 20, color: Colors.white),
                ),
              ),
              if (unread)
                Positioned(
                  top: -2,
                  right: -3,
                  child: Container(
                    width: 14,
                    height: 14,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '1',
                      style: TextStyle(
                        fontSize: 8,
                        color: DSPalette.media,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              height: 1.2,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
            ),
          ),
        ],
      ),
    ),
  );
}
