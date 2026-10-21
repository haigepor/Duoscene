import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/illustrations.dart';
import '../../design/scroll_chrome.dart';
import '../experience/invite_pages.dart';
import '../experience/settings_pages.dart';
import '../rooms/room_list_page.dart';
import '../rooms/room_repository.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'posters.dart';
import 'detail_page.dart';
import 'collection_pages.dart';
import '../experience/appearance_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.library, this.previewTools});
  final LibraryState library;
  final Widget? previewTools;
  @override
  Widget build(BuildContext context) => ScrollChrome(
    header: Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.pageInset),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '我的',
              style: TextStyle(
                fontSize: DS.pageTitleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconTap(
            'settings',
            '外观设置',
            () => openPage(context, const AppearancePage()),
          ),
        ],
      ),
    ),
    child: ListView(
      key: const PageStorageKey('profile'),
      padding: EdgeInsets.fromLTRB(
        16,
        DS.toolbarHeight,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const SizedBox(height: 6),
        InkWell(
          onTap: () => openPage(context, AccountPage(library: library)),
          child: Panel(
            child: Row(
              children: [
                MountainAvatar(initial: library.initial, size: DS.avatarMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(library.displayName, style: DS.section),
                      const SizedBox(height: 6),
                      Text(
                        library.preview ? '与喜欢的人，看喜欢的故事。' : '私有账户 · 仅受邀加入',
                        style: DS.smallFor(context),
                      ),
                    ],
                  ),
                ),
                DSIcon(
                  'chevron-right',
                  size: DS.chevronSize,
                  color: DSPalette.of(context).muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                '我的收藏',
                action: ArrowAction(
                  '查看全部',
                  onTap: () =>
                      openPage(context, FavoritesPage(library: library)),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('喜欢的故事，留到下次。', style: DS.smallFor(context)),
                  ),
                  const DSIllustration(
                    'collection-favorites-glass',
                    width: 72,
                    height: 52,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              if (library.favorites.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DS.space8),
                  child: Text('还没有收藏，去发现喜欢的影片。', style: DS.smallFor(context)),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in _favoriteCovers)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilmPoster(
                            f,
                            editorial: true,
                            showTitle: false,
                            showMetadata: false,
                            aspectRatio: .85,
                            onTap: () => openPage(
                              context,
                              DetailPage(film: f, library: library),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (library.preview)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    height: 40,
                    child: Stack(
                      children: [
                        const Positioned(
                          left: 32,
                          child: MountainAvatar(initial: '满', size: 40),
                        ),
                        Positioned(
                          left: 0,
                          child: MountainAvatar(
                            initial: library.initial,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('正在一起看 · 预览'),
                        Text('山海之间', style: DS.smallFor(context)),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => openPage(
                      context,
                      DetailPage(film: films.first, library: library),
                    ),
                    child: const Text('返回'),
                  ),
                ],
              ),
            ),
          ),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              MenuRow(
                'sun',
                '外观',
                onTap: () => openPage(context, const AppearancePage()),
              ),
              const Divider(height: 1),
              MenuRow('send', '观影邀请', onTap: () => _invitations(context)),
              Divider(
                height: 1,
                indent: DS.navigationIcon + DS.space12,
                color: DSPalette.of(context).line,
              ),
              MenuRow(
                'volume-2',
                '播放与音频',
                onTap: () =>
                    openPage(context, AudioSettingsPage(library: library)),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.space16),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: DS.space12),
          child: Column(
            children: [
              MenuRow(
                'shield-check',
                '隐私与记录',
                onTap: () => openPage(context, PrivacyPage(library: library)),
              ),
              Divider(
                height: 1,
                indent: DS.navigationIcon + DS.space12,
                color: DSPalette.of(context).line,
              ),
              MenuRow(
                'circle-help',
                '帮助与支持',
                onTap: () => openPage(context, const HelpPage()),
              ),
              Divider(
                height: 1,
                indent: DS.navigationIcon + DS.space12,
                color: DSPalette.of(context).line,
              ),
              MenuRow(
                'info',
                '关于 Duoscene',
                onTap: () => openPage(context, const AboutPage()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: InkWell(
            onTap: () => logout(context, library),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DSIcon(
                    'log-out',
                    color: DSPalette.of(context).muted,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    library.preview ? '退出预览' : '退出登录',
                    style: TextStyle(color: DSPalette.of(context).muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  static int _coverOrder(Film f) => switch (f.id) {
    'summer' => 0,
    'stars' => 1,
    'mountains' => 2,
    _ => 3,
  };

  Iterable<Film> get _favoriteCovers {
    final items = films.where((f) => library.favorites.contains(f.id)).toList()
      ..sort((a, b) => _coverOrder(a).compareTo(_coverOrder(b)));
    return items.take(3);
  }

  Future<void> _invitations(BuildContext context) => showDSSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('观影邀请', style: DS.heading),
            MenuRow(
              'users-round',
              '邀请与房间',
              onTap: () {
                Navigator.pop(sheet);
                if (library.preview) {
                  tell(context, '开发预览没有账户凭据，请登录后管理真实房间。');
                } else {
                  openPage(
                    context,
                    RoomListPage(
                      session: library.session!,
                      rooms: RoomRepository(library.session!),
                    ),
                  );
                }
              },
            ),
            MenuRow(
              'ticket',
              '接受观影邀请',
              onTap: () {
                Navigator.pop(sheet);
                openPage(context, ReceivedInvitePage(library: library));
              },
            ),
          ],
        ),
      ),
    ),
  );
}
