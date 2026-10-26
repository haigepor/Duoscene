import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import 'catalog.dart';
import 'detail_page.dart';
import 'library_state.dart';
import 'posters.dart';
import 'media_provider.dart';

/// 每个分类独立保留条件和片单顺序；数据仍由现有片库提供。
class CatalogSelection {
  String? genre;
  String? area, language, year;
  int length = 0, sort = 0, pickOffset = 0, limit = pageSize;
  static const pageSize = 12;
  bool get filtered =>
      genre != null ||
      area != null ||
      language != null ||
      year != null ||
      length != 0 ||
      sort != 0;
  CatalogFilter get query =>
      CatalogFilter(genre: genre, area: area, language: language, year: year);

  List<String> lengthLabels(String kind) => switch (kind) {
    '电影' => ['全部片长', '100 分钟以内', '101–120 分钟', '120 分钟以上'],
    '短剧' => ['全部时长', '每集 2 分钟以内', '每集 3 分钟以上'],
    _ => ['全部集数', '12 集以内', '13 集以上'],
  };

  List<Film> results(
    Iterable<Film> source,
    String kind, {
    bool serverFiltered = false,
  }) {
    final unique = <String, Film>{};
    for (final film in source) {
      if (film.kind == kind) unique.putIfAbsent(film.id, () => film);
    }
    final result = unique.values.where((film) {
      if (serverFiltered) return true;
      if (genre != null && genre != film.genre) return false;
      if (length != 0 &&
          film.remote &&
          film.minutes == 0 &&
          (kind == '电影' || kind == '短剧'))
        return false;
      return switch (length) {
        0 => true,
        1 =>
          kind == '电影'
              ? film.minutes <= 100
              : kind == '短剧'
              ? film.minutes <= 2
              : film.episodes <= 12,
        2 =>
          kind == '电影'
              ? film.minutes > 100 && film.minutes <= 120
              : kind == '短剧'
              ? film.minutes >= 3
              : film.episodes > 12,
        _ => film.minutes > 120,
      };
    }).toList();
    if (sort != 0) {
      result.sort((a, b) {
        final order = sort == 1
            ? a.title.compareTo(b.title)
            : (kind == '电影' || kind == '短剧')
            ? a.minutes.compareTo(b.minutes)
            : a.episodes.compareTo(b.episodes);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    }
    return result;
  }

  void reset() {
    genre = null;
    area = language = year = null;
    length = sort = 0;
    limit = pageSize;
  }
}

/// 分类页使用一个主 Sliver 滚动，三列片库只构建视口附近的卡片。
class CatalogDiscovery extends StatefulWidget {
  const CatalogDiscovery({
    super.key,
    required this.library,
    required this.kind,
    required this.selection,
    required this.header,
    this.items = films,
    this.loading = false,
    this.hasMore = false,
    this.error,
    this.onLoadMore,
    this.onRetry,
    this.remoteFilters = false,
    this.filterOptions = const {},
    this.navigationError,
    this.onFilter,
    this.onRetryFilters,
  });
  final LibraryState library;
  final String kind;
  final CatalogSelection selection;
  final Widget header;
  final List<Film> items;
  final bool loading, hasMore;
  final String? error;
  final VoidCallback? onLoadMore, onRetry;
  final bool remoteFilters;
  final Map<String, List<String>> filterOptions;
  final String? navigationError;
  final ValueChanged<CatalogFilter>? onFilter;
  final VoidCallback? onRetryFilters;

  @override
  State<CatalogDiscovery> createState() => _CatalogDiscoveryState();
}

class _CatalogDiscoveryState extends State<CatalogDiscovery> {
  final scroll = ScrollController();
  final gridHeadingKey = GlobalKey();
  late final VoidCallback unbindScrollTop;
  late List<Film> all, result;

  /// 远程触底加载的自动重试：上游常闪断，失败不能死等用户手动点重试。
  Timer? retryTimer;
  int retryDelay = 2;
  CatalogSelection get selection => widget.selection;

  @override
  void initState() {
    super.initState();
    updateResults();
    scroll.addListener(loadMore);
    unbindScrollTop = bindScrollTop(widget.library.scrollTopRequest, scroll);
  }

  @override
  void didUpdateWidget(covariant CatalogDiscovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items ||
        oldWidget.kind != widget.kind ||
        oldWidget.selection != widget.selection)
      updateResults();
    if (oldWidget.error != widget.error) {
      if (widget.error != null) {
        scheduleRetry();
      } else {
        retryDelay = 2;
      }
    }
    if (oldWidget.items != widget.items) {
      // 停在底部等新页时没有滚动事件：新数据到达后直接续渲染/续拉取。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadMore();
      });
    }
  }

  void updateResults() {
    all = CatalogSelection().results(widget.items, widget.kind);
    result = selection.results(
      all,
      widget.kind,
      serverFiltered: widget.remoteFilters,
    );
  }

  void changeFilter(VoidCallback change) {
    final before = selection.query.parameters.toString();
    setState(() {
      change();
      selection.limit = CatalogSelection.pageSize;
      updateResults();
    });
    if (widget.remoteFilters && before != selection.query.parameters.toString())
      widget.onFilter?.call(selection.query);
  }

  void scheduleRetry() {
    retryTimer?.cancel();
    retryTimer = Timer(Duration(seconds: retryDelay), () {
      retryDelay = (retryDelay * 2).clamp(2, 12);
      if (mounted) loadMore();
    });
  }

  void loadMore() {
    if (!scroll.hasClients || scroll.position.extentAfter > 400) return;
    if (selection.limit >= result.length) {
      // 加载失败不再由 error 永久拦停：滚动、退避定时器、新页到达都会重试。
      if (!widget.loading && widget.hasMore) widget.onLoadMore?.call();
      return;
    }
    // 本地有限片库同步追加；limit 已到 result.length 后不再 setState，
    // 避免触底区每个滚动 tick 都整页重建。
    final next = (selection.limit + CatalogSelection.pageSize).clamp(
      0,
      result.length,
    );
    if (next == selection.limit) return;
    setState(() => selection.limit = next);
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    unbindScrollTop();
    scroll.removeListener(loadMore);
    scroll.dispose();
    super.dispose();
  }

  void openFilm(Film film) =>
      openPage(context, DetailPage(film: film, library: widget.library));

  @override
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    final large = MediaQuery.textScalerOf(context).scale(14) > 22;
    final titles = switch (widget.kind) {
      '电影' => ('值得一看', '随心放映', '全部电影'),
      '电视剧' => ('值得追的故事', '慢慢看完', '全部剧集'),
      '动漫' => ('打开想象', '另一种世界', '全部动漫'),
      _ => ('短篇片单', '片刻入戏', '全部短剧'),
    };
    return RefreshIndicator(
      color: p.primary,
      onRefresh: () async => widget.onRetry?.call(),
      child: CustomScrollView(
        key: PageStorageKey('catalog-${widget.kind}'),
        controller: scroll,
        // 筛选结果很短时也要能下拉刷新。
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: widget.header),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: DS.space4),
                  _filterPanel(),
                  if (widget.error != null)
                    EmptyView(
                      '暂时无法加载片库',
                      widget.error!,
                      action: '重试',
                      onTap: widget.onRetry,
                    ),
                  if (!selection.filtered && all.isNotEmpty) ...[
                    _DiscoveryCollection(
                      key: const Key('category-picks'),
                      title: titles.$1,
                      items: all,
                      selection: selection,
                      large: large,
                      onOpen: openFilm,
                    ),
                    const SizedBox(height: DS.space8),
                    SectionHeading(
                      titles.$2,
                      action: Semantics(
                        label: '查看全部${widget.kind}',
                        child: ArrowAction(
                          '',
                          onTap: () {
                            final target = gridHeadingKey.currentContext;
                            if (target != null)
                              Scrollable.ensureVisible(
                                target,
                                duration: DSMotion.duration(context),
                                alignment: .12,
                              );
                          },
                        ),
                      ),
                    ),
                    _posterShelf(all, large),
                    const SizedBox(height: DS.space8),
                  ],
                  Padding(
                    key: gridHeadingKey,
                    padding: const EdgeInsets.symmetric(vertical: DS.space12),
                    child: SectionHeading(
                      selection.filtered ? '筛选结果' : titles.$3,
                      action: Text(
                        widget.remoteFilters
                            ? '已载 ${result.length} 部'
                            : '${result.length} 部',
                        style: DS.smallFor(context),
                      ),
                    ),
                  ),
                  if (result.isEmpty && widget.loading && widget.error == null)
                    _GridSkeleton(large: large)
                  else if (result.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: DS.space24),
                      child: Column(
                        children: [
                          Text(
                            widget.hasMore ? '本页暂无片目，可继续加载' : '暂时没有符合条件的片目',
                            style: DS.smallFor(context),
                          ),
                          if (widget.hasMore)
                            TextButton(
                              onPressed: widget.onLoadMore,
                              child: const Text('加载下一页'),
                            ),
                          TextButton(
                            onPressed: () => changeFilter(selection.reset),
                            child: const Text('重置筛选'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = large ? 2 : 3;
                final width =
                    (constraints.crossAxisExtent - DS.space8 * (columns - 1)) /
                    columns;
                final text = MediaQuery.textScalerOf(context);
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: DS.space8,
                    mainAxisSpacing: DS.space16,
                    // 中文回退字体在原生设备会向上取整，保留少量行高余量。
                    mainAxisExtent:
                        width / .75 +
                        DS.space8 +
                        (text.scale(14) * 1.4).ceilToDouble() +
                        DS.space4 +
                        (text.scale(12) * 1.5).ceilToDouble() +
                        DS.space4,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final film = result[index];
                    return _DiscoveryPoster(
                      key: Key('category-film-${film.id}'),
                      film: film,
                      onTap: () => openFilm(film),
                    );
                  }, childCount: result.length.clamp(0, selection.limit)),
                );
              },
            ),
          ),
          if (result.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: DS.space24),
                child: Center(
                  child:
                      widget.error != null && widget.hasMore && !widget.loading
                      ? TextButton(
                          key: const Key('category-load-retry'),
                          onPressed: widget.onLoadMore,
                          child: const Text('下一页加载失败，点击重试'),
                        )
                      : Text(
                          widget.loading
                              ? '正在加载…'
                              : selection.limit >= result.length &&
                                    !widget.hasMore
                              ? '已经到底了'
                              : '继续上滑，查看更多',
                          key: const Key('category-page-status'),
                          style: DS.smallFor(context).copyWith(color: p.muted),
                        ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }

  // 筛选区常驻展开（不再折叠）：行式全量选项铺开，选中值以主题色高亮。
  Widget _filterPanel() {
    if (widget.remoteFilters) return _remoteFilterPanel();
    final genres = all.map((f) => f.genre).toSet();
    final lengths = selection.lengthLabels(widget.kind);
    return Padding(
      key: const Key('category-filter-panel'),
      padding: const EdgeInsets.symmetric(vertical: DS.space4),
      child: Column(
        spacing: DS.space4,
        children: [
          _filterRow('题材', [
            _choice(
              '全部',
              'category-genre-all',
              selection.genre == null,
              () => changeFilter(() => selection.genre = null),
            ),
            for (final genre in genres)
              _choice(
                genre,
                'category-genre-$genre',
                selection.genre == genre,
                () => changeFilter(() => selection.genre = genre),
              ),
          ]),
          _filterRow(
            widget.kind == '电影'
                ? '片长'
                : widget.kind == '短剧'
                ? '时长'
                : '集数',
            [
              for (var i = 0; i < lengths.length; i++)
                _choice(
                  i == 0 ? '全部' : lengths[i],
                  'category-length-$i',
                  selection.length == i,
                  () => changeFilter(() => selection.length = i),
                ),
            ],
          ),
          _filterRow('排序', [
            for (var i = 0; i < 3; i++)
              _choice(
                [
                  '默认',
                  '片名',
                  widget.kind == '电影' || widget.kind == '短剧' ? '时长' : '集数',
                ][i],
                'category-sort-$i',
                selection.sort == i,
                () => changeFilter(() => selection.sort = i),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _remoteFilterPanel() => Padding(
    key: const Key('category-filter-panel'),
    padding: const EdgeInsets.symmetric(vertical: DS.space4),
    child: Column(
      spacing: DS.space4,
      children: [
        if (widget.navigationError != null)
          TextButton(
            onPressed: widget.onRetryFilters,
            child: Text('${widget.navigationError}，点击重试'),
          ),
        for (final field in [
          ('class', '题材', selection.genre),
          ('area', '地区', selection.area),
          ('year', '年份', selection.year),
          ('lang', '语言', selection.language),
        ])
          _filterRow(field.$2, [
            for (final value in <String?>[
              null,
              ...?widget.filterOptions[field.$1],
            ])
              _choice(
                value ?? '全部',
                'category-${field.$1}-${value ?? 'all'}',
                field.$3 == value,
                () => changeFilter(() {
                  switch (field.$1) {
                    case 'class':
                      selection.genre = value;
                    case 'area':
                      selection.area = value;
                    case 'year':
                      selection.year = value;
                    case 'lang':
                      selection.language = value;
                  }
                }),
              ),
          ]),
        _filterRow('排序', [
          for (var index = 0; index < 2; index++)
            _choice(
              ['源站默认', '本页片名'][index],
              'category-sort-$index',
              selection.sort == index,
              () => changeFilter(() => selection.sort = index),
            ),
        ]),
      ],
    ),
  );

  Widget _filterRow(String title, List<Widget> choices) => Row(
    children: [
      Padding(
        padding: const EdgeInsets.only(right: DS.space8),
        child: Text(title, style: DS.smallFor(context)),
      ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: choices),
        ),
      ),
    ],
  );

  Widget _choice(String label, String key, bool selected, VoidCallback onTap) {
    final p = DSPalette.of(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        key: Key(key),
        onPressed: onTap,
        style: TextButton.styleFrom(
          // 横向滚动的筛选条：加宽命中区提升点按精度，纵向只小幅上调。
          minimumSize: const Size(52, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(
          label,
          style: DS.label.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? p.primary : p.ink,
          ),
        ),
      ),
    );
  }

  Widget _posterShelf(List<Film> items, bool large) {
    final width = large ? 144.0 : 104.0;
    final text = MediaQuery.textScalerOf(context);
    return SizedBox(
      height:
          width / .75 +
          DS.space8 +
          (text.scale(14) * 1.4).ceilToDouble() +
          DS.space4 +
          (text.scale(12) * 1.5).ceilToDouble() +
          DS.space4,
      child: ListView.separated(
        key: PageStorageKey('category-shelf-${widget.kind}'),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: DS.space8),
        itemBuilder: (context, index) => SizedBox(
          width: width,
          child: _DiscoveryPoster(
            film: items[index],
            onTap: () => openFilm(items[index]),
          ),
        ),
      ),
    );
  }
}

/// 换组仅重建这一块，长列表与主滚动位置不参与过渡。
class _DiscoveryCollection extends StatefulWidget {
  const _DiscoveryCollection({
    super.key,
    required this.title,
    required this.items,
    required this.selection,
    required this.large,
    required this.onOpen,
  });
  final String title;
  final List<Film> items;
  final CatalogSelection selection;
  final bool large;
  final ValueChanged<Film> onOpen;
  @override
  State<_DiscoveryCollection> createState() => _DiscoveryCollectionState();
}

class _DiscoveryCollectionState extends State<_DiscoveryCollection> {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeading(
        widget.title,
        action: widget.items.length > 1
            ? ArrowAction(
                '换一组',
                key: const Key('category-refresh-picks'),
                onTap: () => setState(() {
                  widget.selection.pickOffset =
                      (widget.selection.pickOffset + 1) % widget.items.length;
                }),
              )
            : const SizedBox(height: DS.touchTarget),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = widget.large || constraints.maxWidth < 280 ? 1 : 2;
          final width =
              (constraints.maxWidth - DS.space8 * (columns - 1)) / columns;
          final picks = [
            for (var i = 0; i < widget.items.length.clamp(0, 4); i++)
              widget.items[(i + widget.selection.pickOffset) %
                  widget.items.length],
          ];
          return AnimatedSwitcher(
            duration: DSMotion.duration(context),
            switchInCurve: DSMotion.curve,
            child: Wrap(
              key: ValueKey(widget.selection.pickOffset),
              spacing: DS.space8,
              runSpacing: DS.space8,
              children: [
                for (final film in picks)
                  SizedBox(
                    key: ValueKey('pick-${film.id}'),
                    width: width,
                    child: _CompactFilm(
                      film: film,
                      onTap: () => widget.onOpen(film),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ],
  );
}

class _CompactFilm extends StatelessWidget {
  const _CompactFilm({required this.film, required this.onTap});
  final Film film;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    return Material(
      color: p.panel,
      borderRadius: BorderRadius.circular(DS.radiusSmall),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(DS.space8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: FilmArtwork(
                  film,
                  asset: homeArtwork(film),
                  width: 44,
                  height: 64,
                  cacheWidth: (44 * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                ),
              ),
              const SizedBox(width: DS.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      film.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DS.title.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: DS.space4),
                    Text(
                      film.genre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DS.smallFor(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryPoster extends StatelessWidget {
  const _DiscoveryPoster({super.key, required this.film, required this.onTap});
  final Film film;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${film.title}，${homeMetadata(film)}',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DS.radiusSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: .75,
            child: LayoutBuilder(
              builder: (context, constraints) => ClipRRect(
                borderRadius: BorderRadius.circular(DS.radiusSmall),
                child: FilmArtwork(
                  film,
                  asset: homeArtwork(film),
                  cacheWidth:
                      (constraints.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                ),
              ),
            ),
          ),
          const SizedBox(height: DS.space8),
          Text(
            film.title,
            style: DS.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: DS.space4),
          Text(
            homeMetadata(film),
            style: DS.smallFor(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

// 片库加载骨架：占位网格与真实网格同构（列数、间距、海报比例一致）。
class _GridSkeleton extends StatefulWidget {
  const _GridSkeleton({required this.large});

  final bool large;

  @override
  State<_GridSkeleton> createState() => _GridSkeletonState();
}

class _GridSkeletonState extends State<_GridSkeleton>
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
    Widget bone(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    Widget card(double width) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: width,
          height: width / .75,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DS.radiusSmall),
          ),
        ),
        const SizedBox(height: DS.space8),
        bone(width * .72, 13),
        const SizedBox(height: DS.space4),
        bone(width * .45, 12),
      ],
    );

    return FadeTransition(
      key: const Key('catalog-skeleton'),
      opacity: CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
      child: Semantics(
        label: '正在加载片库',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = widget.large ? 2 : 3;
            final width =
                (constraints.maxWidth - DS.space8 * (columns - 1)) / columns;
            return Wrap(
              spacing: DS.space8,
              runSpacing: DS.space16,
              children: [for (var i = 0; i < columns * 2; i++) card(width)],
            );
          },
        ),
      ),
    );
  }
}
