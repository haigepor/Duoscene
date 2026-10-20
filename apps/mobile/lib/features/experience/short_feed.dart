import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/search_page.dart';
import '../playback/player_page.dart';
import 'chat_panel.dart';
import 'experience_player.dart';
import 'episode_sheet.dart';
import 'invite_pages.dart';

class ShortFeed extends StatefulWidget {
  const ShortFeed({super.key, required this.library, required this.active});
  final LibraryState library;
  final bool active;
  @override
  State<ShortFeed> createState() => _ShortFeedState();
}

class _ShortFeedState extends State<ShortFeed> {
  final pager = PageController(initialPage: 7);
  int episode = 8;
  bool manualPause = true;
  PlayerPresentation? current;
  Film get film => films.last;
  @override
  void didUpdateWidget(covariant ShortFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      unawaited(current?.session.pause());
    }
  }

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = designSource(film);
    // 路由覆盖时让短剧停止持有媒体，避免搜索页后面继续播放。
    final visible = widget.active && (ModalRoute.isCurrentOf(context) ?? true);
    if (source != null && visible)
      return PlayerPage(
        key: const ValueKey('short-player-owner'),
        roomName: film.title,
        initialSource: source,
        presentation: (context, p, surface) {
          current = p;
          return _content(surface: surface);
        },
      );
    // 原稿帧仅作预览封面；没有真实片源时明确标注，绝不推进假视频进度。
    return _content();
  }

  Widget _content({Widget? surface}) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.dark,
      iconTheme: const IconThemeData(color: Colors.white),
      extensions: [DSPalette.dark],
      textTheme: Theme.of(context).textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
    ),
    child: Builder(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          if (surface != null)
            Positioned.fill(child: surface)
          else
            PageView.builder(
              controller: pager,
              scrollDirection: Axis.vertical,
              itemCount: 60,
              onPageChanged: (index) => setState(() => episode = index + 1),
              itemBuilder: (_, i) => Image.asset(film.image, fit: BoxFit.cover),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x70000000),
                    Colors.transparent,
                    Color(0xE6081414),
                  ],
                  stops: [0, .45, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 18,
            right: 8,
            child: Row(
              children: [
                const Text(
                  '短剧',
                  style: TextStyle(
                    fontSize: DS.pageTitleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 24),
                Text(
                  '推荐',
                  style: TextStyle(
                    fontSize: DS.itemTitleSize,
                    decoration: TextDecoration.underline,
                    decorationColor: DSPalette.of(context).primary,
                    decorationThickness: 3,
                  ),
                ),
                const Spacer(),
                IconTap(
                  'search',
                  '搜索短剧',
                  () => openPage(context, SearchPage(library: widget.library)),
                ),
              ],
            ),
          ),
          if (widget.library.preview)
            Positioned(
              top: 78,
              left: 18,
              child: Panel(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MountainAvatar(size: 28),
                    const MountainAvatar(initial: '满', size: 28),
                    const SizedBox(width: 8),
                    Text(
                      widget.library.scenario == 'peer-offline'
                          ? '小满已断线 · 预览'
                          : '与小满一起看 · 预览',
                      style: const TextStyle(fontSize: DS.labelSize),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 6,
            bottom: 165,
            child: Column(
              children: [
                _action(
                  widget.library.favorites.contains(film.id)
                      ? 'bookmark-check'
                      : 'bookmark',
                  '收藏',
                  () async {
                    await widget.library.toggleFavorite(film);
                    if (mounted) setState(() {});
                  },
                ),
                _action(
                  'message-circle',
                  widget.library.scenario == 'short-unread' ? '私聊 · 1' : '私聊',
                  () => showPrivateChat(context, widget.library),
                ),
                _action('list-video', '选集', () async {
                  final next = await showEpisodes(
                    context,
                    film,
                    episode,
                    shared: widget.library.preview,
                  );
                  if (next != null && mounted) {
                    setState(() => episode = next);
                    if (pager.hasClients) {
                      if (MediaQuery.disableAnimationsOf(context)) {
                        pager.jumpToPage(next - 1);
                      } else {
                        pager.animateToPage(
                          next - 1,
                          duration: DSMotion.navigation,
                          curve: DSMotion.curve,
                        );
                      }
                    }
                  }
                }),
                _action(
                  'users-round',
                  '一起看',
                  () => showInvite(
                    context,
                    film: film,
                    library: widget.library,
                    episode: episode,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 18,
            right: 72,
            bottom: 25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '都市情感',
                  style: TextStyle(
                    color: DSPalette.of(context).primary,
                    fontSize: DS.labelSize,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  film.title,
                  style: const TextStyle(
                    fontSize: DS.displaySize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '第 $episode 集 / 共 60 集 · 每集 2 分钟',
                  style: TextStyle(color: DSPalette.of(context).muted),
                ),
                const SizedBox(height: 8),
                const Text('有些重逢，是命中注定。'),
                const SizedBox(height: 12),
                if (sourceMissing)
                  OutlinedButton(
                    onPressed: () => openPage(
                      context,
                      ExperiencePlayer(
                        film: film,
                        library: widget.library,
                        episode: episode,
                      ),
                    ),
                    child: const Text('封面预览 · 选择自己的视频'),
                  ),
                if (widget.library.preview)
                  InkWell(
                    onTap: () => showPrivateChat(context, widget.library),
                    child: const Panel(
                      padding: EdgeInsets.all(10),
                      child: Row(
                        children: [
                          MountainAvatar(initial: '满', size: 24),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '小满：这一集反转好突然！',
                              style: TextStyle(fontSize: DS.captionSize),
                            ),
                          ),
                          DSIcon('chevron-right', size: 16),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  bool get sourceMissing => designSource(film) == null;
  Widget _action(String icon, String text, VoidCallback tap) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: DSPalette.of(context).muted),
            color: DSPalette.of(context).bg.withValues(alpha: .3),
          ),
          child: IconTap(icon, text, tap),
        ),
        const SizedBox(height: 3),
        Text(text, style: const TextStyle(fontSize: DS.captionSize)),
      ],
    ),
  );
}
