import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/search_page.dart';
import '../playback/player_page.dart';
import 'chat_panel.dart';
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
    final visible =
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
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

  Future<void> _selectEpisode() async {
    final next = await showEpisodes(
      context,
      film,
      episode,
      shared: widget.library.preview,
    );
    if (next == null || !mounted) return;
    setState(() => episode = next);
    if (!pager.hasClients) return;
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

  Widget _content({Widget? surface}) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        surface: DSPalette.media,
        onSurface: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      extensions: [DSPalette.dark],
      textTheme: Theme.of(context).textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
    ),
    // Theme 不会替换外层 Material 已设置的 DefaultTextStyle，媒体覆盖层显式指定白色。
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bottom = MediaQuery.paddingOf(context).bottom;
          final favorite = widget.library.favorites.contains(film.id);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (surface != null)
                Positioned.fill(child: surface)
              else
                PageView.builder(
                  controller: pager,
                  scrollDirection: Axis.vertical,
                  itemCount: film.episodes,
                  onPageChanged: (index) => setState(() => episode = index + 1),
                  itemBuilder: (_, i) => Image.asset(
                    film.image,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Colors.transparent,
                        Color(0x24000000),
                        Color(0xED101216),
                      ],
                      stops: [0, .28, .54, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 16,
                right: 8,
                child: Row(
                  children: [
                    const Text(
                      '短剧',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 18),
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '推荐',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        SizedBox(
                          width: 16,
                          height: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.all(
                                Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '搜索短剧',
                      onPressed: () => openPage(
                        context,
                        SearchPage(library: widget.library, initialKind: '短剧'),
                      ),
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const DSIcon(
                        'search',
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                top: 116,
                bottom: bottom + 24,
                end: 8,
                width: 56,
                child: Align(
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    child: Column(
                      key: const Key('short-action-rail'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _action(
                          'favorite',
                          favorite ? 'bookmark-check' : 'bookmark',
                          '收藏',
                          () async {
                            try {
                              await widget.library.toggleFavorite(film);
                              if (mounted) setState(() {});
                            } catch (_) {
                              if (mounted) tell(context, '收藏保存失败，请重试。');
                            }
                          },
                          selected: favorite,
                        ),
                        const SizedBox(height: 6),
                        _action(
                          'chat',
                          'message-circle',
                          '私聊',
                          () => showPrivateChat(context, widget.library),
                          unread: widget.library.scenario == 'short-unread',
                        ),
                        const SizedBox(height: 6),
                        _action('episodes', 'list-video', '选集', _selectEpisode),
                        const SizedBox(height: 6),
                        _action(
                          'invite',
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
                ),
              ),
              PositionedDirectional(
                start: 16,
                end: 80,
                bottom: bottom + 12,
                child: ConstrainedBox(
                  key: const Key('short-details'),
                  // 控件与信息分别占位；大字体或矮屏时信息可滚动，不覆盖顶部导航。
                  constraints: BoxConstraints(
                    maxHeight: (constraints.maxHeight - bottom - 96).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          film.title,
                          maxLines:
                              MediaQuery.textScalerOf(context).scale(18) > 25
                              ? 2
                              : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 10,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              film.genre,
                              style: const TextStyle(
                                fontSize: 10,
                                height: 1.4,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '第 $episode 集 · 共 ${film.episodes} 集',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.4,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '有些重逢，是命中注定。',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: Colors.white70,
                          ),
                        ),
                        if (widget.library.preview) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.library.scenario == 'peer-offline'
                                ? '小满已断线 · 预览'
                                : '与小满一起看 · 预览',
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.4,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _action(
    String id,
    String icon,
    String text,
    VoidCallback tap, {
    bool selected = false,
    bool unread = false,
  }) => Semantics(
    selected: selected,
    child: TextButton(
      key: Key('short-$id'),
      onPressed: tap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 64),
        padding: const EdgeInsets.symmetric(vertical: 4),
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white.withValues(alpha: .24)
                      : Colors.black.withValues(alpha: .22),
                ),
                child: Center(
                  child: DSIcon(icon, size: 20, color: Colors.white),
                ),
              ),
              if (unread)
                Positioned(
                  top: -2,
                  right: -3,
                  child: Container(
                    width: 14,
                    height: 14,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '1',
                      style: TextStyle(
                        fontSize: 8,
                        color: DSPalette.media,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              height: 1.2,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
            ),
          ),
        ],
      ),
    ),
  );
}
