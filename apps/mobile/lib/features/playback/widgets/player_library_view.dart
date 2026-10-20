import 'package:flutter/material.dart';

import '../../../design/components.dart';
import '../../../design/tokens.dart';
import '../player_page.dart';

/// 没有媒体时显示选择入口，不绘制不能使用的进度条和黑色播放按钮。
class PlayerEmptySurface extends StatelessWidget {
  const PlayerEmptySurface({super.key, required this.player, this.cover});
  final PlayerPresentation player;
  final String? cover;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (cover != null)
        Image.asset(cover!, fit: BoxFit.cover, excludeFromSemantics: true),
      ColoredBox(
        color: cover == null
            ? DSPalette.media
            : Colors.black.withValues(alpha: .55),
      ),
      Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DSIcon('play', size: 28, color: DSPalette.onMedia),
              const SizedBox(height: 8),
              Text(
                cover == null ? '下一场，从这里开始' : '选择视频，开始观看',
                style: DS.title.copyWith(color: DSPalette.onMedia),
              ),
              const SizedBox(height: 4),
              const Text(
                '支持 MP4、HLS 与本地视频',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: player.network,
                    icon: DSIcon(
                      'link',
                      size: 16,
                      color: DSPalette.of(context).onPrimary,
                    ),
                    label: const Text('视频地址'),
                  ),
                  OutlinedButton.icon(
                    onPressed: player.local,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DSPalette.onMedia,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    icon: const DSIcon(
                      'list-video',
                      size: 16,
                      color: DSPalette.onMedia,
                    ),
                    label: const Text('本地视频'),
                  ),
                ],
              ),
              if (cover != null)
                const Text(
                  '封面预览 · 尚未载入视频',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: DS.captionSize,
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class PlayerQuickActions extends StatelessWidget {
  const PlayerQuickActions({super.key, required this.player});
  final PlayerPresentation player;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      ActionChip(
        label: Text('${player.session.core.playerSpeed.toStringAsFixed(2)}×'),
        onPressed: player.settings,
      ),
      ActionChip(label: const Text('画幅 / 字幕'), onPressed: player.settings),
      ActionChip(
        label: const Text('截图'),
        onPressed: player.session.source == null ? null : player.capture,
      ),
      ActionChip(
        label: Text('${player.session.screenshots.candidates.length} 张'),
        onPressed: player.screenshots,
      ),
      ActionChip(label: const Text('全部设置 ›'), onPressed: player.settings),
    ],
  );
}

/// 通用媒体入口与影片页使用同一配色、空态、快捷操作和原有播放会话。
class PlayerLibraryView extends StatelessWidget {
  const PlayerLibraryView({
    super.key,
    required this.player,
    required this.surface,
    required this.roomName,
  });
  final PlayerPresentation player;
  final Widget surface;
  final String roomName;
  @override
  Widget build(BuildContext context) => Forest(
    child: Column(
      children: [
        SizedBox(
          height: DS.toolbarHeight,
          child: Row(
            children: [
              IconTap('arrow-left', '返回', () => Navigator.maybePop(context)),
              const Expanded(child: Text('播放器', style: DS.toolbar)),
              IconTap('sliders-horizontal', '播放设置', player.settings),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: (c.maxWidth * 9 / 16).clamp(
              0,
              MediaQuery.sizeOf(context).height * .4,
            ),
            child: player.session.source == null
                ? PlayerEmptySurface(player: player)
                : surface,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(DS.pageInset),
            children: [
              Text(player.session.source?.title ?? '你的播放空间', style: DS.section),
              const SizedBox(height: 4),
              Text(roomName, style: DS.smallFor(context)),
              if (player.error != null)
                Text(
                  player.error!,
                  style: TextStyle(color: DSPalette.of(context).amber),
                ),
              if (player.session.notice != null)
                Text(
                  player.session.notice!,
                  style: TextStyle(color: DSPalette.of(context).amber),
                ),
              const SizedBox(height: 12),
              PlayerQuickActions(player: player),
              const Divider(height: 28),
              Row(
                children: [
                  const Expanded(child: Text('播放列表', style: DS.section)),
                  TextButton(
                    onPressed: player.network,
                    child: const Text('添加视频'),
                  ),
                ],
              ),
              if (player.session.playlist.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('添加视频后，可在这里连续观看。', style: DS.smallFor(context)),
                ),
              for (var i = 0; i < player.session.playlist.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: DSIcon(
                    i == player.session.playlistIndex ? 'play' : 'list-video',
                    color: DSPalette.of(context).primary,
                  ),
                  title: Text(
                    player.session.playlist[i].title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: i == player.session.playlistIndex,
                  onTap: () => player.session.setPlaylist(
                    player.session.playlist,
                    index: i,
                  ),
                ),
              if (player.session.source != null)
                TextButton.icon(
                  onPressed: player.local,
                  icon: const DSIcon('list-video', size: 16),
                  label: const Text('添加本地视频'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
