import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'detail_page.dart';

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
  late final search = SearchState(widget.repository ?? DesignCatalog());
  @override
  void initState() {
    super.initState();
    search.search(input.text);
  }

  @override
  void dispose() {
    input.dispose();
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
              search.search(value);
              setState(() {});
            },
            onSubmitted: search.search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索影片、剧集',
              prefixIcon: const Padding(
                padding: EdgeInsets.all(14),
                child: DSIcon('search', size: 18),
              ),
              suffixIcon: input.text.isEmpty
                  ? null
                  : IconTap('x', '清空搜索', () {
                      input.clear();
                      search.search('');
                      setState(() {});
                    }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DSTabs(
            labels: const ['全部', '电影', '电视剧', '动漫', '短剧'],
            index: kind,
            onChanged: (i) => setState(() => kind = i),
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
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(input.text.isEmpty ? '发现故事' : '搜索结果', style: DS.section),
                  const SizedBox(height: 12),
                  if (search.loading)
                    const LinearProgressIndicator(semanticsLabel: '正在搜索')
                  else if (search.error != null)
                    EmptyView(
                      '搜索暂时不可用',
                      search.error!,
                      action: '重试',
                      onTap: () => search.search(input.text),
                    )
                  else if (results.isEmpty)
                    const EmptyView('没有找到相关内容', '换个片名或分类试试。', icon: 'search')
                  else ...[
                    Text(
                      '${results.length} 部相关内容',
                      style: DS.smallFor(context),
                    ),
                    const SizedBox(height: 12),
                    for (final f in results)
                      Padding(
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
                                  child: Image.asset(
                                    f.image,
                                    width: 64,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                      ),
                  ],
                  const PreviewLabel(),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
