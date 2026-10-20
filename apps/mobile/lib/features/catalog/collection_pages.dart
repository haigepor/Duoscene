import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import '../../design/scroll_chrome.dart';
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
  });
  final LibraryState library;
  final VoidCallback onBrowse;
  final int initialFilter;
  final bool? sharedScope;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late int filter = widget.initialFilter;
  bool manage = false;
  bool deleting = false;
  final selected = <String>{};
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
            final f = films.firstWhere((f) => f.id == e.filmId);
            return filter == 0 ||
                filter == 1 && !f.short ||
                filter == 2 && f.short ||
                filter == 3 && e.shared;
          }).toList();
    return ScrollChrome(
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
        child: Row(
          children: [
            const Expanded(child: Text('观看记录', style: DS.toolbar)),
            TextButton(
              onPressed: deleting
                  ? null
                  : () => setState(() {
                      manage = !manage;
                      selected.clear();
                    }),
              child: Text(manage ? '取消' : '管理'),
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              key: const PageStorageKey('history'),
              padding: const EdgeInsets.fromLTRB(
                16,
                DS.toolbarHeight + 8,
                16,
                16,
              ),
              children: [
                Text(
                  '故事停在哪里，下次就从哪里开始。',
                  style: TextStyle(color: DSPalette.of(context).muted),
                ),
                const SizedBox(height: 12),
                DSTabs(
                  labels: const ['全部', '影视', '短剧', '一起看'],
                  index: filter,
                  pill: false,
                  onChanged: deleting
                      ? (_) {}
                      : (i) => setState(() {
                          filter = i;
                          selected.clear();
                        }),
                ),
                const SizedBox(height: 16),
                if (entries.isEmpty)
                  EmptyView(
                    '还没有观看记录',
                    '选一部喜欢的影片，开始第一段故事。',
                    icon: 'history',
                    action: '去找片',
                    onTap: widget.onBrowse,
                  )
                else ...[
                  Text(
                    '最近观看',
                    style: TextStyle(color: DSPalette.of(context).muted),
                  ),
                  const SizedBox(height: 14),
                  for (final e in entries) _historyRow(e),
                ],
                const SizedBox(height: 20),
                Text(
                  '个人进度与共同进度分别保存 · 仅本机',
                  style: DS.smallFor(context),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (manage)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: deleting || selected.isEmpty
                        ? null
                        : removeSelected,
                    child: Text(
                      deleting ? '正在删除…' : '删除所选 ${selected.length} 条',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyRow(WatchEntry e) {
    final f = films.firstWhere((f) => f.id == e.filmId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (manage)
            Checkbox(
              value: selected.contains(e.key),
              onChanged: (_) => setState(() {
                if (!selected.remove(e.key)) selected.add(e.key);
              }),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset(
              f.image,
              width: 60,
              height: 84,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.title,
                  style: const TextStyle(
                    fontSize: DS.itemTitleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  e.shared ? '共同观看 · 本机' : '个人观看 · 本机',
                  style: TextStyle(
                    fontSize: DS.captionSize,
                    color: DSPalette.of(context).primary,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '第 ${e.episode} 集 · 已看 ${e.seconds ~/ 60}:${(e.seconds % 60).toString().padLeft(2, '0')}',
                  style: DS.smallFor(context),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (e.seconds / (f.minutes * 60)).clamp(0, 1),
                  minHeight: 2,
                  color: DSPalette.of(context).primary,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => openPage(
                        context,
                        ExperiencePlayer(
                          film: f,
                          library: widget.library,
                          resume: e,
                          episode: e.episode,
                        ),
                      ),
                      child: const Text('继续观看'),
                    ),
                    OutlinedButton(
                      onPressed: () => openPage(
                        context,
                        DetailPage(film: f, library: widget.library),
                      ),
                      child: const Text('详情'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
  Future<void> removeSelected() async {
    if (deleting || selected.isEmpty) return;
    setState(() => deleting = true);
    try {
      for (final id in selected.toList()) {
        // 已完成的项立即退出选择；失败重试不会把已删除的收藏重新加入。
        if (widget.library.favorites.contains(id)) {
          await widget.library.toggleFavorite(
            films.firstWhere((f) => f.id == id),
          );
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
      final items = films
          .where(
            (f) =>
                widget.library.scenario != 'favorites-empty' &&
                widget.library.favorites.contains(f.id) &&
                (filter == 0 ||
                    filter == 1 && !f.short ||
                    filter == 2 && f.short),
          )
          .toList();
      return PageFrame(
        title: '我的收藏',
        actions: [
          TextButton(
            onPressed: deleting
                ? null
                : () => setState(() {
                    manage = !manage;
                    selected.clear();
                  }),
            child: Text(manage ? '取消' : '管理'),
          ),
        ],
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DSTabs(
              labels: const ['全部', '影视', '短剧'],
              index: filter,
              onChanged: deleting
                  ? (_) {}
                  : (i) => setState(() {
                      filter = i;
                      selected.clear();
                    }),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              '喜欢的故事，留到下次。',
              style: TextStyle(color: DSPalette.of(context).muted),
            ),
            const PreviewLabel(text: '收藏仅保存在当前账户的本机'),
            const SizedBox(height: 10),
            if (items.isEmpty)
              EmptyView(
                '把喜欢的故事，留到下次',
                '看到喜欢的影片，点一下收藏。',
                action: '去找片',
                onTap: () =>
                    openPage(context, SearchPage(library: widget.library)),
              )
            else
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 10,
                  runSpacing: 20,
                  children: [
                    for (final f in items)
                      SizedBox(
                        width:
                            (c.maxWidth -
                                10 * (_columns(context, c.maxWidth) - 1)) /
                            _columns(context, c.maxWidth),
                        child: FilmPoster(
                          f,
                          selected: manage ? selected.contains(f.id) : null,
                          onSelect: manage
                              ? () => setState(() {
                                  if (!selected.remove(f.id))
                                    selected.add(f.id);
                                })
                              : null,
                          onTap: () => openPage(
                            context,
                            DetailPage(film: f, library: widget.library),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
