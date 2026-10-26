import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'detail_page.dart';
import 'posters.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.library,
    this.initialQuery = '',
    this.initialKind,
    this.repository,
  });
  final LibraryState library;
  final String initialQuery;
  final String? initialKind;
  final CatalogRepository? repository;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late int kind = [
    null,
    '电影',
    '电视剧',
    '动漫',
    '短剧',
  ].indexOf(widget.initialKind).clamp(0, 4);
  late final input = TextEditingController(text: widget.initialQuery);
  late final search = SearchState(
    widget.repository ?? widget.library.provider ?? DesignCatalog(),
  );
  final scroll = ScrollController();
  Timer? debounce;
  Future<void> submit(String value) {
    debounce?.cancel();
    search.kind = kind == 0 ? null : ['全部', '电影', '电视剧', '动漫', '短剧'][kind];
    return search.search(value);
  }

  @override
  void initState() {
    super.initState();
    submit(input.text);
    scroll.addListener(() {
      if (scroll.position.extentAfter < 400)
        search.search(input.text, next: true);
    });
  }

  @override
  void dispose() {
    input.dispose();
    debounce?.cancel();
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '搜索',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const Key('search-input'),
            controller: input,
            onChanged: (value) {
              search.invalidate();
              debounce?.cancel();
              debounce = Timer(
                const Duration(milliseconds: 350),
                () => submit(value),
              );
              setState(() {});
            },
            onSubmitted: submit,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索影片、剧集',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 12, right: 8),
                child: DSIcon('search', size: 18),
              ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: input.text.isEmpty
                  ? null
                  : IconTap('x', '清空搜索', () {
                      input.clear();
                      submit('');
                      setState(() {});
                    }),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DSTabs(
            labels: const ['全部', '电影', '电视剧', '动漫', '短剧'],
            index: kind,
            onChanged: (i) {
              setState(() => kind = i);
              submit(input.text);
            },
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: search,
            builder: (context, _) {
              final results = search.results
                  .where(
                    (f) =>
                        kind == 0 ||
                        f.kind == ['全部', '电影', '电视剧', '动漫', '短剧'][kind],
                  )
                  .toList();
              // builder 化：结果可随翻页无限增长，滚动只 build 可见行。
              Widget? header; // 首行区（标题/骨架/空态）
              final rows = <Widget Function()>[]; // 结果行工厂
              if (search.loading) {
                header = const _SearchSkeleton();
              } else if (search.error != null) {
                header = EmptyView(
                  '搜索暂时不可用',
                  search.error!,
                  action: '重试',
                  onTap: () => submit(input.text),
                );
              } else if (results.isEmpty && search.hasMore) {
                header = EmptyView(
                  '当前页暂无此类内容',
                  '尚有后续结果可继续查找。',
                  icon: 'search',
                  action: '继续查找',
                  onTap: () => search.search(input.text, next: true),
                );
              } else if (results.isEmpty) {
                header = const EmptyView(
                  '没有找到相关内容',
                  '换个片名或分类试试。',
                  icon: 'search',
                );
              } else {
                header = Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${results.length} 部相关内容',
                    style: DS.smallFor(context),
                  ),
                );
                for (final f in results) {
                  rows.add(() {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => openPage(
                          context,
                          DetailPage(film: f, library: widget.library),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: FilmArtwork(
                                  f,
                                  width: 64,
                                  height: 90,
                                  cacheWidth: 192,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.title, style: DS.title),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${f.kind} · ${f.genre}',
                                      style: DS.smallFor(context),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(f.meta, style: DS.smallFor(context)),
                                  ],
                                ),
                              ),
                              DSIcon(
                                'chevron-right',
                                size: 16,
                                color: DSPalette.of(context).muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  });
                }
              }
              return RefreshIndicator(
                color: DSPalette.of(context).primary,
                onRefresh: () => submit(input.text),
                child: ListView.builder(
                  controller: scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: 1 + rows.length + 1, // 标题区 + 结果行 + 尾注
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            input.text.isEmpty ? '发现故事' : '搜索结果',
                            style: DS.section,
                          ),
                          const SizedBox(height: 12),
                          if (header != null) header,
                        ],
                      );
                    }
                    if (i <= rows.length) return rows[i - 1]();
                    return PreviewLabel(
                      text: widget.library.provider == null
                          ? '设计预览 · 虚构片目，无在线片源'
                          : '片库内容由播放源提供',
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

// 搜索加载骨架：与结果行同构（海报块 + 三行文字骨）。
class _SearchSkeleton extends StatefulWidget {
  const _SearchSkeleton();

  @override
  State<_SearchSkeleton> createState() => _SearchSkeletonState();
}

class _SearchSkeletonState extends State<_SearchSkeleton>
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
    Widget row() => Row(
      children: [
        Container(
          width: 64,
          height: 90,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: .62,
                child: bone(double.infinity, 14),
              ),
              const SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: .42,
                child: bone(double.infinity, 12),
              ),
              const SizedBox(height: 6),
              FractionallySizedBox(
                widthFactor: .3,
                child: bone(double.infinity, 12),
              ),
            ],
          ),
        ),
      ],
    );
    return FadeTransition(
      key: const Key('search-skeleton'),
      opacity: CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
      child: Semantics(
        label: '正在搜索',
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              row(),
            ],
          ],
        ),
      ),
    );
  }
}
