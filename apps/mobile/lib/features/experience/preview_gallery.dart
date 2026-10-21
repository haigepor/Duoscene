import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../auth/login_page.dart';
import '../../design/bottom_navigation.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/search_page.dart';
import '../catalog/detail_page.dart';
import '../catalog/collection_pages.dart';
import '../catalog/profile_page.dart';
import '../catalog/home_page.dart';
import 'experience_player.dart';
import 'short_feed.dart';
import 'chat_panel.dart';
import 'episode_sheet.dart';
import 'invite_pages.dart';
import 'settings_pages.dart';

const previewPages = [
  '观影首页',
  '短剧推荐流',
  '观看记录',
  '我的',
  '影片详情',
  '长视频与私聊',
  '短剧私聊',
  '发送邀请',
  '搜索',
  '选集',
  '播放与音频',
  '私有账户登录',
  '我的收藏',
  '接收邀请',
  '隐私与记录',
  '账户信息',
  '帮助与反馈',
  '关于 Duoscene',
];
const previewStates = <String, String>{
  'home-loading': '片库加载中',
  'home-source-error': '片库加载失败重试',
  'history-empty': '无观看记录',
  'favorites-empty': '无收藏',
  'private-chat-empty': '尚未邀请好友',
  'peer-buffering': '好友缓冲等待',
  'peer-offline': '好友断线重连',
  'manual-pause': '手动暂停优先',
  'message-send-failed': '消息失败原条重试',
  'chat-keyboard': '短剧键盘展开',
  'mic-denied': '麦克风权限拒绝',
  'invite-busy': '邀请生成中防重',
  'invite-expired-sender': '邀请发送方过期',
  'invite-expired-receiver': '邀请接收方过期',
  'room-full': '房间满员',
  'room-closed': '房间关闭',
  'invite-revoked': '邀请撤销',
  'shared-episode': '同看换集确认',
  'short-unread': '短剧未读私聊',
  'clear-history': '清理记录确认',
  'logout': '退出登录确认',
  'login-invalid': '登录信息无效',
  'search-empty': '搜索无结果',
  'media-unavailable': '片源不可用',
};

/// 预览身份只存在于独立模型中，不能为 Session 写入凭据或访问房间 API。
class PreviewGallery extends StatelessWidget {
  const PreviewGallery({super.key, required this.library});
  final LibraryState library;
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return PageFrame(
      title: '开发预览',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PreviewLabel(text: '虚构片目与示例身份 · 所有联网能力边界明确标注'),
          for (var i = 0; i < previewPages.length; i++)
            ListTile(
              title: Text(
                '${(i + 1).toString().padLeft(2, '0')} · ${previewPages[i]}',
              ),
              trailing: const DSIcon('chevron-right', size: 18),
              onTap: () => openPage(context, PreviewHost(page: i)),
            ),
          const Divider(),
          const Text('交互状态', style: DS.heading),
          for (final e in previewStates.entries)
            ListTile(
              title: Text(e.value),
              subtitle: Text(e.key, style: DS.smallFor(context)),
              onTap: () => openPage(
                context,
                PreviewHost(page: _statePage(e.key), scenario: e.key),
              ),
            ),
        ],
      ),
    );
  }

  int _statePage(String id) {
    if (id.startsWith('home-')) return 0;
    if (id == 'history-empty') return 2;
    if (id == 'favorites-empty') return 12;
    if (id.startsWith('invite-') && id != 'invite-revoked')
      return id.endsWith('receiver') ? 13 : 7;
    if (id.startsWith('room-') || id == 'invite-revoked') return 13;
    if (id == 'shared-episode') return 9;
    if (id == 'short-unread') return 1;
    if (id == 'clear-history') return 14;
    if (id == 'logout') return 15;
    if (id == 'login-invalid') return 11;
    if (id == 'search-empty') return 8;
    if (id == 'mic-denied') return 10;
    if (id == 'media-unavailable') return 4;
    if (id == 'message-send-failed' || id == 'chat-keyboard') return 6;
    return 5;
  }
}

class PreviewHost extends StatefulWidget {
  const PreviewHost({super.key, required this.page, this.scenario = 'normal'});
  final int page;
  final String scenario;
  @override
  State<PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<PreviewHost> {
  late final l = LibraryState(accountId: 'preview-only', preview: true)
    ..scenario = widget.scenario;
  @override
  void dispose() {
    l.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: l, builder: (context, _) => _page(context));

  Widget _page(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    switch (widget.page) {
      case 0:
        return _frame(
          WatchHome(
            library: l,
            onProfile: () => openPage(context, const PreviewHost(page: 3)),
          ),
        );
      case 1:
        return _frame(ShortFeed(library: l, active: true));
      case 2:
        return _frame(
          HistoryPage(
            library: l,
            onBrowse: () => openPage(context, const PreviewHost(page: 0)),
          ),
        );
      case 3:
        return _frame(ProfilePage(library: l));
      case 4:
        return DetailPage(film: films.first, library: l);
      case 5:
        return ExperiencePlayer(film: films.first, library: l);
      case 6:
        return _ShortOverlay(library: l, chat: true);
      case 7:
        return _InvitePreview(library: l);
      case 8:
        return SearchPage(
          library: l,
          initialQuery: l.scenario == 'search-empty' ? '不存在的片名' : '山海',
        );
      case 9:
        return _ShortOverlay(library: l, chat: false);
      case 10:
        return AudioSettingsPage(library: l);
      case 11:
        return LoginPage(
          session: null,
          previewError: l.scenario == 'login-invalid',
        );
      case 12:
        return FavoritesPage(library: l);
      case 13:
        return ReceivedInvitePage(library: l);
      case 14:
        return PrivacyPage(library: l);
      case 15:
        return AccountPage(library: l);
      case 16:
        return const HelpPage();
      default:
        return const AboutPage();
    }
  }

  Widget _frame(Widget child) => Scaffold(
    extendBody: true,
    body: Forest(child: SafeArea(bottom: false, child: child)),
    bottomNavigationBar: DuosceneNavigation(
      index: widget.page,
      onSelect: (index) => openPage(context, PreviewHost(page: index)),
    ),
  );
}

class _ShortOverlay extends StatefulWidget {
  const _ShortOverlay({required this.library, required this.chat});
  final LibraryState library;
  final bool chat;
  @override
  State<_ShortOverlay> createState() => _ShortOverlayState();
}

class _ShortOverlayState extends State<_ShortOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.chat)
        showPrivateChat(context, widget.library);
      else
        showEpisodes(context, films.last, 8, shared: true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: ShortFeed(library: widget.library, active: true)),
  );
}

class _InvitePreview extends StatefulWidget {
  const _InvitePreview({required this.library});
  final LibraryState library;
  @override
  State<_InvitePreview> createState() => _InvitePreviewState();
}

class _InvitePreviewState extends State<_InvitePreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        showInvite(
          context,
          film: films.first,
          library: widget.library,
          position: 2180,
        );
    });
  }

  @override
  Widget build(BuildContext context) =>
      ExperiencePlayer(film: films.first, library: widget.library);
}
