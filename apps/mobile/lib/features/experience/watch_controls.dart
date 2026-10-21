import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/library_state.dart';
import '../catalog/media_provider.dart';
import '../playback/player_page.dart';

/// 观看页的三个紧凑入口；具体状态和操作收进对应弹层。
class WatchControls extends StatefulWidget {
  const WatchControls({
    super.key,
    required this.player,
    required this.library,
    required this.status,
    required this.shared,
    required this.onInvite,
    this.onPeerReady,
    this.onEndPreview,
    this.lines = const [],
    this.lineCode,
    this.onLine,
  });
  final PlayerPresentation player;
  final LibraryState library;
  final String status;
  final bool shared;
  final Future<void> Function() onInvite;
  final VoidCallback? onPeerReady, onEndPreview;
  final List<MediaLine> lines;
  final String? lineCode;
  final Future<void> Function(String)? onLine;

  @override
  State<WatchControls> createState() => WatchControlsState();
}

class WatchControlsState extends State<WatchControls> {
  int? active;

  Future<void> chooseSource() => _open(0);
  Future<void> showTogether() => _open(1);
  Future<void> chooseQuality() => _open(3);

  Future<void> _open(int index) async {
    if (active != null) return;
    FocusScope.of(context).unfocus();
    setState(() => active = index);
    final action = await showDSSheet<String>(
      context: context,
      builder: (c) => switch (index) {
        0 => _source(c),
        1 => _together(c),
        3 => _WatchQualitySheet(player: widget.player),
        _ => _audio(c),
      },
    );
    if (!mounted) return;
    setState(() => active = null);
    if (action != null && action.startsWith('line:')) {
      await widget.onLine?.call(action.substring(5));
      return;
    }
    // 先关闭选择层再进入现有流程，避免多层表单同时占用焦点。
    switch (action) {
      case 'network':
        await widget.player.network();
      case 'local':
        await widget.player.local();
      case 'invite':
        await widget.onInvite();
      case 'choose-source':
        await chooseSource();
      case 'ready':
        widget.onPeerReady?.call();
      case 'end':
        widget.onEndPreview?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    return Panel(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          key: const Key('watch-control-bar'),
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DS.space8),
                  child: VerticalDivider(width: 1, color: p.line),
                ),
              Expanded(
                child: TextButton(
                  key: Key('watch-control-$i'),
                  style: TextButton.styleFrom(
                    // 单行视觉高度为 36dp，大字号仍可自然撑开。
                    minimumSize: const Size(0, DS.buttonHeight + DS.space4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DS.space4,
                      vertical: DS.space8,
                    ),
                    backgroundColor: active == i ? p.tint : null,
                    foregroundColor: active == i ? p.primary : p.ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DS.radiusMedium),
                    ),
                  ),
                  onPressed: () => _open(i),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DSIcon(
                        const ['link', 'users-round', 'volume-2'][i],
                        size: DS.iconSmall,
                        color: active == i ? p.primary : p.ink,
                      ),
                      const SizedBox(width: DS.space8),
                      Flexible(
                        child: Text(
                          const ['片源', '同看', '音频'][i],
                          maxLines: 1,
                          style: DS.label,
                        ),
                      ),
                      const SizedBox(width: DS.space4),
                      DSIcon(
                        active == i ? 'chevron-up' : 'chevron-down',
                        size: DS.chevronSize,
                        color: active == i ? p.primary : p.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _source(BuildContext c) => DSSheetContent(
    title: '选择视频',
    closeLabel: '关闭片源选择',
    subtitle: widget.player.session.source == null
        ? '当前未选择视频'
        : '当前片源：${widget.player.session.source!.title}',
    children: [
      for (final line in widget.lines)
        MenuRow(
          line.code == widget.lineCode ? 'check' : 'link',
          line.name,
          subtitle: '${line.episodes.length} 集',
          onTap: () => Navigator.pop(c, 'line:${line.code}'),
        ),
      MenuRow(
        'link',
        '视频地址',
        subtitle: '输入 MP4 或 HLS 链接',
        onTap: () => Navigator.pop(c, 'network'),
      ),
      const Divider(),
      MenuRow(
        'list-video',
        '本地视频',
        subtitle: '从设备选择文件',
        onTap: () => Navigator.pop(c, 'local'),
      ),
    ],
  );

  Widget _together(BuildContext c) {
    final p = DSPalette.of(c);
    final needsSource =
        widget.player.session.source == null && !widget.library.preview;
    final status = widget.shared
        ? widget.library.scenario == 'normal'
              ? '同步状态预览'
              : widget.status
        : '双方准备好后，开始同步观看';
    return DSSheetContent(
      title: '私密同看',
      closeLabel: '关闭同看设置',
      children: [
        const SizedBox(height: DS.space12),
        Row(
          children: [
            Semantics(
              label: widget.shared ? '你和小满 · 预览' : '我，等待好友加入',
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MountainAvatar(
                      initial: widget.library.initial,
                      size: DS.avatarMedium,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DS.space4,
                      ),
                      child: DSIcon(
                        'link',
                        size: DS.chevronSize,
                        color: p.muted,
                      ),
                    ),
                    if (widget.shared)
                      const MountainAvatar(initial: '满', size: DS.avatarMedium)
                    else
                      CircleAvatar(
                        radius: DS.avatarMedium / 2,
                        backgroundColor: p.subtle,
                        child: DSIcon(
                          'user-round',
                          color: p.muted,
                          size: DS.navigationIcon,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: DS.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.shared ? '你和小满' : '等待好友加入', style: DS.title),
                  const SizedBox(height: DS.space4),
                  Text(status, style: DS.smallFor(c)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: DS.space24),
        FilledButton.icon(
          key: const Key('watch-together-primary'),
          onPressed: () =>
              Navigator.pop(c, needsSource ? 'choose-source' : 'invite'),
          icon: DSIcon(
            needsSource ? 'play' : 'link',
            size: DS.iconSmall,
            color: p.onPrimary,
          ),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: DS.space12),
            child: Text(
              needsSource ? '先选择视频' : '邀请好友一起看',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: DS.space12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DSIcon('lock-keyhole', size: DS.chevronSize, color: p.muted),
            const SizedBox(width: DS.space4),
            Flexible(
              child: Text(
                '仅房间成员可见',
                style: DS.smallFor(c),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        if (needsSource) ...[
          const SizedBox(height: DS.space4),
          Text(
            '选好视频后，即可创建私密邀请',
            style: DS.smallFor(c),
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.library.preview) ...[
          const SizedBox(height: DS.space4),
          Text(
            '界面预览 · 不会建立真实连接',
            style: DS.smallFor(c),
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.onPeerReady != null || widget.onEndPreview != null) ...[
          const SizedBox(height: DS.space8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: DS.space8,
            children: [
              if (widget.onPeerReady != null)
                TextButton(
                  onPressed: () => Navigator.pop(c, 'ready'),
                  child: const Text('模拟好友恢复 · 保持暂停'),
                ),
              if (widget.onEndPreview != null)
                TextButton(
                  onPressed: () => Navigator.pop(c, 'end'),
                  child: const Text('结束同看预览'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _audio(BuildContext c) => StatefulBuilder(
    builder: (c, update) => DSSheetContent(
      title: '音频设置',
      closeLabel: '关闭音频设置',
      subtitle: '调整立即生效',
      children: [
        Row(
          children: [
            const DSIcon('volume-2', size: DS.navigationIcon),
            const SizedBox(width: DS.space12),
            const Expanded(child: Text('影片音量', style: DS.title)),
            Text(
              '${(widget.library.movieVolume * 100).round()}%',
              style: DS.label.copyWith(color: DSPalette.of(c).primary),
            ),
          ],
        ),
        Slider(
          key: const Key('watch-volume'),
          value: widget.library.movieVolume,
          semanticFormatterCallback: (v) => '${(v * 100).round()}%',
          onChanged: (v) {
            update(() => widget.library.movieVolume = v);
            widget.player.session.core.mediaPlayer?.setVolume(v * 100);
          },
        ),
        const Divider(),
        MenuRow(
          'mic-off',
          '麦克风',
          subtitle: widget.library.scenario == 'mic-denied'
              ? '权限被拒，仍可观看和文字交流'
              : widget.library.preview
              ? '预览中保持关闭 · 进入同看房间后可开启'
              : '请在同看房间内开启语音',
          trailing: const Switch(value: false, onChanged: null),
        ),
      ],
    ),
  );
}

String _qualityName(VideoTrack track) => track.id == 'auto'
    ? '默认'
    : track.h != null && track.h! > 0
    ? '${track.h}P'
    : track.title ?? '视频 ${track.id}';

/// 输入区上方的轻量状态栏，大字号时横向滚动，保持入口在同一行。
class WatchComposerBar extends StatelessWidget {
  const WatchComposerBar({
    super.key,
    required this.player,
    required this.shared,
    required this.onTogether,
    required this.onQuality,
    this.episode,
    this.onEpisode,
  });
  final PlayerPresentation player;
  final bool shared;
  final int? episode;
  final VoidCallback onTogether, onQuality;
  final VoidCallback? onEpisode;

  @override
  Widget build(BuildContext context) {
    final current = player.session.core.mediaPlayer?.state.track.video;
    final quality = player.session.source == null || current == null
        ? '清晰度'
        : '清晰度 · ${_qualityName(current)}';
    return SingleChildScrollView(
      key: const Key('watch-composer-status'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: DS.space4),
      child: Row(
        children: [
          _option(context, 'users-round', shared ? '同看预览' : '个人观看', onTogether),
          if (episode != null)
            _option(context, 'list-video', '选集 · $episode', onEpisode),
          _option(context, 'sliders-horizontal', quality, onQuality),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    String icon,
    String label,
    VoidCallback? action,
  ) => TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      foregroundColor: DSPalette.of(context).muted,
      minimumSize: const Size(0, DS.buttonHeight + DS.space4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(
        horizontal: DS.space8,
        vertical: DS.space8,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DSIcon(icon, size: DS.iconSmall, color: DSPalette.of(context).muted),
        const SizedBox(width: DS.space4),
        Text(label, style: DS.label),
        const SizedBox(width: DS.space4),
        DSIcon(
          'chevron-down',
          size: DS.chevronSize,
          color: DSPalette.of(context).muted,
        ),
      ],
    ),
  );
}

class _WatchQualitySheet extends StatefulWidget {
  const _WatchQualitySheet({required this.player});
  final PlayerPresentation player;
  @override
  State<_WatchQualitySheet> createState() => _WatchQualitySheetState();
}

class _WatchQualitySheetState extends State<_WatchQualitySheet> {
  bool busy = false;
  String? error;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.player.session,
    builder: (context, _) {
      final session = widget.player.session;
      final player = session.core.mediaPlayer;
      // 只列出当前片源实际报告的视频轨道，排除禁用视频和封面图片。
      final tracks =
          player?.state.tracks.video
              .where(
                (t) => t.id != 'no' && t.image != true && t.albumart != true,
              )
              .toList() ??
          <VideoTrack>[];
      final available = tracks.any((t) => t.id != 'auto');
      return DSSheetContent(
        title: '清晰度',
        closeLabel: '关闭清晰度选择',
        subtitle: session.source == null
            ? '先选择视频，再查看可用清晰度'
            : kIsWeb
            ? '当前网页不支持切换清晰度'
            : !available
            ? '当前片源未提供可选画质'
            : '可选画质由视频来源提供',
        children: [
          if (session.source == null)
            MenuRow(
              'link',
              '选择视频',
              onTap: () => Navigator.pop(context, 'choose-source'),
            ),
          if (available && !kIsWeb)
            for (final track in tracks)
              MenuRow(
                'film-reel',
                _qualityName(track),
                trailing: player!.state.track.video.id == track.id
                    ? DSIcon(
                        'check',
                        size: DS.iconSmall,
                        color: DSPalette.of(context).primary,
                      )
                    : const SizedBox.shrink(),
                onTap: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await player.setVideoTrack(track);
                          if (mounted) Navigator.pop(context);
                        } catch (_) {
                          if (mounted)
                            setState(() {
                              busy = false;
                              error = '清晰度切换失败，请重试';
                            });
                        }
                      },
              ),
          if (error != null)
            Text(
              error!,
              style: DS.small.copyWith(color: DSPalette.of(context).error),
            ),
        ],
      );
    },
  );
}

class WatchCover extends StatelessWidget {
  const WatchCover({super.key, required this.cover, required this.onChoose});
  final String cover;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          cover,
          cacheWidth: 1080,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(color: DSPalette.media),
        ),
        ColoredBox(color: DSPalette.media.withValues(alpha: .15)),
        Center(
          child: IconButton.outlined(
            tooltip: '选择视频，开始观看',
            onPressed: onChoose,
            style: IconButton.styleFrom(
              minimumSize: const Size(DS.avatarLarge, DS.avatarLarge),
              backgroundColor: DSPalette.media.withValues(alpha: .4),
              side: BorderSide(color: DSPalette.onMedia.withValues(alpha: .8)),
            ),
            icon: const DSIcon(
              'play',
              size: DS.space24,
              color: DSPalette.onMedia,
            ),
          ),
        ),
        Positioned(
          left: DS.space12,
          bottom: DS.space12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DSPalette.media.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(DS.radiusSmall),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DS.space8,
                vertical: DS.space4,
              ),
              child: Text(
                '封面预览',
                style: DS.label.copyWith(color: DSPalette.onMedia),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
