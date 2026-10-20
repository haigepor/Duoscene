import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/scroll_chrome.dart';
import '../experience/experience_player.dart';
import '../experience/episode_sheet.dart';
import '../experience/invite_pages.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'posters.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.film,
    required this.library,
    this.resume,
  });
  final Film film;
  final LibraryState library;
  final WatchEntry? resume;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late int episode = widget.resume?.episode ?? 1;
  @override
  Widget build(BuildContext context) {
    final f = widget.film, l = widget.library;
    final unavailable = l.scenario == 'media-unavailable';
    return Scaffold(
      body: Forest(
        child: Stack(
          children: [
            ScrollChrome(
              fadeStart: MediaQuery.sizeOf(context).height * .42 - 110,
              fadeExtent: 64,
              header: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconTap(
                      'arrow-left',
                      '返回',
                      () => Navigator.maybePop(context),
                    ),
                    const Spacer(),
                    IconTap(
                      l.favorites.contains(f.id)
                          ? 'bookmark-check'
                          : 'bookmark',
                      '收藏影片',
                      () async {
                        try {
                          await l.toggleFavorite(f);
                          if (mounted) setState(() {});
                        } catch (_) {
                          if (context.mounted) tell(context, '收藏保存失败，请重试。');
                        }
                      },
                    ),
                  ],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 110),
                children: [
                  FilmHero(f, height: MediaQuery.sizeOf(context).height * .42),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        const Text(
                          '剧情简介',
                          style: TextStyle(
                            fontSize: DS.sectionSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          f.synopsis,
                          style: TextStyle(
                            color: DSPalette.of(context).muted,
                            height: 1.8,
                          ),
                        ),
                        if (f.episodes > 1)
                          MenuRow(
                            'list-video',
                            '选集 · 第 $episode 集',
                            subtitle: '共 ${f.episodes} 集',
                            onTap: () async {
                              final next = await showEpisodes(
                                context,
                                f,
                                episode,
                                shared: false,
                              );
                              if (next != null && mounted)
                                setState(() => episode = next);
                            },
                          ),
                        if (widget.resume != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              '从${widget.resume!.shared ? '共同' : '个人'}进度 ${widget.resume!.seconds ~/ 60}:${(widget.resume!.seconds % 60).toString().padLeft(2, '0')} 继续 · 本机',
                              style: TextStyle(
                                color: DSPalette.of(context).primary,
                              ),
                            ),
                          ),
                        const PreviewLabel(),
                        const Divider(height: 36),
                        const Text(
                          '你可能也喜欢',
                          style: TextStyle(fontSize: DS.sectionSize),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final other
                                in films.where((v) => v.id != f.id).take(3))
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: FilmPoster(
                                    other,
                                    onTap: () => openPage(
                                      context,
                                      DetailPage(film: other, library: l),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: DSPalette.of(context).bg.withValues(alpha: .96),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: unavailable
                                ? null
                                : () => openPage(
                                    context,
                                    ExperiencePlayer(
                                      film: f,
                                      library: l,
                                      episode: episode,
                                      resume: widget.resume,
                                    ),
                                  ),
                            icon: DSIcon(
                              'play',
                              color: DSPalette.of(context).onPrimary,
                              size: 18,
                            ),
                            label: Text(
                              unavailable
                                  ? '片源暂不可用'
                                  : designSource(f) == null
                                  ? '选择视频观看'
                                  : widget.resume != null
                                  ? '继续观看'
                                  : '立即观看',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: unavailable
                                ? null
                                : () => showInvite(
                                    context,
                                    film: f,
                                    library: l,
                                    episode: episode,
                                    position: widget.resume?.seconds ?? 0,
                                  ),
                            child: const Text('邀请一起看'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
