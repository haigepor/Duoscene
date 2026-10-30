import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/window_layout.dart';
import '../catalog/catalog.dart';

Future<int?> showEpisodes(
  BuildContext context,
  Film film,
  int episode, {
  required bool shared,
  bool binge = false,
  ValueChanged<bool>? onBingeChanged,
}) {
  final isWide = WindowLayout.isWide(context);
  if (isWide) {
    return _showSideSheet<int>(
      context: context,
      builder: (ctx) => EpisodeSheet(
        film: film,
        episode: episode,
        shared: shared,
        binge: binge,
        onBingeChanged: onBingeChanged,
        isSideSheet: true,
      ),
    );
  }
  return showDSSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EpisodeSheet(
      film: film,
      episode: episode,
      shared: shared,
      binge: binge,
      onBingeChanged: onBingeChanged,
      isSideSheet: false,
    ),
  );
}

Future<T?> _showSideSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final palette = DSPalette.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭选集',
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.60 : 0.38),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final width = (MediaQuery.sizeOf(dialogContext).width * 0.44)
          .clamp(360.0, 440.0);
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: width,
            height: double.infinity,
            decoration: BoxDecoration(
              color: palette.panel,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                  blurRadius: 24,
                  offset: const Offset(-4, 0),
                ),
              ],
            ),
            child: SafeArea(
              left: false,
              right: true,
              child: builder(dialogContext),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class EpisodeSheet extends StatefulWidget {
  const EpisodeSheet({
    super.key,
    required this.film,
    required this.episode,
    required this.shared,
    this.binge = false,
    this.onBingeChanged,
    this.isSideSheet = false,
  });
  final Film film;
  final int episode;
  final bool shared;
  final bool binge;
  final ValueChanged<bool>? onBingeChanged;
  final bool isSideSheet;
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = widget.isSideSheet ? 20.0 : 8.0;
    final horizontalPadding = widget.isSideSheet ? 20.0 : DS.pageInset;
    final bottomPadding = widget.isSideSheet ? 24.0 : DS.space16;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
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
                  const Spacer(),
                  if (f.episodes > 1) ...[
                    orderToggle(palette),
                    const SizedBox(width: DS.space8),
                  ],
                  IconTap('x', '关闭选集', () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${f.title} · 第 ${widget.episode} 集 / 共 ${f.episodes} 集',
                style: DS.smallFor(context),
              ),
              const SizedBox(height: 12),
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
                builder: (context, c) {
                  const cols = 5;
                  final itemWidth =
                      ((c.maxWidth - (cols - 1) * 8) / cols).floorToDouble();
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final ep in eps)
                        SizedBox(
                          width: itemWidth,
                          height: (MediaQuery.textScalerOf(context)
                                          .scale(DS.labelSize) *
                                      1.4 +
                                  DS.space24)
                              .clamp(DS.touchTarget, double.infinity),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: waiting
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
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  color: ep == widget.episode
                                      ? palette.primary
                                      : (isDark
                                          ? const Color(0xFF22252E)
                                          : const Color(0xFFF1F3F5)),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: ep == widget.episode
                                      ? [
                                          BoxShadow(
                                            color: palette.primary
                                                .withValues(alpha: .28),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  ep.toString().padLeft(2, '0'),
                                  style: DS.label.copyWith(
                                    fontWeight: ep == widget.episode
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: ep == widget.episode
                                        ? palette.onPrimary
                                        : palette.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = selected
        ? palette.primary.withValues(alpha: 0.12)
        : (isDark ? const Color(0xFF22252E) : const Color(0xFFF1F3F5));
    final textColor = selected ? palette.primary : palette.muted;

    return Padding(
      key: selected ? selectedTab : null,
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: waiting
              ? null
              : () {
                  if (logical != segment) setState(() => segment = logical);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(
                      color: palette.primary.withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
            ),
            child: Text(
              '${logical * 20 + 1}–${((logical + 1) * 20).clamp(1, widget.film.episodes)}',
              style: DS.label.copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: textColor,
              ),
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
    final color = active ? palette.primary : palette.muted;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = active
        ? palette.primary.withValues(alpha: 0.12)
        : (isDark ? const Color(0xFF22252E) : const Color(0xFFF1F3F5));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('episode-order-toggle'),
        borderRadius: BorderRadius.circular(16),
        onTap: toggleOrder,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DSIcon(
                active ? 'arrow-down' : 'arrow-up',
                size: 13,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                active ? '倒序' : '正序',
                style: DS.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
