import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/motion.dart';
import '../../design/bottom_navigation.dart';
import '../auth/session.dart';
import '../experience/short_feed.dart';
import '../experience/preview_gallery.dart';
import '../experience/invite_pages.dart';
import 'library_state.dart';
import 'home_page.dart';
import 'collection_pages.dart';
import 'profile_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.session,
    this.preview = false,
    this.library,
    this.initialInviteToken,
    this.onInviteConsumed,
  });
  final Session? session;
  final bool preview;
  final LibraryState? library;
  final String? initialInviteToken;
  final VoidCallback? onInviteConsumed;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final library =
      widget.library ??
      LibraryState(
        accountId: widget.preview ? 'design-preview' : widget.session!.user!.id,
        session: widget.session,
        preview: widget.preview,
      );
  final tab = ValueNotifier(0);
  final preparingTab = ValueNotifier<int?>(null);
  late final navigation = Listenable.merge([tab, preparingTab]);
  final preparedTabs = <int>{0};
  int selectionRequest = 0;
  @override
  void initState() {
    super.initState();
    unawaited(library.restore());
    final token = widget.initialInviteToken;
    if (!widget.preview && token != null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onInviteConsumed?.call();
          openPage(
            context,
            ReceivedInvitePage(library: library, initialToken: token),
          );
        }
      });
  }

  @override
  void dispose() {
    preparingTab.dispose();
    tab.dispose();
    if (widget.library == null) library.dispose();
    super.dispose();
  }

  void select(int value) {
    if (!mounted) return;
    final request = ++selectionRequest;
    if (value == tab.value) {
      preparingTab.value = null;
      return;
    }
    if (preparedTabs.contains(value) ||
        MediaQuery.disableAnimationsOf(context)) {
      preparingTab.value = null;
      preparedTabs.add(value);
      tab.value = value;
      return;
    }
    // 首次布局不消耗动画时长：先离屏挂载，再同步提交内容与底栏选择。
    preparingTab.value = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 快速反向点击或退出时，旧准备任务不能抢回选择。
      if (!mounted || request != selectionRequest) return;
      preparedTabs.add(value);
      preparingTab.value = null;
      tab.value = value;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        // 切页复用同一批 Widget；只有业务数据变化才刷新页面描述。
        // 可见性由 MotionTabs 的 TickerMode 传递，避免离开首页时重建整棵列表。
        final pages = <Widget>[
          WatchHome(library: library, onProfile: () => select(3)),
          ShortFeed(library: library, active: true),
          HistoryPage(library: library, onBrowse: () => select(0)),
          ProfilePage(
            library: library,
            previewTools: kDebugMode
                ? TextButton(
                    onPressed: () =>
                        openPage(context, PreviewGallery(library: library)),
                    child: const Text('开发预览 · 18 页面 / 24 状态'),
                  )
                : null,
          ),
        ];
        return ListenableBuilder(
          listenable: navigation,
          builder: (context, _) {
            final index = tab.value;
            // 覆盖状态只更新导航壳，子页沿用 Playra 的可见性规则暂停后台工作。
            final covered = ModalRoute.isCurrentOf(context) == false;
            return Scaffold(
              // 内容延伸到玻璃底栏后方；各页通过底部 inset 保留最后一项的可达性。
              extendBody: true,
              body: Forest(
                child: SafeArea(
                  bottom: false,
                  child: MotionTabs(
                    index: index,
                    isCovered: covered,
                    preparingIndex: preparingTab.value,
                    children: pages,
                  ),
                ),
              ),
              bottomNavigationBar: DuosceneNavigation(
                index: index,
                onSelect: select,
                notifyReselection: true,
              ),
            );
          },
        );
      },
    );
  }
}
