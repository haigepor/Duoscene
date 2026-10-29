import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/window_layout.dart';
import '../../design/scroll_chrome.dart';
import '../experience/experience_player.dart';
import '../experience/episode_sheet.dart';
import '../experience/invite_pages.dart';
import '../experience/short_feed.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'posters.dart';
import 'media_provider.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.film,
    required this.library,
    this.resume,
  });
  final Film film;
  final LibraryState library;
  final WatchEntry? resume;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late int episode = widget.resume?.episode ?? 1;
  MediaDetail? detail;
  String? lineCode, loadError;
  bool loading = false;
  MediaLine? get line => detail?.lines
      .where((line) => lineCode == null || line.code == lineCode)
      .firstOrNull;
  // 集数统一以拥有最新集数的线路为准（MediaDetail.unifiedFilm），不再按当前线路收窄。
  Film get film => detail?.unifiedFilm ?? widget.film;
  @override
  void initState() {
    super.initState();
    widget.library.remember([widget.film]);
    if (widget.film.remote) {
      unawaited(load());
      unawaited(
        widget.library.catalog.home.load().then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final provider = widget.library.provider;
      if (provider == null) throw StateError('片源未启用');
      final value = await provider.detail(widget.film.id);
      if (!mounted) return;
      widget.library.remember([value.film]);
      setState(() {
        detail = value;
        final preferred = preferredPlaybackLine(
          value.lines,
          resumeCode: widget.resume?.lineCode,
        );
        lineCode = preferred?.code;
        episode = episode.clamp(
          1,
          preferred?.episodes.length ?? value.film.episodes,
        );
      });
    } catch (_) {
      if (mounted) setState(() => loadError = '无法加载真实详情，请重试。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> watch() async {
    final f = film;
    // 短剧点击观看进入竖屏信息流播放器；横屏播放器只服务长视频。
    if (f.remote && f.short) {
      final resume = widget.resume?.episode == episode ? widget.resume : null;
      await openPage(
        context,
        ShortFeed(
          library: widget.library,
          active: true,
          initialFilm: f,
          initialEpisode: episode,
          initialSeconds: resume?.seconds,
        ),
      );
      return;
    }
    // 点击立即观看直接打开播放页，将解析网络等待转移至播放页内部进行，免除等待阻塞。
    await openPage(
      context,
      ExperiencePlayer(
        film: f,
        library: widget.library,
        episode: episode,
        resume: widget.resume?.episode == episode ? widget.resume : null,
        initialSource: f.remote ? null : designSource(f),
        lineCode: lineCode,
        lines: detail?.lines ?? const [],
        autoResolve: f.remote,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = film, l = widget.library;
    final unavailable =
        l.scenario == 'media-unavailable' ||
        (!f.remote && designSource(f) == null);
    final heroHeight = (MediaQuery.sizeOf(context).height * .36).clamp(
      240.0,
      320.0,
    );
    final wide = WindowLayout.isWide(context);
    final information = <Widget>[
      if (loadError != null)
        EmptyView('详情加载失败', loadError!, action: '重试', onTap: load),
      if (detail != null && detail!.lines.isEmpty) const Text('当前片目暂无可用播放线路'),
      const Text(
        '剧情简介',
        style: TextStyle(fontSize: DS.sectionSize, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      if (loading)
        const _DetailSkeleton()
      else
        Text(
          f.synopsis,
          style: DS.body.copyWith(color: DSPalette.of(context).muted),
        ),
      if (!loading && f.episodes > 1)
        MenuRow(
          'list-video',
          '选集 · 第 $episode 集',
          subtitle: '共 ${f.episodes} 集',
          onTap: () async {
            final next = await showEpisodes(context, f, episode, shared: false);
            if (next != null && mounted) setState(() => episode = next);
          },
        ),
      if (widget.resume != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            '从${widget.resume!.shared ? '共同' : '个人'}进度 ${widget.resume!.seconds ~/ 60}:${(widget.resume!.seconds % 60).toString().padLeft(2, '0')} 继续 · 本机',
            style: TextStyle(color: DSPalette.of(context).primary),
          ),
        ),
      if (!f.remote) const PreviewLabel(),
    ];
    final recommendations = <Widget>[
      if (!loading) ...[
        const Divider(height: 16),
        const Text('你可能也喜欢', style: TextStyle(fontSize: DS.sectionSize)),
        const SizedBox(height: 16),
        if (wide)
          _wideRecommendations(f, l)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final other
                  in (f.remote ? l.catalog.home.items : films)
                      .where((v) => v.id != f.id)
                      .take(3))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: FilmPoster(
                      other,
                      editorial: true,
                      aspectRatio: .72,
                      onTap: () => openPage(
                        context,
                        DetailPage(film: other, library: l),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    ];
    // 平板顶部是正文背景，沿用主题系统条；手机大图仍使用沉浸白色图标。
    return (wide ? themeSystemBars : mediaSystemBars)(
      context,
      Scaffold(
        body: Forest(
          child: ContentWidth(
            maxWidth: 1120,
            child: Stack(
              children: [
                ScrollChrome(
                  fadeStart: wide ? 0 : heroHeight - 110,
                  fadeExtent: 64,
                  header: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        _CoverAction(
                          'arrow-left',
                          '返回',
                          () => Navigator.maybePop(context),
                        ),
                        const Spacer(),
                        _CoverAction(
                          l.favorites.contains(f.id)
                              ? 'bookmark-check'
                              : 'bookmark',
                          '收藏影片',
                          () async {
                            try {
                              await l.toggleFavorite(f);
                              if (mounted) setState(() {});
                            } catch (_) {
                              if (context.mounted) tell(context, '收藏保存失败，请重试。');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 110),
                    children: [
                      if (wide)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 72, 16, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 200,
                                child: AspectRatio(
                                  key: const Key('tablet-detail-poster'),
                                  aspectRatio: .75,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      DS.panelRadius,
                                    ),
                                    child: FilmArtwork(f, asset: f.image),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: ContentWidth(
                                  maxWidth: 720,
                                  wideInset: 0,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        f.title,
                                        style: DS.section.copyWith(
                                          fontSize: DS.posterTitleSize,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        homeMetadata(f),
                                        style: DS.smallFor(context),
                                      ),
                                      const SizedBox(height: 20),
                                      ...information,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        FilmHero(f, height: heroHeight),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DS.pageInset,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              ...information,
                              ...recommendations,
                            ],
                          ),
                        ),
                      ],
                      if (wide)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DS.pageInset,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [...recommendations],
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: (Theme.of(context).brightness == Brightness.dark
                                  ? DSPalette.of(context).panel.withValues(alpha: .75)
                                  : DSPalette.of(context).bg.withValues(alpha: .82)),
                          border: Border(
                            top: BorderSide(
                              color: (Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white.withValues(alpha: .10)
                                      : DSPalette.of(context).line.withValues(alpha: .80)),
                              width: .6,
                            ),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: ContentWidth(
                              maxWidth: 720,
                              wideInset: 0,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        shape: const StadiumBorder(),
                                        minimumSize: const Size.fromHeight(42),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        elevation: 0,
                                      ),
                                      onPressed: unavailable ? null : watch,
                                      icon: DSIcon(
                                        'play',
                                        color: DSPalette.of(context)
                                            .onPrimary,
                                        size: 16,
                                      ),
                                      label: Text(
                                        unavailable
                                            ? '片源暂不可用'
                                            : !f.remote && designSource(f) == null
                                            ? '选择视频观看'
                                            : widget.resume != null
                                            ? '继续观看'
                                            : '立即观看',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        shape: const StadiumBorder(),
                                        minimumSize: const Size.fromHeight(42),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        side: BorderSide(
                                          color: DSPalette.of(context)
                                              .outline
                                              .withValues(alpha: .35),
                                          width: 1,
                                        ),
                                      ),
                                      onPressed: unavailable || (f.remote && line == null)
                                          ? null
                                          : () => showInvite(
                                              context,
                                              film: f,
                                              library: l,
                                              episode: episode,
                                              position: widget.resume?.seconds ?? 0,
                                              lineCode: lineCode,
                                            ),
                                      child: Text(
                                        '邀请一起看',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: DSPalette.of(context).ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideRecommendations(Film current, LibraryState library) =>
      LayoutBuilder(
        builder: (context, bounds) {
          final items = (current.remote ? library.catalog.home.items : films)
              .where((film) => film.id != current.id)
              .take(12)
              .toList();
          final columns = WindowLayout.posterColumns(
            bounds.maxWidth,
            MediaQuery.textScalerOf(context),
          );
          final width = (bounds.maxWidth - 16 * (columns - 1)) / columns;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final film in items)
                SizedBox(
                  width: width,
                  child: FilmPoster(
                    film,
                    editorial: true,
                    aspectRatio: .72,
                    onTap: () => openPage(
                      context,
                      DetailPage(film: film, library: library),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

/// 媒体封面与滚动后的浅色顶栏都需要稳定对比度，视觉圆片与触控区分离。
class _CoverAction extends StatelessWidget {
  const _CoverAction(this.icon, this.label, this.onTap);
  final String icon, label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DSPalette.media.withValues(alpha: .45),
      ),
      child: Center(
        child: DSIcon(icon, size: DS.navigationIcon, color: DSPalette.onMedia),
      ),
    ),
  );
}

/// 详情加载骨架屏：按正文布局铺灰色占位块，替代线性进度条。
class _DetailSkeleton extends StatefulWidget {
  const _DetailSkeleton();

  @override
  State<_DetailSkeleton> createState() => _DetailSkeletonState();
}

class _DetailSkeletonState extends State<_DetailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = _initPulse();

  // 呼吸动画遵循系统"减少动画"设置：关闭时停在满不透明度，不闪动。
  AnimationController _initPulse() {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else {
      controller.repeat(reverse: true);
    }
    return controller;
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = DSPalette.of(context).subtle;
    Widget bar(double width, {double height = 13, double radius = 6}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return FadeTransition(
      key: const Key('detail-skeleton'),
      opacity: CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
      child: Semantics(
        label: '正在加载详情',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(double.infinity),
            const SizedBox(height: 10),
            bar(double.infinity),
            const SizedBox(height: 10),
            bar(180),
            const SizedBox(height: 24),
            Row(
              children: [
                bar(44, height: 44, radius: 22),
                const SizedBox(width: DS.panelPadding),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(120, height: 14),
                      const SizedBox(height: 8),
                      bar(80, height: 12),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 36),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: AspectRatio(
                        aspectRatio: .72,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(DS.radiusSmall),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
