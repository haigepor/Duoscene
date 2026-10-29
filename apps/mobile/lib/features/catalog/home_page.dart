import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/scroll_chrome.dart';
import '../../design/motion.dart';
import '../../core/models.dart';
import 'library_state.dart';
import 'search_page.dart';
import 'home_content.dart';
import 'category_discovery.dart';
import 'catalog_data.dart';
import '../rooms/room_form_page.dart';
import '../rooms/room_detail_page.dart';
import '../rooms/room_repository.dart';

class WatchHome extends StatefulWidget {
  const WatchHome({
    super.key,
    required this.library,
    required this.onProfile,
    this.active = true,
  });
  final LibraryState library;
  final VoidCallback onProfile;
  final bool active;
  @override
  State<WatchHome> createState() => _WatchHomeState();
}

class _WatchHomeState extends State<WatchHome> {
  int category = 0;
  final selections = <int, CatalogSelection>{};
  final categoryNavigationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.library.catalog.load();
  }

  Widget discoveryHeader() => Column(
    children: [
      const SizedBox(height: 51),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: InkWell(
          key: const Key('home-search'),
          onTap: () => openPage(
            context,
            SearchPage(
              library: widget.library,
              initialKind: category == 0
                  ? null
                  : ['推荐', '电影', '电视剧', '动漫', '短剧'][category],
            ),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: DSPalette.of(context).panel,
              border: Border.all(color: DSPalette.of(context).line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                DSIcon('search', size: 20, color: DSPalette.of(context).muted),
                const SizedBox(width: 10),
                Text(
                  '搜索影片、剧集',
                  style: TextStyle(
                    color: DSPalette.of(context).muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      categoryTabs(),
    ],
  );

  Widget categoryTabs() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final minWidth =
            (MediaQuery.textScalerOf(context).scale(14) * 3 + DS.space24) * 5;
        return SingleChildScrollView(
          // 分类内容替换时保留票签动画和横向浏览位置。
          key: categoryNavigationKey,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth < minWidth
                ? minWidth
                : constraints.maxWidth,
            child: DSTabs(
              key: const Key('home-categories'),
              labels: const ['推荐', '电影', '电视剧', '动漫', '短剧'],
              index: category,
              pill: true,
              ticket: true,
              onChanged: (i) {
                if (category != i) setState(() => category = i);
                if (i > 0) {
                  widget.library.catalog
                      .category(['推荐', '电影', '电视剧', '动漫', '短剧'][i])
                      .load();
                }
              },
            ),
          ),
        );
      },
    ),
  );

  Future<void> openRoom(bool join) async {
    if (widget.library.isGuest) {
      tell(context, '当前免登录模式暂不支持双人房间。');
      return;
    }
    final session = widget.library.session;
    if (session == null || widget.library.preview) {
      tell(context, '登录后即可创建或加入真实房间。');
      return;
    }
    final rooms = RoomRepository(session);
    final room = await Navigator.of(context).push<Room>(
      MaterialPageRoute(
        builder: (_) => RoomFormPage(rooms: rooms, join: join),
      ),
    );
    if (!mounted || room == null) return;
    await openPage(
      context,
      RoomDetailPage(initialRoom: room, rooms: rooms, userId: session.user!.id),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library.catalog,
    builder: (context, _) => content(context),
  );

  Widget content(BuildContext context) {
    final l = widget.library;
    final kind = ['推荐', '电影', '电视剧', '动漫', '短剧'][category];
    final feed = category == 0 ? l.catalog.home : l.catalog.category(kind);
    final selected = feed.items.take(4).toList();
    return ScrollChrome(
      key: ValueKey('watch-chrome-$category'),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 12, 0),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const Expanded(child: Brand(size: 23, ringsFirst: true)),
              IconButton(
                onPressed: widget.onProfile,
                tooltip: '我的账户',
                icon: CircleAvatar(
                  radius: 14,
                  backgroundColor: DSPalette.of(context).tint,
                  child: Text(
                    l.initial,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DSPalette.of(context).primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child:
          category != 0 &&
              l.scenario != 'home-loading' &&
              l.scenario != 'home-source-error'
          ? CatalogDiscovery(
              key: ValueKey(kind),
              library: l,
              kind: kind,
              selection: selections.putIfAbsent(category, CatalogSelection.new),
              header: discoveryHeader(),
              items: feed.items,
              loading: feed.loading,
              error: feed.error,
              hasMore: feed.hasMore,
              onLoadMore: () => feed.load(next: true),
              onRetry: () => feed.load(refresh: true),
              remoteFilters: l.catalog.remoteFilters,
              filterOptions:
                  l.catalog.filterOptions[categoryIds[kind]] ?? const {},
              navigationError: l.catalog.navigationError,
              onRetryFilters: l.catalog.loadFilters,
              onFilter: (filter) => l.catalog.filter(kind, filter),
            )
          : ListView(
              key: const PageStorageKey('watch-home'),
              padding: EdgeInsets.zero,
              children: [
                discoveryHeader(),
                if (l.scenario == 'home-loading' ||
                    feed.loading && feed.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Panel(
                      child: SizedBox(
                        height: 290,
                        child: Center(child: Text('正在加载片库…')),
                      ),
                    ),
                  )
                else if (l.scenario == 'home-source-error' ||
                    feed.error != null && feed.items.isEmpty)
                  EmptyView(
                    '暂时无法加载片库',
                    '检查网络后重试',
                    icon: 'wifi-off',
                    action: '重试',
                    onTap: () {
                      l.scenario = 'normal';
                      l.changed();
                      l.catalog.load();
                    },
                  )
                else if (category == 0) ...[
                  HomeCarousel(
                    items: selected,
                    library: l,
                    active: widget.active,
                  ),
                  if (l.history.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, DS.space12, 18, 0),
                      child: ContinueCard(library: l),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, DS.space12, 18, 0),
                    child: WatchTogetherPanel(
                      onCreate: () => openRoom(false),
                      onJoin: () => openRoom(true),
                    ),
                  ),
                  CatalogSections(library: l),
                ],
                PreviewLabel(
                  text: l.provider == null ? '设计预览 · 虚构片目，无在线片源' : '片库内容由播放源提供',
                ),
                SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
              ],
            ),
    );
  }
}

class WatchTogetherPanel extends StatelessWidget {
  const WatchTogetherPanel({
    super.key,
    required this.onCreate,
    required this.onJoin,
  });
  final VoidCallback onCreate, onJoin;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    decoration: BoxDecoration(
      color: DSPalette.roomSurface,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: DSPalette.roomAction.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: DSIcon(
                  'users-round',
                  size: 20,
                  color: DSPalette.roomAction,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '一起看',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: DSPalette.onMedia,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '创建房间，或加入好友的邀请',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: DSPalette.roomMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                MediaQuery.textScalerOf(context).scale(14) * 10 + 100 >
                constraints.maxWidth;
            Widget action(bool join) => TextButton(
              key: Key(join ? 'home-join-room' : 'home-create-room'),
              onPressed: join ? onJoin : onCreate,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                overlayColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
                foregroundColor: join
                    ? DSPalette.onMedia
                    : DSPalette.roomSurface,
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: join ? Colors.transparent : DSPalette.roomAction,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: DSPalette.roomAction.withValues(alpha: .7),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (join)
                      const DSIcon('link', size: 15, color: DSPalette.onMedia)
                    else
                      const Icon(
                        Icons.add_circle,
                        size: 15,
                        color: DSPalette.roomSurface,
                      ),
                    const SizedBox(width: 6),
                    Text(
                      join ? '加入邀请' : '创建房间',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [action(false), action(true)],
                  )
                : Row(
                    children: [
                      Expanded(child: action(false)),
                      const SizedBox(width: 8),
                      Expanded(child: action(true)),
                    ],
                  );
          },
        ),
      ],
    ),
  );
}
