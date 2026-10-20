import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import 'catalog.dart';
import 'detail_page.dart';
import '../experience/experience_player.dart';
import 'library_state.dart';
import 'posters.dart';
import 'search_page.dart';

class HomeCarousel extends StatefulWidget {
  const HomeCarousel({
    super.key,
    required this.items,
    required this.library,
    required this.active,
  });
  final List<Film> items;
  final LibraryState library;
  final bool active;
  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel>
    with WidgetsBindingObserver {
  final pager = PageController();
  Timer? timer;
  int index = 0;
  bool foreground = true;
  bool paused = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    schedule();
  }

  @override
  void didUpdateWidget(covariant HomeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.map((f) => f.id).join() !=
        widget.items.map((f) => f.id).join()) {
      index = 0;
      if (pager.hasClients) pager.jumpToPage(0);
    }
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (paused ||
        !widget.active ||
        !foreground ||
        widget.items.length < 2 ||
        MediaQuery.disableAnimationsOf(context))
      return;
    timer = Timer(const Duration(seconds: 6), () {
      if (mounted &&
          pager.hasClients &&
          ModalRoute.isCurrentOf(context) != false &&
          TickerMode.valuesOf(context).enabled) {
        pager.animateToPage(
          (index + 1) % widget.items.length,
          duration: const Duration(milliseconds: 480),
          curve: DSMotion.curve,
        );
      }
      if (mounted) schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 208,
    child: Stack(
      children: [
        Listener(
          onPointerDown: (_) => timer?.cancel(),
          onPointerUp: (_) {
            paused = true;
            setState(() {});
            schedule();
          },
          onPointerCancel: (_) => schedule(),
          child: PageView.builder(
            key: const Key('home-carousel'),
            controller: pager,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              setState(() => index = i);
              schedule();
            },
            itemBuilder: (context, i) {
              final film = widget.items[i];
              void detail() => openPage(
                context,
                DetailPage(film: film, library: widget.library),
              );
              return Semantics(
                label: '推荐 ${i + 1}/${widget.items.length}：${film.title}',
                child: FilmHero(
                  film,
                  height: 208,
                  blendBackground: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        film.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
                          color: DSPalette.onMedia,
                          height: 1.1,
                          fontFamily: 'DuosceneDisplay',
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        film.synopsis.split('。').first,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => openPage(
                              context,
                              ExperiencePlayer(
                                film: film,
                                library: widget.library,
                              ),
                            ),
                            icon: DSIcon(
                              'play',
                              size: 17,
                              color: DSPalette.of(context).onPrimary,
                            ),
                            label: Text(
                              designSource(film) == null ? '选择视频' : '立即观看',
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconTap(
                            'info',
                            '影片详情',
                            detail,
                            color: DSPalette.onMedia,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Semantics(label: '推荐第 ${index + 1} 张，共 ${widget.items.length} 张',
                child: ExcludeSemantics(child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < widget.items.length; i++)
                      AnimatedContainer(
                        duration: DSMotion.duration(context),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: index == i ? 14 : 4, height: 3,
                        decoration: BoxDecoration(color: index == i ? Colors.white : Colors.white54,
                          borderRadius: BorderRadius.circular(2)),
                      ),
                  ]),
                )),
              ),
              IconButton(
                tooltip: paused ? '自动轮播' : '暂停轮播',
                onPressed: () { setState(() => paused = !paused); schedule(); },
                icon: Icon(paused ? Icons.play_arrow : Icons.pause, color: Colors.white, size: 18),
              ),
            ]),
          ),
        ),
      ],
    ),
  );
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.library});
  final LibraryState library;
  @override
  Widget build(BuildContext context) {
    final entry = library.history.first;
    final found = films.where((f) => f.id == entry.filmId);
    if (found.isEmpty) return const SizedBox.shrink();
    final film = found.first;
    return InkWell(
      onTap: () => openPage(
        context,
        ExperiencePlayer(
          film: film,
          library: library,
          resume: entry,
          episode: entry.episode,
        ),
      ),
      child: Panel(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                film.image,
                width: 40,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '继续观看 · ${film.title}',
                    style: DS.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${film.episodes > 1 ? '第 ${entry.episode} 集 · ' : ''}已看 ${entry.seconds ~/ 60}:${(entry.seconds % 60).toString().padLeft(2, '0')} · ${entry.shared ? '共同' : '个人'}',
                    style: DS.smallFor(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (entry.seconds / (film.minutes * 60)).clamp(0, 1),
                    minHeight: 2,
                    color: DSPalette.of(context).primary,
                    backgroundColor: DSPalette.of(context).line,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const DSIcon('play'),
          ],
        ),
      ),
    );
  }
}

class CatalogSections extends StatelessWidget {
  const CatalogSections({super.key, required this.library, this.kind});
  final LibraryState library;
  final String? kind;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final category
          in kind == null ? ['电影', '电视剧', '动漫', '短剧'] : [kind!]) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SectionHeading(
            {
              '电影': '电影 · 值得一看的故事',
              '电视剧': '电视剧 · 慢慢看完',
              '动漫': '动漫 · 另一种想象',
              '短剧': '短剧 · 此刻入戏',
            }[category]!,
            action: ArrowAction(
              '全部',
              onTap: () => openPage(
                context,
                SearchPage(library: library, initialKind: category),
              ),
            ),
          ),
        ),
        SizedBox(
          height:
              112 / .77 +
              16 +
              MediaQuery.textScalerOf(context).scale(DS.captionSize) * 3,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: films.where((f) => f.kind == category).length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final film = films.where((f) => f.kind == category).elementAt(i);
              return SizedBox(
                width: 112,
                child: FilmPoster(
                  film,
                  aspectRatio: .77,
                  showTitle: false,
                  onTap: () => openPage(
                    context,
                    DetailPage(film: film, library: library),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ],
  );
}
