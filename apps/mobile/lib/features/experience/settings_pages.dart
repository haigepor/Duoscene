import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../catalog/library_state.dart';
import 'experience_player.dart';
import '../catalog/collection_pages.dart';
import '../playback/player_page.dart';

class AudioSettingsPage extends StatefulWidget {
  const AudioSettingsPage({super.key, required this.library, this.player});
  final LibraryState library;
  final PlayerPresentation? player;
  @override
  State<AudioSettingsPage> createState() => _AudioSettingsPageState();
}

class _AudioSettingsPageState extends State<AudioSettingsPage> {
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '播放与音频',
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _volume('影片音量', widget.library.movieVolume, (v) {
          setState(() => widget.library.movieVolume = v);
          widget.player?.session.core.mediaPlayer?.setVolume(v * 100);
        }, enabled: true),
        const SizedBox(height: 12),
        _volume(
          '语音音量',
          widget.library.voiceVolume,
          (v) => setState(() => widget.library.voiceVolume = v),
          enabled: widget.library.preview,
          note: widget.library.preview ? '仅调整本机听到的声音 · 预览' : '请在同看房间的语音设置中调整',
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              MenuRow(
                'mic-off',
                '麦克风',
                subtitle: widget.library.scenario == 'mic-denied'
                    ? '权限被拒，仍可观看和文字交流'
                    : '默认关闭 · 在同看房间内开启',
                trailing: Switch(
                  value: false,
                  onChanged: widget.library.preview
                      ? (_) => tell(context, '预览：麦克风权限被拒，仍可观看和发送文字。')
                      : null,
                ),
              ),
              const Divider(),
              const MenuRow(
                'message-circle',
                '不开麦，也能正常观看和发消息',
                trailing: SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (widget.player != null)
          MenuRow(
            'sliders-horizontal',
            '播放器高级设置',
            subtitle: '保留 Playra 全部功能',
            onTap: widget.player!.settings,
          )
        else
          MenuRow(
            'play',
            '打开播放器',
            subtitle: '载入自己的 MP4 / HLS / 本地视频',
            onTap: () =>
                openPage(context, ExperiencePlayer(library: widget.library)),
          ),
      ],
    ),
  );
  Widget _volume(
    String title,
    double value,
    ValueChanged<double> changed, {
    required bool enabled,
    String? note,
  }) => Panel(
    child: Column(
      children: [
        Row(
          children: [
            const DSIcon('volume-2', size: DS.navigationIcon),
            const SizedBox(width: DS.space12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: DS.secondarySectionSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(
                color: DSPalette.of(context).primary,
                fontSize: DS.secondarySectionSize,
              ),
            ),
          ],
        ),
        const SizedBox(height: DS.space8),
        Slider(
          value: value,
          onChanged: enabled ? changed : null,
          semanticFormatterCallback: (v) => '${(v * 100).round()}%',
        ),
        if (note != null) Text(note, style: DS.smallFor(context)),
      ],
    ),
  );
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key, required this.library});
  final LibraryState library;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '隐私与记录',
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Panel(
          child: Row(
            children: [
              DSIcon(
                'shield-check',
                size: 28,
                color: DSPalette.of(context).primary,
              ),
              const SizedBox(width: DS.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '只属于你们的交流',
                      style: const TextStyle(
                        fontSize: DS.secondarySectionSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('交流范围仅限房间成员。私聊记录保存在服务端。', style: DS.smallFor(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('观看记录', style: DS.secondarySection),
              MenuRow(
                'play',
                '个人观看进度',
                subtitle: '保存你独自观看的位置 · 本机',
                onTap: () => openPage(
                  context,
                  PageFrame(
                    title: '个人观看进度',
                    child: HistoryPage(
                      library: library,
                      onBrowse: () =>
                          Navigator.popUntil(context, (r) => r.isFirst),
                      sharedScope: false,
                    ),
                  ),
                ),
              ),
              const Divider(),
              MenuRow(
                'users-round',
                '共同观看进度',
                subtitle: '保存你与好友一起看的位置 · 本机',
                onTap: () => openPage(
                  context,
                  PageFrame(
                    title: '共同观看进度',
                    child: HistoryPage(
                      library: library,
                      onBrowse: () =>
                          Navigator.popUntil(context, (r) => r.isFirst),
                      sharedScope: true,
                    ),
                  ),
                ),
              ),
              const Divider(),
              Text('个人进度与共同进度分别保存。', style: DS.smallFor(context)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('记录与缓存', style: DS.secondarySection),
              MenuRow(
                'history',
                '清理我的本机观看记录',
                subtitle: '仅清理当前账户在本机保存的记录。',
                trailing: DSIcon('trash-2', color: DSPalette.of(context).muted),
                onTap: () async {
                  if (await confirm(
                    context,
                    '清理本机观看记录？',
                    '清理个人与共同的本机副本，不影响好友。',
                    action: '清理记录',
                  )) {
                    try {
                      await library.removeHistory(
                        library.history.map((e) => e.key).toSet(),
                      );
                      if (context.mounted) tell(context, '本机记录已清理');
                    } catch (_) {
                      if (context.mounted) tell(context, '本机存储写入失败，请重试。');
                    }
                  }
                },
              ),
              const Divider(),
              MenuRow(
                'notebook',
                '清理本机缓存',
                subtitle: '暂不可用 · 不会清除播放器或登录数据',
                trailing: Text('暂不可用', style: DS.smallFor(context)),
              ),
              const Divider(),
              Text('记录清理不影响好友记录；缓存仅属于本机。', style: DS.smallFor(context)),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> logout(BuildContext context, LibraryState library) async {
  if (!await confirm(context, '退出登录？', '退出将关闭当前页面，清除本机会话凭据。', action: '退出登录'))
    return;
  if (library.preview) {
    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
  } else {
    await library.session?.logout();
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.library});
  final LibraryState library;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '账户信息',
    bottom: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => logout(context, library),
        icon: const DSIcon('log-out'),
        label: const Text('退出登录'),
      ),
    ),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Panel(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DS.space8),
            child: Row(
              children: [
                MountainAvatar(initial: library.initial, size: DS.avatarMedium),
                const SizedBox(width: DS.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(library.displayName, style: DS.secondarySection),
                      const SizedBox(height: 8),
                      Text(
                        library.preview ? '界面预览 · 未登录' : '已登录',
                        style: TextStyle(color: DSPalette.of(context).primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              _info(context, '显示名', library.displayName),
              const Divider(),
              _info(
                context,
                '账户名',
                library.preview
                    ? 'zhixia · 示例'
                    : library.session?.user?.username ?? '未登录',
              ),
              const Divider(),
              _info(context, '账户类型', library.preview ? '预览身份' : '个人账户'),
              const Divider(height: 30),
              Text('账户名用于登录。忘记密码可在登录页使用恢复码重设。', style: DS.smallFor(context)),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _info(BuildContext context, String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DS.space8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: TextStyle(color: DSPalette.of(context).muted),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});
  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final expanded = <int>{0};
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '帮助与支持',
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        const Text(
          '让一起看，更顺畅。',
          style: TextStyle(
            fontSize: DS.secondaryTitleSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '遇到问题，先从这里找到答案。',
          style: TextStyle(color: DSPalette.of(context).muted),
        ),
        const SizedBox(height: 24),
        Panel(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              for (var i = 0; i < 4; i++)
                ExpansionTile(
                  initiallyExpanded: i == 0,
                  onExpansionChanged: (open) => setState(() {
                    if (open) {
                      expanded.add(i);
                    } else {
                      expanded.remove(i);
                    }
                  }),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  leading: DSIcon(
                    'circle-help',
                    size: DS.navigationIcon,
                    color: DSPalette.of(context).primary,
                  ),
                  trailing: AnimatedRotation(
                    turns: expanded.contains(i) ? .5 : 0,
                    duration: DSMotion.duration(context),
                    curve: DSMotion.curve,
                    child: DSIcon(
                      'chevron-down',
                      size: DS.chevronSize,
                      color: DSPalette.of(context).muted,
                    ),
                  ),
                  minTileHeight: DS.touchTarget,
                  title: Text(
                    ['为什么双方一起暂停？', '好友断线怎么办？', '不开麦可以一起看吗？', '邀请失效怎么办？'][i],
                    style: DS.menuLabel,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(46, 0, 12, 16),
                      child: Text(
                        [
                          '同看房间中，一方缓冲时会等待双方准备。手动暂停后需要主动点击播放。',
                          '房间会自动重连并恢复媒体与消息。断线后保持暂停，双方准备好再点击播放。',
                          '可以保持麦克风关闭。同步观看和文字私聊正常使用；语音需双方主动开启。',
                          '邀请一次性使用，15 分钟有效。过期或撤销后请邀请人重新生成；满员或关闭的房间无法加入。',
                        ][i],
                        style: DS.smallFor(context),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: MenuRow(
            'circle-help',
            '账户协助',
            subtitle: '忘记密码请在登录页使用恢复码重设。',
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('账户协助'),
                content: const Text(
                  '忘记密码请在登录页使用恢复码重设。旧的管理员账户若没有恢复码，请联系管理员协助。当前未配置公开客服渠道。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final version = _version();
  Future<String> _version() async {
    try {
      return await const MethodChannel('duoscene/player')
              .invokeMethod<String>('getAppVersion') ??
          '无法读取';
    } catch (_) {
      return '此平台暂无法读取应用版本';
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '关于 Duoscene',
    hero: true,
    child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * .1),
        const Center(child: Brand(size: DS.brandSize + DS.space8)),
        const SizedBox(height: DS.space16),
        const Text(
          '一部好片，独自沉浸，\n也可以一起。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: DS.secondarySectionSize, height: 1.8),
        ),
        const SizedBox(height: DS.space24),
        Panel(
          child: Column(
            children: [
              FutureBuilder<String>(
                future: version,
                builder: (_, s) => MenuRow(
                  'info',
                  '版本信息',
                  subtitle: s.data ?? '正在读取…',
                  onTap: () => tell(context, s.data ?? '正在读取…'),
                ),
              ),
              const Divider(),
              MenuRow(
                'shield-check',
                '开源许可',
                subtitle: 'Flutter、Playra / GPL v3、media-kit、Lucide、字体',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Duoscene',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.space24),
        Text(
          '把时间，留给喜欢的故事。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: DSPalette.of(context).muted,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}
