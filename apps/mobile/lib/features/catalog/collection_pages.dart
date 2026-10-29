import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/window_layout.dart';
import 'search_page.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'posters.dart';
import 'detail_page.dart';
import '../experience/experience_player.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.library,
    required this.onBrowse,
    this.initialFilter = 0,
    this.sharedScope,
    this.secondary = false,
  });
  final LibraryState library;
  final VoidCallback onBrowse;
  final int initialFilter;
  final bool? sharedScope;
  final bool secondary;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late int filter = widget.initialFilter;
  bool manage = false;
  bool deleting = false;
  final selected = <String>{};
  final historyScroll = ScrollController();
  VoidCallback? unbindScrollTop;

  @override
  void initState() {
    super.initState();
    // 只有主壳层里的“记录”页响应双击回顶；好友记录等二级页不抢信号。
    if (!widget.secondary) {
      unbindScrollTop = bindScrollTop(
        widget.library.scrollTopRequest,
        historyScroll,
      );
    }
  }

  @override
  void dispose() {
    unbindScrollTop?.call();
    historyScroll.dispose();
    super.dispose();
  }

  Future<void> removeSelected() async {
    if (deleting || selected.isEmpty) return;
    if (!await confirm(context, '删除本机记录？', '只删除所选记录，不影响好友和其他设备。', action: '删除'))
      return;
    setState(() => deleting = true);
    try {
      await widget.library.removeHistory(selected.toSet());
      if (mounted) setState(selected.clear);
    } catch (_) {
      if (mounted) tell(context, '记录保存失败，请重试。');
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.library;
    final entries = l.scenario == 'history-empty'
        ? <WatchEntry>[]
        : l.history.where((e) {
            if (widget.sharedScope != null && e.shared != widget.sharedScope)
              return false;
            final f = l.filmById(e.filmId);
            return filter == 0 ||
                filter == 1 && !f.short ||
                filter == 2 && f.short ||
                filter == 3 && e.shared;
          }).toList();
    final p = DSPalette.of(context);
    final content = _CollectionLayout(
      back: widget.secondary,
      title: widget.secondary
          ? widget.sharedScope == true
                ? '共同观看进度'
                : '个人观看进度'
          : '观看记录',
      introduction: '故事停在哪里，下次就从哪里开始。',
      action: TextButton(
        onPressed: deleting || l.history.isEmpty
            ? null
            : () => setState(() {
                manage = !manage;
                selected.clear();
              }),
        child: Text(manage ? '取消' : '管理'),
      ),
      filters: _CollectionFilters(
        labels: const ['全部', '影视', '短剧', '一起看'],
        index: filter,
        onChanged: (i) {
          if (deleting || i == filter) return;
          setState(() {
            filter = i;
            selected.clear();
          });
        },
      ),
      bottom: !manage
          ? null
          : FilledButton(
              onPressed: deleting || selected.isEmpty ? null : removeSelected,
              child: Text(deleting ? '正在删除…' : '删除所选 ${selected.length} 条'),
            ),
      child: entries.isEmpty
          ? _CollectionEmpty(
              key: const Key('history-empty'),
              title: l.history.isNotEmpty && filter != 0
                  ? '这个分类还没有记录'
                  : '还没有观看记录',
              description: l.history.isNotEmpty && filter != 0
                  ? '换个分类看看，或发现新的故事。'
                  : '看过的故事，会在这里等你。',
              onBrowse: widget.onBrowse,
            )
          : ListView.builder(
              key: const PageStorageKey('history'),
              controller: historyScroll,
              padding: EdgeInsets.fromLTRB(
                18,
                22,
                18,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: entries.length + 2, // 标题行 + 记录行 + 隐私说明
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Text('最近观看', style: DS.label.copyWith(color: p.muted)),
                        const Spacer(),
                        Text(
                          '${entries.length} 条',
                          style: DS.smallFor(context).copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  );
                }
                if (i <= entries.length) return _historyRow(entries[i - 1]);
                return const Column(
                  children: [SizedBox(height: 20), _CollectionPrivacy()],
                );
              },
            ),
    );
    return widget.secondary
        ? Scaffold(
            body: Forest(
              child: SafeArea(
                bottom: false,
                child: ContentWidth(maxWidth: 840, child: content),
              ),
            ),
          )
        : ContentWidth(maxWidth: 840, child: content);
  }

  Widget _historyRow(WatchEntry entry) {
    final film = widget.library.filmById(entry.filmId);
    final p = DSPalette.of(context);
    void toggle() => setState(() {
      if (!selected.remove(entry.key)) selected.add(entry.key);
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: p.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.line.withValues(alpha: .65), width: .7),
        ),
        child: InkWell(
          key: Key('history-row-${entry.key}'),
          borderRadius: BorderRadius.circular(14),
          onTap: deleting
              ? null
              : manage
              ? toggle
              : () => openPage(
                  context,
                  DetailPage(film: film, library: widget.library),
                ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (manage)
                  Checkbox(
                    value: selected.contains(entry.key),
                    onChanged: deleting ? null : (_) => toggle(),
                  ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FilmArtwork(
                    film,
                    asset: homeArtwork(film),
                    width: 60,
                    height: 84,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        film.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${entry.shared ? '共同观看' : '个人观看'} · 第 ${entry.episode} 集',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DS
                            .smallFor(context)
                            .copyWith(fontSize: 10.5, height: 1.4),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '已看 ${entry.seconds ~/ 60}:${(entry.seconds % 60).toString().padLeft(2, '0')}',
                        style: DS
                            .smallFor(context)
                            .copyWith(fontSize: 10.5, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: film.minutes > 0
                              ? (entry.seconds / (film.minutes * 60)).clamp(
                                  0,
                                  1,
                                )
                              : 0,
                          minHeight: 2,
                          color: p.primary,
                          backgroundColor: p.subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!manage) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    key: Key('history-resume-${entry.key}'),
                    tooltip: '继续观看${film.title}',
                    onPressed: () => openPage(
                      context,
                      film.remote
                          ? DetailPage(
                              film: film,
                              library: widget.library,
                              resume: entry,
                            )
                          : ExperiencePlayer(
                              film: film,
                              library: widget.library,
                              resume: entry,
                              episode: entry.episode,
                            ),
                    ),
                    icon: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.tint,
                      ),
                      child: Center(
                        child: DSIcon('play', size: 16, color: p.primary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 两个收藏类页面共用排版；状态和导航仍由原来的页面与 LibraryState 持有。
class _CollectionLayout extends StatelessWidget {
  const _CollectionLayout({
    required this.title,
    required this.introduction,
    required this.action,
    required this.filters,
    required this.child,
    this.back = false,
    this.bottom,
  });
  final String title, introduction;
  final Widget action, filters, child;
  final bool back;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: back ? 4 : DS.pageInset, right: 4),
          child: Row(
            children: [
              if (back)
                IconButton(
                  tooltip: '返回',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const DSIcon('arrow-left'),
                ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: back ? DS.secondaryTitleSize : DS.pageTitleSize,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
              ),
              action,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DS.pageInset,
            DS.space8,
            DS.pageInset,
            0,
          ),
          child: Text(
            introduction,
            style: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
          ),
        ),
        const SizedBox(height: DS.space4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
          child: filters,
        ),
        Expanded(child: child),
        if (bottom != null)
          SafeArea(
            top: false,
            child: Padding(padding: const EdgeInsets.all(16), child: bottom!),
          ),
      ],
    );
  }
}

class _CollectionFilters extends StatelessWidget {
  const _CollectionFilters({
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final p = DSPalette.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final minimumWidth = (scaler.scale(13) * 3 + 12) * labels.length;
      // 大字号允许横向浏览，保留完整标签和点击区域。
      final width = constraints.maxWidth < minimumWidth
          ? minimumWidth
          : constraints.maxWidth;
      final height = (scaler.scale(13) * 1.3 + 24).clamp(48.0, double.infinity);
      final itemWidth = width / labels.length;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: DSMotion.duration(context, DSMotion.navigation),
                curve: DSMotion.curve,
                start: itemWidth * index + (itemWidth - 20) / 2,
                bottom: DS.space8,
                width: 20,
                height: DS.space2,
                child: DecoratedBox(
                  key: const Key('collection-filter-indicator'),
                  decoration: BoxDecoration(
                    color: p.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: index == i,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: Size(48, height),
                            padding: const EdgeInsets.only(bottom: DS.space4),
                            foregroundColor: index == i ? p.primary : p.muted,
                            overlayColor: Colors.transparent,
                            backgroundColor: Colors.transparent,
                            splashFactory: NoSplash.splashFactory,
                          ),
                          onPressed: () => onChanged(i),
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: index == i
                                  ? FontWeight.w600
                                  : FontWeight.w500,
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
    },
  );
}

class _CollectionEmpty extends StatelessWidget {
  const _CollectionEmpty({
    super.key,
    required this.title,
    required this.description,
    required this.onBrowse,
    this.favorites = false,
  });
  final String title, description;
  final VoidCallback onBrowse;
  final bool favorites;

  @override
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottom = favorites
            ? 56.0 + MediaQuery.viewPaddingOf(context).bottom
            : 50.0 + MediaQuery.paddingOf(context).bottom;
        final height = (constraints.maxHeight - bottom).clamp(
          0.0,
          double.infinity,
        );
        // 短屏与大字号改为滚动；插图和按钮不压缩，底栏也不会覆盖说明。
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 0, 18, bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  SizedBox(height: (height * .11).clamp(24.0, 68.0)),
                  RepaintBoundary(
                    child: Opacity(
                      opacity: dark ? .85 : .65,
                      child: Image.asset(
                        '${DS.media}collection-${favorites ? 'favorites' : 'history'}-glass.webp',
                        key: Key(
                          favorites
                              ? 'favorites-illustration'
                              : 'history-illustration',
                        ),
                        width: favorites ? 300 : 270,
                        height: favorites ? 240 : 196,
                        fit: BoxFit.contain,
                        cacheWidth: 768,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  SizedBox(height: favorites ? 24 : 28),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: DS.sectionSize,
                      height: 1.4,
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.6, color: p.muted),
                  ),
                  SizedBox(height: favorites ? 20 : 14),
                  TextButton(
                    key: const Key('collection-browse'),
                    onPressed: onBrowse,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(126, 48),
                      padding: EdgeInsets.zero,
                      foregroundColor: p.onPrimary,
                      shape: const StadiumBorder(),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: p.primary.withValues(
                              alpha: dark ? .08 : .10,
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 34,
                          vertical: 11,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '去找片',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            DSIcon(
                              'chevron-right',
                              size: 16,
                              color: p.onPrimary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Spacer(),
                  _CollectionPrivacy(favorites: favorites),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CollectionPrivacy extends StatelessWidget {
  const _CollectionPrivacy({this.favorites = false});
  final bool favorites;
  @override
  Widget build(BuildContext context) {
    final color = DSPalette.of(context).muted;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DSIcon('lock-keyhole', size: DS.chevronSize, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            favorites ? '收藏仅保存在当前账户的本机' : '个人与共同进度独立保存 · 仅此设备',
            style: TextStyle(fontSize: 10, height: 1.5, color: color),
          ),
        ),
      ],
    );
  }
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, required this.library});
  final LibraryState library;
  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  int _columns(BuildContext c, double width) =>
      (width / (100 * MediaQuery.textScalerOf(c).scale(1))).floor().clamp(2, 5);
  int filter = 0;
  bool manage = false;
  bool deleting = false;
  final selected = <String>{};
  Widget favoriteCard(Film film, {double? width}) => SizedBox(
    key: Key('favorite-card-${film.id}'),
    width: width,
    child: FilmPoster(
      film,
      editorial: true,
      aspectRatio: .72,
      selected: manage ? selected.contains(film.id) : null,
      onSelect: manage
          ? () => setState(() {
              if (!selected.remove(film.id)) selected.add(film.id);
            })
          : null,
      onTap: () =>
          openPage(context, DetailPage(film: film, library: widget.library)),
    ),
  );
  Future<void> removeSelected() async {
    if (deleting || selected.isEmpty) return;
    setState(() => deleting = true);
    try {
      for (final id in selected.toList()) {
        // 已完成的项立即退出选择；失败重试不会把已删除的收藏重新加入。
        if (widget.library.favorites.contains(id)) {
          await widget.library.toggleFavorite(widget.library.filmById(id));
        } else {
          await widget.library.persist();
        }
        if (mounted) setState(() => selected.remove(id));
      }
      if (mounted) setState(() => manage = false);
    } catch (_) {
      if (mounted) tell(context, '收藏保存失败，未完成的选择已保留，请重试。');
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final library = widget.library;
      final p = DSPalette.of(context);
      final hasFavorites =
          library.scenario != 'favorites-empty' && library.favorites.isNotEmpty;
      final items = library.knownFilms
          .where(
            (film) =>
                hasFavorites &&
                library.favorites.contains(film.id) &&
                (filter == 0 ||
                    filter == 1 && !film.short ||
                    filter == 2 && film.short),
          )
          .toList();
      final content = _CollectionLayout(
        back: true,
        title: '我的收藏',
        introduction: '喜欢的故事，留到下次。',
        action: TextButton(
          onPressed: deleting || !hasFavorites
              ? null
              : () => setState(() {
                  manage = !manage;
                  selected.clear();
                }),
          style: TextButton.styleFrom(textStyle: DS.label),
          child: Text(manage ? '取消' : '管理'),
        ),
        bottom: !manage
            ? null
            : SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: deleting || selected.isEmpty
                      ? null
                      : removeSelected,
                  child: Text(deleting ? '正在移除…' : '取消收藏 ${selected.length} 项'),
                ),
              ),
        filters: _CollectionFilters(
          labels: const ['全部', '影视', '短剧'],
          index: filter,
          onChanged: (i) {
            if (deleting || i == filter) return;
            setState(() {
              filter = i;
              selected.clear();
            });
          },
        ),
        child: items.isEmpty
            ? _CollectionEmpty(
                key: const Key('favorites-empty'),
                favorites: true,
                title: hasFavorites && filter != 0
                    ? '这个分类还没有收藏'
                    : '把喜欢的故事，留到下次',
                description: hasFavorites && filter != 0
                    ? '换个分类看看，或发现喜欢的影片。'
                    : '看到喜欢的影片，点一下收藏。',
                onBrowse: () => openPage(context, SearchPage(library: library)),
              )
            : CustomScrollView(
                key: const PageStorageKey('favorites-grid'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Text('已收藏', style: DS.label.copyWith(color: p.muted)),
                          const Spacer(),
                          Text(
                            '${items.length} 部',
                            style: DS.smallFor(context).copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final wide = WindowLayout.isWide(context);
                        final columns = wide
                            ? WindowLayout.posterColumns(
                                constraints.crossAxisExtent,
                                MediaQuery.textScalerOf(context),
                              )
                            : _columns(context, constraints.crossAxisExtent);
                        final spacing = wide ? 16.0 : 12.0;
                        final width =
                            (constraints.crossAxisExtent -
                                spacing * (columns - 1)) /
                            columns;
                        if (wide) {
                          final text = MediaQuery.textScalerOf(context);
                          return SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: 18,
                                  mainAxisExtent:
                                      width / .72 +
                                      16 +
                                      (text.scale(14) * 1.3).ceil() +
                                      (text.scale(12) * 1.5).ceil(),
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => favoriteCard(items[index]),
                              childCount: items.length,
                            ),
                          );
                        }
                        return SliverToBoxAdapter(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 18,
                            children: [
                              for (final film in items)
                                favoriteCard(film, width: width),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(18, 24, 18, 32),
                    sliver: SliverToBoxAdapter(
                      child: _CollectionPrivacy(favorites: true),
                    ),
                  ),
                ],
              ),
      );
      return Scaffold(
        backgroundColor: p.bg,
        body: Forest(
          child: SafeArea(bottom: false, child: ContentWidth(child: content)),
        ),
      );
    },
  );
}
