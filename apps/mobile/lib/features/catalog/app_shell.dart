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
  int tab = 0;
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
    if (widget.library == null) library.dispose();
    super.dispose();
  }

  void select(int value) => setState(() => tab = value);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => Scaffold(
      body: Forest(
        child: SafeArea(
          bottom: false,
          child: MotionTabs(
            index: tab,
            children: [
              WatchHome(
                library: library,
                onProfile: () => select(3),
                active: tab == 0,
              ),
              ShortFeed(library: library, active: tab == 1),
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: DuosceneNavigation(index: tab, onSelect: select),
    ),
  );
}
