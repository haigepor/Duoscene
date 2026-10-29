import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/catalog.dart';

Future<int?> showEpisodes(
  BuildContext context,
  Film film,
  int episode, {
  required bool shared,
  bool binge = false,
  ValueChanged<bool>? onBingeChanged,
}) => showDSSheet<int>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => EpisodeSheet(
    film: film,
    episode: episode,
    shared: shared,
    binge: binge,
    onBingeChanged: onBingeChanged,
  ),
);

class EpisodeSheet extends StatefulWidget {
  const EpisodeSheet({
    super.key,
    required this.film,
    required this.episode,
    required this.shared,
    this.binge = false,
    this.onBingeChanged,
  });
  final Film film;
  final int episode;
  final bool shared;
  final bool binge;
  final ValueChanged<bool>? onBingeChanged;
  @override
  State<EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<EpisodeSheet> {
  late int segment = (widget.episode - 1) ~/ 20;
  late bool binge = widget.binge;
  bool waiting = false;
  bool descending = false;
  final selectedTab = GlobalKey();
  final segmentScroll = ScrollController();

  @override
  void dispose() {
    segmentScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => alignSegment());
  }

  // 打开或切倒序后，把当前集所在分段滚到可视区中央。
  // 关键：上下文要在新帧布局完成后才取，直接同步取会拿到旧元素或空值。
  void alignSegment({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tab = selectedTab.currentContext;
      if (tab == null) return;
      Scrollable.ensureVisible(
        tab,
        duration: animated ? DSMotion.duration(context) : Duration.zero,
        curve: DSMotion.curve,
        alignment: .5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.film;
    final palette = DSPalette.of(context);
    final count = (f.episodes / 20).ceil();
    var displaySegments = [for (var i = 0; i < count; i++) i];
    if (descending) displaySegments = displaySegments.reversed.toList();
    final start = segment * 20 + 1;
    final end = ((segment + 1) * 20).clamp(1, f.episodes);
    var eps = [for (var ep = start; ep <= end; ep++) ep];
    if (descending) eps = eps.reversed.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DS.pageInset,
        0,
        DS.pageInset,
        DS.space16,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('选集', style: DS.section),
                  if (f.episodes > 1) ...[
                    const SizedBox(width: DS.space8),
                    orderToggle(palette),
                  ],
                  const Spacer(),
                  IconTap('x', '关闭选集', () => Navigator.pop(context)),
                ],
              ),
              Text(
                '${f.title} · 第 ${widget.episode} 集 / 共 ${f.episodes} 集',
                style: DS.smallFor(context),
              ),
              const SizedBox(height: DS.space8),
              // 分段多时横向滑动查看，标签按内容取宽不再截断。
              if (count > 1)
                SingleChildScrollView(
                  key: const Key('episode-segment-scroll'),
                  controller: segmentScroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final logical in displaySegments)
                        segmentTab(logical, palette),
                      const SizedBox(width: DS.space8),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ep in eps)
                      SizedBox(
                        width: (c.maxWidth - 32) / 5,
                        height:
                            (MediaQuery.textScalerOf(context)
                                            .scale(DS.labelSize) *
                                        1.4 +
                                    DS.space24)
                                .clamp(DS.touchTarget, double.infinity),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            backgroundColor: ep == widget.episode
                                ? palette.primary
                                : Colors.transparent,
                            foregroundColor: ep == widget.episode
                                ? palette.onPrimary
                                : palette.ink,
                            side: BorderSide(color: palette.line),
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
                          child: Text(
                            ep.toString().padLeft(2, '0'),
                            style: DS.label,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (widget.onBingeChanged != null) ...[
                Row(
                  children: [
                    DSIcon('play', size: 18, color: palette.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('自动连播', style: DS.label),
                          Text(
                            '本集播完自动接播下一集，整部播完换下一部短剧',
                            style: DS.smallFor(context),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      key: const Key('episode-binge-switch'),
                      value: binge,
                      onChanged: (value) {
                        setState(() => binge = value);
                        widget.onBingeChanged?.call(value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (waiting) ...[
                Text(
                  '界面预览：等待好友确认，尚未换集',
                  style: DS.smallFor(context),
                ),
                TextButton(
                  onPressed: () => setState(() => waiting = false),
                  child: const Text('取消换集请求'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget segmentTab(int logical, DSPalette palette) {
    final selected = logical == segment;
    return Padding(
      key: selected ? selectedTab : null,
      padding: const EdgeInsets.only(right: 2),
      child: TextButton(
        style: TextButton.styleFrom(
          // 分段页签补足纵向命中区：只加高度不改视觉位置。
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: waiting
            ? null
            : () {
                if (logical != segment) setState(() => segment = logical);
              },
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? palette.primary : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${logical * 20 + 1}–${((logical + 1) * 20).clamp(1, widget.film.episodes)}',
            style: DS.label.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? palette.primary : palette.muted,
            ),
          ),
        ),
      ),
    );
  }

  // 倒序一键直达最新一页：分段条反转后最新段就在最左，无需再滑到最右。
  // 关闭倒序则回到正在看的那一分段。
  void toggleOrder() {
    final count = (widget.film.episodes / 20).ceil();
    setState(() {
      descending = !descending;
      if (descending) {
        segment = count - 1;
      } else {
        segment = (widget.episode - 1) ~/ 20;
      }
    });
    if (descending) {
      if (segmentScroll.hasClients) {
        segmentScroll.animateTo(
          0,
          duration: DSMotion.duration(context),
          curve: DSMotion.curve,
        );
      }
    } else {
      alignSegment(animated: true);
    }
  }

  Widget orderToggle(DSPalette palette) {
    final active = descending;
    final color = active ? palette.onTint : palette.muted;
    return TextButton(
      key: const Key('episode-order-toggle'),
      style: TextButton.styleFrom(
        backgroundColor: active ? palette.tint : Colors.transparent,
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: active ? palette.tint : palette.line),
        ),
      ),
      onPressed: toggleOrder,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DSIcon('arrow-up', size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '倒序',
            style: DS.label.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
