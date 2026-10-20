import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import '../../design/scroll_chrome.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'search_page.dart';
import 'home_content.dart';
import '../rooms/room_list_page.dart';
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
  @override
  Widget build(BuildContext context) {
    final l = widget.library;
    final selected = films
        .where(
          (f) => category == 0
              ? !f.short &&
                    const [
                      'mountains',
                      'summer',
                      'stars',
                      'clouds',
                    ].contains(f.id)
              : f.kind == ['推荐', '电影', '电视剧', '动漫', '短剧'][category],
        )
        .toList();
    return ScrollChrome(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const Expanded(child: Brand()),
              IconButton(
                onPressed: widget.onProfile,
                tooltip: '我的账户',
                icon: MountainAvatar(initial: l.initial, size: 28),
              ),
            ],
          ),
        ),
      ),
      child: ListView(
        key: const PageStorageKey('watch-home'),
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: DS.toolbarHeight),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: InkWell(
              onTap: () => openPage(context, SearchPage(library: l)),
              borderRadius: BorderRadius.circular(28),
              child: Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    DSIcon(
                      'search',
                      size: 20,
                      color: DSPalette.of(context).muted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '搜索影片、剧集',
                      style: TextStyle(color: DSPalette.of(context).muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DSTabs(
            labels: const ['推荐', '电影', '电视剧', '动漫', '短剧'],
            index: category,
            onChanged: (i) => setState(() => category = i),
          ),
          if (l.scenario == 'home-loading')
            const Padding(
              padding: EdgeInsets.all(18),
              child: Panel(
                child: SizedBox(
                  height: 290,
                  child: Center(child: Text('正在加载片库…')),
                ),
              ),
            )
          else if (l.scenario == 'home-source-error')
            EmptyView(
              '暂时无法加载片库',
              '检查网络后重试',
              icon: 'wifi-off',
              action: '重试',
              onTap: () {
                l.scenario = 'normal';
                l.changed();
              },
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DS.panelRadius),
                child: HomeCarousel(
                  items: selected,
                  library: l,
                  active: widget.active,
                ),
              ),
            ),
            if (l.history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  DS.carouselContentGap,
                  16,
                  0,
                ),
                child: ContinueCard(library: l),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Panel(
                child: MenuRow(
                  'users-round',
                  '一起看',
                  subtitle: '创建房间，或加入好友的邀请',
                  onTap: () {
                    if (l.session == null) {
                      tell(context, '登录后即可创建或加入真实房间。');
                    } else {
                      openPage(
                        context,
                        RoomListPage(
                          session: l.session!,
                          rooms: RoomRepository(l.session!),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            CatalogSections(
              library: l,
              kind: category == 0
                  ? null
                  : ['推荐', '电影', '电视剧', '动漫', '短剧'][category],
            ),
          ],
          const PreviewLabel(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
