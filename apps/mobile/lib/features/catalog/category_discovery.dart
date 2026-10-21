import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import 'catalog.dart';
import 'detail_page.dart';
import 'library_state.dart';
import 'posters.dart';

/// 每个分类独立保留条件和片单顺序；数据仍由现有片库提供。
class CatalogSelection {
  String? genre;
  int length = 0, sort = 0, pickOffset = 0, limit = pageSize;
  bool expanded = false;
  static const pageSize = 12;
  bool get filtered => genre != null || length != 0 || sort != 0;

  List<String> lengthLabels(String kind) => switch (kind) {
    '电影' => ['全部片长', '100 分钟以内', '101–120 分钟', '120 分钟以上'],
    '短剧' => ['全部时长', '每集 2 分钟以内', '每集 3 分钟以上'],
    _ => ['全部集数', '12 集以内', '13 集以上'],
  };

  List<Film> results(Iterable<Film> source, String kind) {
    final unique = <String, Film>{};
    for (final film in source) {
      if (film.kind == kind) unique.putIfAbsent(film.id, () => film);
    }
    final result = unique.values.where((film) {
      if (genre != null && genre != film.genre) return false;
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
  });
  final LibraryState library;
  final String kind;
  final CatalogSelection selection;
  final Widget header;
  final List<Film> items;

  @override
  State<CatalogDiscovery> createState() => _CatalogDiscoveryState();
}

class _CatalogDiscoveryState extends State<CatalogDiscovery> {
  final scroll = ScrollController();
  final gridHeadingKey = GlobalKey();
  late List<Film> all, result;
  CatalogSelection get selection => widget.selection;

  @override
  void initState() {
    super.initState();
    updateResults();
    scroll.addListener(loadMore);
  }

  @override
  void didUpdateWidget(covariant CatalogDiscovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items ||
        oldWidget.kind != widget.kind ||
        oldWidget.selection != widget.selection)
      updateResults();
  }

  void updateResults() {
    all = CatalogSelection().results(widget.items, widget.kind);
    result = selection.results(all, widget.kind);
  }

  void changeFilter(VoidCallback change) {
    setState(() {
      change();
      selection.limit = CatalogSelection.pageSize;
      updateResults();
    });
  }

  void loadMore() {
    if (!scroll.hasClients ||
        scroll.position.extentAfter > 400 ||
        selection.limit >= result.length)
      return;
    // 本地有限片库同步追加；不制造网络等待，也不重复片目伪装无限列表。
    setState(
      () => selection.limit = (selection.limit + CatalogSelection.pageSize)
          .clamp(0, result.length),
    );
  }

  @override
  void dispose() {
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
    return CustomScrollView(
      key: PageStorageKey('catalog-${widget.kind}'),
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(child: widget.header),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: DS.space4),
                _filterCard(),
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
                      '${result.length} 部',
                      style: DS.smallFor(context),
                    ),
                  ),
                ),
                if (result.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: DS.space24),
                    child: Column(
                      children: [
                        Text('暂时没有符合条件的片目', style: DS.smallFor(context)),
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
                child: Text(
                  selection.limit >= result.length ? '已经到底了' : '继续上滑，查看更多',
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
    );
  }

  Widget _filterCard() {
    final p = DSPalette.of(context);
    return Material(
      color: p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DS.radiusMedium),
        side: BorderSide(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _filterBar(),
          if (MediaQuery.disableAnimationsOf(context))
            if (selection.expanded) _filterPanel() else const SizedBox()
          else
            AnimatedSize(
              alignment: Alignment.topCenter,
              duration: DSMotion.duration(context),
              curve: DSMotion.curve,
              child: selection.expanded ? _filterPanel() : const SizedBox(),
            ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final p = DSPalette.of(context);
    final labels = selection.lengthLabels(widget.kind);
    final summary = [
      selection.genre ?? '全部题材',
      labels[selection.length],
      if (selection.sort != 0)
        selection.sort == 1
            ? '片名排序'
            : widget.kind == '电影' || widget.kind == '短剧'
            ? '时长优先'
            : '集数优先',
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: Semantics(
            expanded: selection.expanded,
            child: InkWell(
              key: const Key('category-filter-toggle'),
              onTap: () =>
                  setState(() => selection.expanded = !selection.expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: DS.touchTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DS.space12,
                    vertical: DS.space8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DS.label.copyWith(
                            color: selection.filtered ? p.onTint : p.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: DS.space8),
                      Text(
                        selection.expanded ? '收起' : '筛选',
                        style: DS.label.copyWith(color: p.muted),
                      ),
                      const SizedBox(width: DS.space4),
                      AnimatedRotation(
                        turns: selection.expanded ? .5 : 0,
                        duration: DSMotion.duration(context, DSMotion.fast),
                        curve: DSMotion.curve,
                        child: DSIcon(
                          'chevron-down',
                          size: DS.chevronSize,
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (selection.filtered)
          IconButton(
            key: const Key('category-reset'),
            tooltip: '重置筛选',
            onPressed: () => changeFilter(selection.reset),
            icon: DSIcon('refresh-cw', size: DS.iconSmall, color: p.primary),
          ),
      ],
    );
  }

  Widget _filterPanel() {
    final genres = all.map((f) => f.genre).toSet();
    final lengths = selection.lengthLabels(widget.kind);
    return Padding(
      key: const Key('category-filter-panel'),
      padding: const EdgeInsets.symmetric(
        horizontal: DS.space8,
        vertical: DS.space4,
      ),
      child: Column(
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
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 3),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DS.space12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected ? p.tint : p.bg,
            borderRadius: BorderRadius.circular(DS.radiusSmall),
            border: Border.all(
              color: selected ? p.primary : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: DS.label.copyWith(color: selected ? p.onTint : p.muted),
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
                child: Image.asset(
                  homeArtwork(film),
                  width: 44,
                  height: 64,
                  fit: BoxFit.cover,
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
                child: Image.asset(
                  homeArtwork(film),
                  fit: BoxFit.cover,
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
