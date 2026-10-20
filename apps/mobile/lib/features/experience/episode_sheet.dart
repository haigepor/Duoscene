import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/motion.dart';
import '../catalog/catalog.dart';

Future<int?> showEpisodes(
  BuildContext context,
  Film film,
  int episode, {
  required bool shared,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => EpisodeSheet(film: film, episode: episode, shared: shared),
);

class EpisodeSheet extends StatefulWidget {
  const EpisodeSheet({
    super.key,
    required this.film,
    required this.episode,
    required this.shared,
  });
  final Film film;
  final int episode;
  final bool shared;
  @override
  State<EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<EpisodeSheet> {
  late int segment = (widget.episode - 1) ~/ 20;
  bool waiting = false;
  @override
  Widget build(BuildContext context) {
    final f = widget.film;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('选集', style: DS.heading)),
                  IconTap('x', '关闭选集', () => Navigator.pop(context)),
                ],
              ),
              Text(
                '${f.title} · 第 ${widget.episode} 集 / 共 ${f.episodes} 集',
                style: TextStyle(color: DSPalette.of(context).muted),
              ),
              const SizedBox(height: 16),
              if (f.episodes > 20)
                DSTabs(
                  labels: [
                    for (var i = 0; i < (f.episodes / 20).ceil(); i++)
                      '${i * 20 + 1}–${((i + 1) * 20).clamp(1, f.episodes)}',
                  ],
                  index: segment,
                  onChanged: (i) {
                    if (!waiting) setState(() => segment = i);
                  },
                ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var ep = segment * 20 + 1;
                      ep <= ((segment + 1) * 20).clamp(1, f.episodes);
                      ep++
                    )
                      SizedBox(
                        width: (c.maxWidth - 32) / 5,
                        height: 44,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            backgroundColor: ep == widget.episode
                                ? DSPalette.of(context).primary
                                : Colors.transparent,
                            foregroundColor: ep == widget.episode
                                ? DSPalette.of(context).bg
                                : DSPalette.of(context).ink,
                            side: BorderSide(color: DSPalette.of(context).line),
                          ),
                          onPressed: waiting
                              ? null
                              : () async {
                                  if (ep == widget.episode) {
                                    Navigator.pop(context);
                                    return;
                                  }
                                  if (widget.shared) {
                                    // 同看时先确认，绝不提前切换本机片源；没有同步服务时维持等待。
                                    if (!await confirm(
                                          context,
                                          '一起切换到第 $ep 集？',
                                          '好友确认并准备好后才能切换。',
                                          action: '请求换集',
                                        ) ||
                                        !mounted)
                                      return;
                                    setState(() => waiting = true);
                                  } else {
                                    Navigator.pop(context, ep);
                                  }
                                },
                          child: Text(ep.toString().padLeft(2, '0')),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  DSIcon('users-round', color: DSPalette.of(context).muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      waiting
                          ? '界面预览：等待好友确认，尚未换集'
                          : widget.shared
                          ? '同看时，换集将与好友同步确认'
                          : '个人观看，可直接选集',
                      style: DS.smallFor(context),
                    ),
                  ),
                ],
              ),
              if (waiting)
                TextButton(
                  onPressed: () => setState(() => waiting = false),
                  child: const Text('取消换集请求'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
