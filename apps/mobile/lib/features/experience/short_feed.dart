import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/search_page.dart';
import '../catalog/media_provider.dart';
import '../catalog/posters.dart';
import '../playback/player_page.dart';
import '../playback/playback_session.dart';
import '../playback/playback_source.dart';
import 'chat_panel.dart';
import 'episode_sheet.dart';
import 'invite_pages.dart';
import 'short_playback.dart';

class ShortFeed extends StatefulWidget {
  const ShortFeed({
    super.key,
    required this.library,
    required this.active,
    this.initialFilm,
    this.initialEpisode = 1,
    this.initialSeconds,
  });
  final LibraryState library;
  final bool active;

  /// 详情页/轮播等入口锚定的短剧：进入信息流直接落在这一部，
  /// 上游列表没有它时插到第一位。
  final Film? initialFilm;
  final int initialEpisode;
  final int? initialSeconds;
  @override
  State<ShortFeed> createState() => _ShortFeedState();
}

/// 一部短剧在信息流里的装载状态；详情与线路按剧缓存，来回滑动不重复解析。
class _DramaSlot {
  _DramaSlot(this.film, {this.episode = 1});
  Film film;
  MediaLine? line;
  List<MediaLine> lines = const [];
  int episode = 1;
}

/// 已装载片源的归属；进度与连播按 identity 回溯，避免页面状态抢先切换。
class _LoadedPiece {
  const _LoadedPiece(this.filmId, this.episode, this.lineCode);
  final String filmId;
  final int episode;
  final String? lineCode;
}

class _ShortFeedState extends State<ShortFeed> {
  late final pager = PageController(initialPage: remote ? 0 : 7);
  late int episode = remote ? widget.initialEpisode : 8;
  PlayerPresentation? current;
  bool get remote => widget.library.provider != null;
  final dramas = <Film>[];
  final slots = <String, _DramaSlot>{};
  final loaded = <String, _LoadedPiece>{};
  int dramaIndex = 0;
  int upstreamPage = 1;
  bool loadingMore = false;
  bool binge = false;
  String? completedIdentity;
  PlaybackSource? source;
  bool switching = false;
  bool carryPlay = false;
  // PlayerPage 尚未挂载时（首次装载/切回 tab）先记下起播意图，由 presentation 回调兑现。
  bool pendingPlay = false;
  bool loading = false;
  String? error;
  int generation = 0;
  PlaybackSession? watched;
  WatchEntry? pausedEntry;
  int? resumedGeneration;
  Object? resumedSession;
  bool synopsisExpanded = false;
  // 首次进入显示一次手势引导；用户有任何操作后消失。
  bool gestureHint = true;
  static const _stallTimeout = Duration(seconds: 25);
  Duration _stallLast = Duration.zero;
  DateTime? _stallSince;
  bool _stallAutoRetried = false;
  bool _wasCompleted = false;

  bool get hasDramas => dramas.isNotEmpty;
  Film get film => remote
      ? (hasDramas
            ? dramas[dramaIndex]
            : const Film('whisklet:pending', '正在加载短剧…', '短剧', '', 0))
      : films.last;
  _DramaSlot? get slot =>
      remote && hasDramas ? slots[dramas[dramaIndex].id] : null;

  @override
  void initState() {
    super.initState();
    if (remote) unawaited(load());
    // 引导条等真正有画面后再计时：首次加载/解析往往超过 6 秒，
    // 从 initState 起算会让提示在用户看到画面之前就消失。
    _hintTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && gestureHint) setState(() => gestureHint = false);
    });
  }

  Timer? _hintTimer;

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.library.provider!.browse(21);
      if (page.items.isEmpty) throw StateError('暂无短剧');
      if (!mounted) return;
      final anchor = widget.initialFilm;
      final items = [...page.items];
      var start = 0;
      if (anchor != null) {
        final found = items.indexWhere((value) => value.id == anchor.id);
        if (found >= 0) {
          start = found;
        } else {
          items.insert(0, anchor);
        }
      }
      setState(() {
        dramas
          ..clear()
          ..addAll(items);
        slots.clear();
        dramaIndex = start;
        upstreamPage = 1;
        loading = false;
      });
      if (anchor != null) {
        slots[anchor.id] = _DramaSlot(
          dramas[start],
          episode: widget.initialEpisode.clamp(1, dramas[start].episodes),
        );
        final seconds = widget.initialSeconds ?? 0;
        if (seconds > 0) {
          pausedEntry = WatchEntry(anchor.id, seconds, widget.initialEpisode);
        }
        if (start != 0) {
          // 两道时序都要守住：跳页要在封面树上先落位；解析完成时 build 会从
          // 封面树换成 PlayerPage 覆盖树，翻页器随换树复位到 0，需要再补一跳。
          // 用户主动翻页（离开 0/锚点页）后不再抢页。
          var landedOnce = false;
          Future<void> land() async {
            for (var attempt = 0; attempt < 600; attempt++) {
              await WidgetsBinding.instance.endOfFrame;
              if (!mounted) return;
              if (!pager.hasClients) continue;
              final page = pager.page?.round() ?? 0;
              if (page == start) {
                landedOnce = true;
                if (source != null) return;
                continue;
              }
              if (landedOnce && page != 0) return;
              try {
                pager.jumpToPage(start);
              } catch (_) {
                // 位置尚未完成布局定维，下一帧重试。
              }
            }
          }

          unawaited(land());
        }
      }
      if (widget.active) await _openDrama(start);
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = '短剧加载失败，点击重试';
        });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || !remote) return;
    loadingMore = true;
    try {
      final page = await widget.library.provider!.browse(
        21,
        page: upstreamPage + 1,
      );
      if (!mounted) return;
      setState(() {
        upstreamPage += 1;
        final known = dramas.map((value) => value.id).toSet();
        dramas.addAll(page.items.where((value) => !known.contains(value.id)));
      });
    } catch (_) {
      // 追加一页失败不打断当前播放，滑到列表末尾时会再次尝试。
    } finally {
      loadingMore = false;
    }
  }

  Future<void> _openDrama(int index) async {
    if (index < 0) return;
    if (index >= dramas.length) {
      await _loadMore();
      if (index >= dramas.length) return;
    }
    final existing = slots[dramas[index].id];
    if (index == dramaIndex &&
        existing != null &&
        existing.line != null &&
        source != null &&
        !switching) {
      return;
    }
    if (index >= dramas.length - 3) unawaited(_loadMore());
    final request = ++generation;
    completedIdentity = null;
    synopsisExpanded = false;
    // 信息流与抖音同规：进入/翻页总是起播，暂停只作用于当前画面。
    carryPlay = true;
    recordProgress();
    await current?.session.pause();
    if (!mounted || request != generation) return;
    pausedEntry = null;
    // 会话跨剧保活：只隐藏画面与更新页码，解析完成后同一会话直接接播。
    setState(() {
      dramaIndex = index;
      switching = true;
      loading = true;
      error = null;
    });
    try {
      final target = slots.putIfAbsent(
        dramas[index].id,
        () => _DramaSlot(dramas[index]),
      );
      if (target.line == null) {
        final detail = await widget.library.provider!.detail(dramas[index].id);
        if (!mounted || request != generation) return;
        final preferred = preferredShortLine(detail.lines);
        if (preferred == null || preferred.episodes.isEmpty) {
          throw StateError('暂无片源');
        }
        if (!mounted || request != generation) return;
        setState(() {
          dramas[index] = detail.unifiedFilm;
          target
            ..film = dramas[index]
            ..lines = detail.lines
            ..line = preferred
            // 起始集号允许落在整部（最多集数线路）范围内；播放时 resolve 跨线路落点。
            ..episode = target.episode.clamp(1, detail.unifiedFilm.episodes);
        });
        widget.library.remember([dramas[index]]);
      }
      await resolveEpisode(target.episode, ticket: request, forcePlay: true);
    } catch (_) {
      if (mounted && request == generation)
        setState(() {
          loading = false;
          error = '短剧加载失败，点击重试';
        });
    }
  }

  void recordProgress() {
    final session = current?.session;
    if (!remote ||
        session == null ||
        session.loading ||
        session.core.playerDuration <= Duration.zero)
      return;
    final piece = loaded[session.source?.identity];
    if (piece == null) return;
    // 解析期间 UI 已切剧/切集，进度必须归属真正装载的片源而非当前页面。
    final entry = WatchEntry(
      piece.filmId,
      session.core.playerPosition.inSeconds,
      piece.episode,
      lineCode: piece.lineCode,
    );
    pausedEntry = entry;
    resumedSession = session;
    resumedGeneration = session.generation;
    unawaited(widget.library.record(entry).catchError((Object _) {}));
  }

  Future<void> resolveEpisode(
    int next, {
    bool forcePlay = false,
    int? ticket,
    bool fromWatchdog = false,
  }) async {
    final target = slot;
    if (target == null || target.line == null) return;
    final request = ticket ?? ++generation;
    if (!fromWatchdog) _stallAutoRetried = false;
    final continuePlaying =
        forcePlay ||
        carryPlay ||
        (current?.session.core.playerPlaying ?? false);
    recordProgress();
    await current?.session.pause();
    if (!mounted || request != generation) return;
    setState(() {
      target.episode = next;
      loading = true;
      error = null;
    });
    try {
      final value = await widget.library.provider!.resolve(
        target.film.id,
        episode: next,
        lineCode: target.line?.code,
      );
      if (!mounted || request != generation) return;
      loaded.removeWhere(
        (identity, _) => identity != current?.session.source?.identity,
      );
      loaded[value.identity] = _LoadedPiece(
        target.film.id,
        next,
        target.line?.code,
      );
      completedIdentity = null;
      source = value;
      if (widget.active) {
        final session = current?.session;
        // setPlaylist 后立即 play 会被 media-kit 在 file-loaded 时按
        // open(play:false) 覆盖回暂停；统一交给 presentation 回调，等时长
        // 就绪（即 file-loaded）后再起播。
        if (session != null) await session.setPlaylist([value]);
        pendingPlay = continuePlaying;
      }
      if (mounted && request == generation)
        setState(() {
          switching = false;
          carryPlay = false;
          loading = false;
          _stallSince = null;
          _stallLast = Duration.zero;
        });
    } catch (_) {
      if (mounted && request == generation)
        setState(() {
          loading = false;
          error = '片源解析失败，点击重试';
        });
    }
  }

  void _watch(PlayerPresentation value) {
    current = value;
    final session = value.session;
    if (identical(watched, session)) return;
    watched?.positionTick.removeListener(_onPositionTick);
    watched?.removeListener(_onPlaybackTick);
    watched = session;
    // 进度节拍走轻量 ValueNotifier（不再触发整页 notifyListeners），连播/循环/
    // 看门狗等位置逻辑挂在这里；状态迁移类通知仍走 ChangeNotifier。
    session.positionTick.addListener(_onPositionTick);
    session.addListener(_onPlaybackTick);
    _onPositionTick();
  }

  /// 状态迁移通知：完成检测（连播/循环）在状态变化时判定。
  void _onPlaybackTick() {
    if (!mounted || loading) return;
    final session = watched;
    if (session == null || session.loading || session.error != null) return;
    final completed =
        session.core.playerCompleted &&
        session.core.playerDuration > Duration.zero;
    if (!completed) _wasCompleted = false;
    if (!binge) {
      if (completed && !_wasCompleted) {
        _wasCompleted = true;
        unawaited(session.seek(Duration.zero).then((_) => session.play()));
      }
      return;
    }
    if (!completed) return;
    final identity = session.source?.identity;
    if (identity == null || identity == completedIdentity) return;
    completedIdentity = identity;
    unawaited(_advanceBinge());
  }

  /// 进度节拍：连播自动接下一集/下一部、单集循环与片源卡死看门狗都由位置驱动。
  void _onPositionTick() {
    final session = watched;
    if (session == null) return;
    _checkStall(session);
  }

  /// 片源看门狗：装载完成后位置长时间不前进（上游死流）时，先静默重解析一次
  /// 拿新地址自愈，再次卡死才把错误交给用户重试。用户暂停不算卡死。
  void _checkStall(PlaybackSession session) {
    final position = session.core.playerPosition;
    final progressed = position > _stallLast && position > Duration.zero;
    _stallLast = position;
    if (progressed) {
      _stallSince = null;
      return;
    }
    final active =
        session.core.playerBuffering ||
        session.core.playerPlaying ||
        // 起播意图挂着但 mpv 始终拿不到时长（死流），同样按卡死处理。
        (pendingPlay && session.core.playerDuration <= Duration.zero);
    if (!active) {
      _stallSince = null;
      return;
    }
    final since = _stallSince ??= DateTime.now();
    if (DateTime.now().difference(since) < _stallTimeout) return;
    _stallSince = null;
    if (session.source == null || !_stallAutoRetried) {
      _stallAutoRetried = true;
      unawaited(
        resolveEpisode(slot?.episode ?? 1, forcePlay: true, fromWatchdog: true),
      );
      return;
    }
    if (error == null) {
      setState(() {
        error = '播放超时，点击重试或更换线路';
        loading = false;
      });
    }
  }

  Future<void> _advanceBinge() async {
    final target = slot;
    if (target != null && target.episode < target.film.episodes) {
      await resolveEpisode(target.episode + 1, forcePlay: true);
      return;
    }
    // 本部最后一集播完：连播滑到下一部短剧从第 1 集继续；没有更多就停下。
    if (!mounted || !pager.hasClients) return;
    final next = (pager.page?.round() ?? dramaIndex) + 1;
    if (next >= dramas.length) await _loadMore();
    if (!mounted || next >= dramas.length) return;
    // EOF 时会话已非播放态，翻剧要沿用连播意图而不是继承「暂停」。
    carryPlay = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      pager.jumpToPage(next);
    } else {
      pager.animateToPage(
        next,
        duration: DSMotion.navigation,
        curve: DSMotion.curve,
      );
    }
  }

  @override
  void didUpdateWidget(covariant ShortFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      recordProgress();
      unawaited(current?.session.pause());
      current = null;
      watched?.positionTick.removeListener(_onPositionTick);
      watched?.removeListener(_onPlaybackTick);
      watched = null;
    } else if (widget.active && !oldWidget.active && remote) {
      if (source != null) {
        // 回到信息流总是续播：PlayerPage 重挂载后由 presentation 回调兑现。
        pendingPlay = true;
      } else if (!loading) {
        unawaited(hasDramas ? _openDrama(dramaIndex) : load());
      }
    }
  }

  @override
  void dispose() {
    recordProgress();
    ++generation;
    _hintTimer?.cancel();
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
          // 信息流是全屏沉浸媒体：画面顶到状态栏后，顶部控件自避安全区。
          respectSafeArea: false,
          presentation: (context, p, surface) {
            _watch(p);
            final entry = pausedEntry;
            final session = p.session;
            final piece = loaded[session.source?.identity];
            if (remote &&
                entry != null &&
                piece != null &&
                entry.filmId == piece.filmId &&
                entry.episode == piece.episode &&
                !session.loading &&
                session.source?.identity == media.identity &&
                session.core.playerDuration > Duration.zero &&
                (!identical(resumedSession, session) ||
                    resumedGeneration != session.generation)) {
              resumedSession = session;
              resumedGeneration = session.generation;
              unawaited(session.seek(Duration(seconds: entry.seconds)));
            }
            // 时长就绪 = file-loaded 已过，此时 play 不会再被 open(play:false) 覆盖。
            if (pendingPlay &&
                p.session.source?.identity == media.identity &&
                p.session.core.playerDuration > Duration.zero) {
              pendingPlay = false;
              unawaited(p.session.play());
            }
            return _content(
              bottomInset: bottomInset,
              player: remote ? p : null,
              surface: remote
                  ? ShortVideoSurface(
                      player: p,
                      onDoubleTap: () => unawaited(_toggleFavorite(film)),
                      onRetry: () {
                        final target = slot;
                        if (target != null) {
                          unawaited(
                            resolveEpisode(target.episode, forcePlay: true),
                          );
                        }
                      },
                    )
                  : surface,
            );
          },
        ),
      );
    // 原稿帧仅作预览封面；没有真实片源时明确标注，绝不推进假视频进度。
    return _content();
  }

  /// 右列按钮与双击画面共用：收藏成功就地刷新，失败给出可重试提示。
  Future<void> _toggleFavorite(Film film) async {
    if (gestureHint && mounted) setState(() => gestureHint = false);
    try {
      await widget.library.toggleFavorite(film);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) tell(context, '收藏保存失败，请重试。');
    }
  }

  Future<void> _selectEpisode() async {
    final next = await showEpisodes(
      context,
      film,
      remote ? (slot?.episode ?? episode) : episode,
      shared: widget.library.preview,
      binge: binge,
      onBingeChanged: remote && !widget.library.preview
          ? (value) => setState(() => binge = value)
          : null,
    );
    if (next == null || !mounted) return;
    if (remote) {
      // 信息流页面即剧；选集不再翻页，直接解析所选集并起播。
      unawaited(resolveEpisode(next, forcePlay: true));
      return;
    }
    setState(() => episode = next);
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
    final target = slot;
    if (target == null) return;
    final selected = await showModalBottomSheet<MediaLine>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final value in target.lines)
              ListTile(
                title: Text(value.name),
                subtitle: Text('${value.episodes.length} 集'),
                selected: value.code == target.line?.code,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null || selected.code == target.line?.code) {
      return;
    }
    recordProgress();
    await current?.session.pause();
    if (!mounted) return;
    pausedEntry = null;
    setState(() {
      target
        ..line = selected
        // 集数展示统一为最多集数线路，不再随所选线路收窄。
        ..episode = target.episode.clamp(1, selected.episodes.length);
      dramas[dramaIndex] = target.film;
      switching = true;
    });
    await resolveEpisode(target.episode, forcePlay: true);
  }

  Widget _content({
    Widget? surface,
    double? bottomInset,
    PlayerPresentation? player,
  }) => mediaSystemBars(
    context,
    Theme(
      // 暗色媒体主题缓存构建：整页因状态迁移重建时不再每次遍历 TextTheme 着色
      // （播放期间每秒可重建数次）。
      data: _mediaTheme(Theme.of(context)),
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
                    itemCount: remote ? dramas.length : film.episodes,
                    onPageChanged: (index) {
                      if (remote) {
                        // 锚点跳页与正常翻页共用回调；同页重复触发会打断进行中的装载。
                        if (index != dramaIndex) unawaited(_openDrama(index));
                      } else {
                        setState(() => episode = index + 1);
                      }
                    },
                    itemBuilder: (_, i) {
                      if (remote &&
                          surface != null &&
                          i == dramaIndex &&
                          !switching) {
                        return surface;
                      }
                      final page = remote ? dramas[i] : film;
                      return GestureDetector(
                        // 封面态（未播放/解析失败）也要能双击收藏；
                        // translucent 只拦双击，纵向滑动照旧交给 PageView。
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: remote
                            ? () => unawaited(_toggleFavorite(page))
                            : null,
                        child: FilmArtwork(
                          page,
                          // 竖屏封面按屏宽限幅解码（dpr 已含在列表里，封面高约 1.78 倍宽）。
                          cacheWidth:
                              (MediaQuery.sizeOf(context).width *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .ceil()
                                  .clamp(480, 1080),
                          excludeFromSemantics: true,
                        ),
                      );
                    },
                  ),
                if (remote && (loading || error != null))
                  Center(
                    child: loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : TextButton(
                            onPressed: () {
                              if (dramas.isEmpty) {
                                unawaited(load());
                                return;
                              }
                              final target = slot;
                              if (target == null || target.line == null) {
                                unawaited(_openDrama(dramaIndex));
                              } else {
                                unawaited(
                                  resolveEpisode(
                                    target.episode,
                                    forcePlay: true,
                                  ),
                                );
                              }
                            },
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                  ),
                // 底部渐变要压住片源自带的烧录字幕（金/白描边字正好落在文案区），
                // 从 68% 高度起快速升到近不透明，避免字幕笔画从白字缝隙里透出。
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
                          Color(0xCC101216),
                          Color(0xF5101216),
                        ],
                        stops: [0, .28, .5, .68, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  // 播放器已跳过顶部安全区（全屏沉浸），控件自己避让状态栏。
                  top: MediaQuery.paddingOf(context).top + 6,
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
                  bottom: bottom + 40,
                  end: 8,
                  width: 56,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SingleChildScrollView(
                      child: Column(
                        key: const Key('short-action-rail'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _action('invite', 'users-round', '一起看', () async {
                            await current?.session.pause();
                            if (!context.mounted) return;
                            await showInvite(
                              context,
                              film: film,
                              library: widget.library,
                              episode: episode,
                              position:
                                  current
                                      ?.session
                                      .core
                                      .playerPosition
                                      .inSeconds ??
                                  0,
                              lineCode: slot?.line?.code,
                              sourceIdentity: current?.session.source?.identity,
                            );
                          }),
                          const SizedBox(height: 14),
                          _action(
                            'chat',
                            'message-circle',
                            '私聊',
                            () => showPrivateChat(context, widget.library),
                            unread: widget.library.scenario == 'short-unread',
                          ),
                          const SizedBox(height: 14),
                          _action(
                            'favorite',
                            favorite ? 'bookmark-check' : 'bookmark',
                            '收藏',
                            () => unawaited(_toggleFavorite(film)),
                            selected: favorite,
                          ),
                          if (remote && (slot?.lines.length ?? 0) > 1) ...[
                            const SizedBox(height: 14),
                            _action('source', 'refresh-cw', '换源', _selectLine),
                          ],
                          const SizedBox(height: 14),
                          // 选集沉到右列最底：拇指热区内的主操作。
                          _action(
                            'episodes',
                            'list-video',
                            '选集',
                            _selectEpisode,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 14,
                  end: 84,
                  bottom: bottom + 34,
                  child: Column(
                    key: const Key('short-details'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        film.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: DS.sectionSize,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
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
                      // 集数 + 连播状态行：TikTok 文案栈的第二行，点按打开选集面板。
                      GestureDetector(
                        key: const Key('short-collection'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _selectEpisode,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  '第 ${remote ? (slot?.episode ?? 1) : episode} 集 · 共 ${film.episodes} 集',
                                  key: const Key('short-episode-label'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (binge) ...[
                                const SizedBox(width: 7),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF3BE38C),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '连播中',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: Color(0xFF3BE38C),
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 简介点击展开而非滚动，纵向手势完整留给切剧翻页。
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(
                          () => synopsisExpanded = !synopsisExpanded,
                        ),
                        child: Text(
                          remote ? film.synopsis : '有些重逢，是命中注定。',
                          maxLines: synopsisExpanded ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Color(0xE0FFFFFF),
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 8,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                if (player != null)
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: bottom + 4,
                    child: ShortScrubLine(player: player),
                  ),
                // 引导放在最外层：解析失败/加载中也能看到，不依赖 surface 挂载。
                if (remote && gestureHint)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottom + 150,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          key: const Key('short-gesture-hint'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.favorite_border,
                                size: 16,
                                color: Colors.white70,
                              ),
                              SizedBox(width: 6),
                              Text(
                                '双击画面收藏 · 上下滑动切剧',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
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
      onPressed: remote && !hasDramas
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
              // TikTok 右列为裸白图标 + 文字投影，不垫底色块。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: DSIcon(icon, size: DS.iconSize, color: Colors.white),
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
          const SizedBox(height: 3),
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

/// 暗色媒体主题缓存：TextTheme.apply 每次遍历整套样式着色，播放期间页面
/// 因状态迁移高频重建，按 colorScheme/textTheme 身份缓存一次构建结果。
final Map<ThemeData, ThemeData> _mediaThemeCache = {};
ThemeData _mediaTheme(ThemeData base) {
  return _mediaThemeCache.putIfAbsent(base, () {
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        surface: DSPalette.media,
        onSurface: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      extensions: [DSPalette.dark],
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  });
}
