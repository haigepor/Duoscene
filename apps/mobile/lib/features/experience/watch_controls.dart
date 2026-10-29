import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/media_provider.dart';
import '../catalog/posters.dart';
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
  const WatchCover({
    super.key,
    required this.cover,
    required this.onChoose,
    this.film,
    this.resolving = false,
    this.error,
    this.onRetry,
    this.episode = 1,
    this.title,
    this.subtitle,
    this.onBack,
    this.onMore,
  });
  final String cover;
  final VoidCallback onChoose;
  final Film? film;
  final bool resolving;
  final String? error;
  final VoidCallback? onRetry;
  final int episode;
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    final f = film;
    final hasFilm = f != null;

    // 背景底图层：若有影片海报则使用海报 + 电影级高斯模糊 + 径向暗角渐变；否则使用本地封面
    Widget backdrop;
    if (hasFilm && (f.remote || f.image.isNotEmpty)) {
      backdrop = Stack(
        fit: StackFit.expand,
        children: [
          FilmArtwork(
            f,
            asset: f.id == 'mountains'
                ? '${DS.media}media-mountains-landscape.png'
                : (f.image.isNotEmpty ? f.image : cover),
            cacheWidth: 1080,
          ),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: const SizedBox.expand(),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.15,
                colors: [
                  DSPalette.media.withValues(alpha: .60),
                  DSPalette.media.withValues(alpha: .94),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      backdrop = Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            cover,
            cacheWidth: 1080,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(color: DSPalette.media),
          ),
          ColoredBox(color: DSPalette.media.withValues(alpha: .65)),
        ],
      );
    }

    Widget content;
    if (resolving) {
      // 正在解析状态：微光环形加载卡 + 标题 + 剧集胶囊标签 + 氛围微提示
      content = Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DS.space16,
              vertical: DS.space8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .08),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .18),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: p.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '正在解析片源…',
                  style: TextStyle(
                    color: DSPalette.onMedia,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .4,
                  ),
                ),
                if (hasFilm) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: .12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .14),
                      ),
                    ),
                    child: Text(
                      f.episodes > 1 ? '${f.title} · 第 $episode 集' : f.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: DSPalette.onMedia.withValues(alpha: .85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '正在寻找最优线路与画质…',
                  style: TextStyle(
                    color: DSPalette.onMedia.withValues(alpha: .48),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (error != null) {
      // 解析失败状态：警告图标 + 错误说明 + 胶囊操作按钮
      content = Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DS.space16,
              vertical: DS.space8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.amber.withValues(alpha: .15),
                    border: Border.all(
                      color: p.amber.withValues(alpha: .35),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: DSIcon(
                      'circle-alert',
                      size: 22,
                      color: p.amber,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '片源解析未完成',
                  style: TextStyle(
                    color: DSPalette.onMedia,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: DSPalette.onMedia.withValues(alpha: .7),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .28),
                        ),
                      ),
                      onPressed: onChoose,
                      icon: const DSIcon(
                        'sliders-horizontal',
                        size: 14,
                        color: DSPalette.onMedia,
                      ),
                      label: const Text(
                        '切换线路',
                        style: TextStyle(
                          color: DSPalette.onMedia,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (onRetry != null)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                        ),
                        onPressed: onRetry,
                        icon: const DSIcon(
                          'refresh-cw',
                          size: 14,
                          color: DSPalette.onMedia,
                        ),
                        label: const Text(
                          '重试解析',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // 空闲/手动选择状态：支持测试检索 tooltip，并以毛玻璃圆环风格呈现
      content = Center(
        child: IconButton.outlined(
          tooltip: '选择视频，开始观看',
          onPressed: onChoose,
          style: IconButton.styleFrom(
            minimumSize: const Size(DS.avatarLarge, DS.avatarLarge),
            backgroundColor: DSPalette.media.withValues(alpha: .5),
            side: BorderSide(
              color: DSPalette.onMedia.withValues(alpha: .8),
              width: 1.5,
            ),
          ),
          icon: const DSIcon(
            'play',
            size: DS.space24,
            color: DSPalette.onMedia,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        backdrop,
        content,
        if (onBack != null || title != null || onMore != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xCC000000),
                    Color(0x66000000),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      if (onBack != null)
                        IconButton(
                          tooltip: '返回',
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: onBack,
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 48),
                          ),
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title ?? f?.title ?? '',
                              key: const Key('watch-header-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    offset: Offset(0, 1),
                                    blurRadius: 3,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 11,
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (onMore != null)
                        IconButton(
                          tooltip: '播放器更多功能',
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: onMore,
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
