import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/window_layout.dart';
import 'catalog.dart';
import 'detail_page.dart';
import '../experience/experience_player.dart';
import 'library_state.dart';
import 'posters.dart';
import 'search_page.dart';
import 'tablet_feature_card.dart';

class HomeCarousel extends StatefulWidget {
  const HomeCarousel({
    super.key,
    required this.items,
    required this.library,
    required this.active,
  });
  final List<Film> items;
  final LibraryState library;
  final bool active;
  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel>
    with WidgetsBindingObserver {
  PageController pager = PageController(viewportFraction: .8);
  Timer? timer;
  int index = 0;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    schedule();
  }

  @override
  void didUpdateWidget(covariant HomeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.map((f) => f.id).join() !=
        widget.items.map((f) => f.id).join()) {
      index = 0;
      if (pager.hasClients) pager.jumpToPage(0);
    }
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (!widget.active ||
        !TickerMode.valuesOf(context).enabled ||
        !foreground ||
        widget.items.length < 2 ||
        MediaQuery.disableAnimationsOf(context))
      return;
    timer = Timer(const Duration(seconds: 6), () {
      if (mounted &&
          pager.hasClients &&
          ModalRoute.isCurrentOf(context) != false &&
          TickerMode.valuesOf(context).enabled) {
        pager.animateToPage(
          (index + 1) % widget.items.length,
          duration: const Duration(milliseconds: 480),
          curve: DSMotion.curve,
        );
      }
      if (mounted) schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (widget.items.isEmpty) return const SizedBox.shrink();
      final palette = DSPalette.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final wide = WindowLayout.isWide(context);
      final fraction = wide && constraints.maxWidth >= 1000 ? .5 : .8;
      if (pager.viewportFraction != fraction) {
        final previous = pager;
        pager = PageController(initialPage: index, viewportFraction: fraction);
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
      final artHeight = (constraints.maxWidth * .385).clamp(122.0, 166.0);
      // 大字体将操作区纵向展开，画面与文字分区始终独立。
      final large = scaler.scale(14) > 20;
      final infoHeight = large
          ? scaler.scale(14) * 1.3 + scaler.scale(10) * 1.4 + 72
          : 56.0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: wide
                ? (scaler.scale(16) * 2.6 + scaler.scale(12) * 3 + 140).clamp(
                    264.0,
                    400.0,
                  )
                : artHeight + infoHeight,
            child: Listener(
              onPointerDown: (_) => timer?.cancel(),
              // 交互时暂缓，松手后重新计时，不再永久停止自动轮播。
              onPointerUp: (_) => schedule(),
              onPointerCancel: (_) => schedule(),
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: PageView.builder(
                  key: const Key('home-carousel'),
                  controller: pager,
                  padEnds: false,
                  itemCount: widget.items.length,
                  onPageChanged: (i) {
                    setState(() => index = i);
                    schedule();
                  },
                  itemBuilder: (context, i) {
                    final film = widget.items[i];
                    void detail() => openPage(
                      context,
                      DetailPage(film: film, library: widget.library),
                    );
                    if (wide) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: TabletFeatureCard(
                          film: film,
                          onDetail: detail,
                          onPlay: () =>
                              openCatalogPlayer(context, film, widget.library),
                        ),
                      );
                    }
                    final title = InkWell(
                      key: Key('home-detail-${film.id}'),
                      onTap: detail,
                      child: Semantics(
                        button: true,
                        label: '${film.title}，详情',
                        excludeSemantics: true,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      film.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.3,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  DSIcon(
                                    'chevron-right',
                                    size: 13,
                                    color: palette.muted,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                homeMetadata(film),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DS
                                    .smallFor(context)
                                    .copyWith(fontSize: 10, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    final action = HomePlayAction(
                      label: '选择视频',
                      compact: true,
                      onTap: () =>
                          openCatalogPlayer(context, film, widget.library),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(right: 9),
                      child: Semantics(
                        label:
                            '推荐 ${i + 1}/${widget.items.length}：${film.title}',
                        child: Material(
                          key: Key('home-slide-${film.id}'),
                          color: palette.panel,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              SizedBox(
                                key: Key('home-art-${film.id}'),
                                height: artHeight,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FilmArtwork(
                                      film,
                                      asset: homeArtwork(film, landscape: true),
                                      cacheWidth: null,
                                      excludeFromSemantics: true,
                                    ),
                                    Positioned(
                                      left: 11,
                                      top: 11,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: palette.panel,
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            '精选',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: palette.ink,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 4,
                                  ),
                                  child: large
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            title,
                                            const Spacer(),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: action,
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            Expanded(child: title),
                                            const SizedBox(width: 6),
                                            action,
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// 图标视觉尺寸与点击区域分开，续播和选择视频共用一致的圆形动作。
class HomePlayAction extends StatelessWidget {
  const HomePlayAction({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 24 : 34,
                height: compact ? 24 : 34,
                decoration: BoxDecoration(
                  color: p.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: compact ? 17 : 25,
                  color: p.onPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 9 : 12,
                  height: 1.3,
                  color: p.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.library});
  final LibraryState library;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final catalog = {for (final film in library.knownFilms) film.id: film};
      final items = [
        for (final entry in library.history)
          if (catalog[entry.filmId] case final film?) (entry, film),
      ];
      if (items.isEmpty) return const SizedBox.shrink();
      final text = MediaQuery.textScalerOf(context);
      // 横向分页需要明确高度；额外留出字体回退的取整空间，避免 Web 中文字体溢出。
      final height =
          (text.scale(10) * 1.4).ceilToDouble() +
          (text.scale(15) * 1.4).ceilToDouble() +
          (text.scale(DS.captionSize) * 1.5).ceilToDouble() +
          18;
      return SizedBox(
        height: height < 68 ? 68 : height,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: PageView.builder(
            key: PageStorageKey('continue-watching-${library.accountId}'),
            itemCount: items.length,
            itemBuilder: (context, i) => _ContinueItem(
              key: ValueKey(items[i].$1.key),
              library: library,
              entry: items[i].$1,
              film: items[i].$2,
              label: items.length > 1
                  ? '继续观看 · ${i + 1}/${items.length}'
                  : '继续观看',
            ),
          ),
        ),
      );
    },
  );
}

class _ContinueItem extends StatelessWidget {
  const _ContinueItem({
    super.key,
    required this.library,
    required this.entry,
    required this.film,
    required this.label,
  });
  final LibraryState library;
  final WatchEntry entry;
  final Film film;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openPage(
        context,
        film.remote
            ? DetailPage(film: film, library: library, resume: entry)
            : ExperiencePlayer(
                film: film,
                library: library,
                resume: entry,
                episode: entry.episode,
              ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: FilmArtwork(
              film,
              asset: homeArtwork(film),
              width: 54,
              height: 68,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: DS
                      .smallFor(context)
                      .copyWith(fontSize: 10, height: 1.4),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  film.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${film.episodes > 1 ? '第 ${entry.episode} 集 · ' : ''}已看 ${entry.seconds ~/ 60}:${(entry.seconds % 60).toString().padLeft(2, '0')}',
                  style: DS.smallFor(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: film.minutes > 0
                      ? (entry.seconds / (film.minutes * 60)).clamp(0, 1)
                      : 0,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(3),
                  color: DSPalette.of(context).primary,
                  backgroundColor: DSPalette.of(context).line,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          HomePlayAction(
            label: '继续',
            onTap: () => openPage(
              context,
              film.remote
                  ? DetailPage(film: film, library: library, resume: entry)
                  : ExperiencePlayer(
                      film: film,
                      library: library,
                      resume: entry,
                      episode: entry.episode,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogSections extends StatelessWidget {
  const CatalogSections({super.key, required this.library, this.kind});
  final LibraryState library;
  final String? kind;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final category
          in kind == null ? ['电影', '电视剧', '动漫', '短剧'] : [kind!]) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
          child: SectionHeading(
            category,
            subtitle: const {
              '电影': '值得一看的故事',
              '电视剧': '慢慢看完',
              '动漫': '另一种想象',
              '短剧': '此刻入戏',
            }[category],
            action: ArrowAction(
              '全部',
              onTap: () => openPage(
                context,
                SearchPage(library: library, initialKind: category),
              ),
            ),
          ),
        ),
        SizedBox(
          height:
              WindowLayout.shelfWidth(context) / (108 / 140) +
              16 +
              MediaQuery.textScalerOf(context)
                      .scale(WindowLayout.isWide(context) ? 14 : 12) *
                  1.3 +
              MediaQuery.textScalerOf(context)
                      .scale(WindowLayout.isWide(context) ? 12 : 10) *
                  1.5,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: library.catalog.category(category).items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, i) {
              final film = library.catalog.category(category).items[i];
              return SizedBox(
                width: WindowLayout.shelfWidth(context),
                child: FilmPoster(
                  film,
                  aspectRatio: 108 / 140,
                  editorial: true,
                  onTap: () => openPage(
                    context,
                    DetailPage(film: film, library: library),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ],
  );
}
