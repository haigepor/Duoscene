import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/illustrations.dart';
import '../catalog/library_state.dart';
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
        const DSIntro('听见故事，也听见彼此', '好的声音，让一起看更有氛围。', artwork: 'audio-glass'),
        const SizedBox(height: DS.space16),
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
      padding: const EdgeInsets.fromLTRB(
        DS.pageInset,
        DS.space8,
        DS.pageInset,
        DS.space16,
      ),
      children: [
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('只属于你们的交流', style: DS.secondarySection),
                    const SizedBox(height: DS.space4),
                    Text('仅房间成员可见，私聊记录保存在服务端。', style: DS.smallFor(context)),
                  ],
                ),
              ),
              const SizedBox(width: DS.space8),
              const DSIllustration('privacy-glass', width: 56, height: 56),
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
                compact: true,
                subtitle: '保存你独自观看的位置 · 本机',
                onTap: () => openPage(
                  context,
                  HistoryPage(
                    secondary: true,
                    library: library,
                    onBrowse: () =>
                        Navigator.popUntil(context, (r) => r.isFirst),
                    sharedScope: false,
                  ),
                ),
              ),
              const Divider(),
              MenuRow(
                'users-round',
                '共同观看进度',
                compact: true,
                subtitle: '保存你与好友一起看的位置 · 本机',
                onTap: () => openPage(
                  context,
                  HistoryPage(
                    secondary: true,
                    library: library,
                    onBrowse: () =>
                        Navigator.popUntil(context, (r) => r.isFirst),
                    sharedScope: true,
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
                compact: true,
                subtitle: '仅清理当前账户在本机保存的记录。',
                trailing: DSIcon(
                  'trash-2',
                  size: DS.iconSmall,
                  color: DSPalette.of(context).muted,
                ),
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
                compact: true,
                subtitle: '不会清除播放器或登录数据',
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
  Widget build(BuildContext context) {
    final p = DSPalette.of(context);
    final username = library.preview
        ? 'zhixia · 示例'
        : library.session?.user?.username;
    return PageFrame(
      title: '账户信息',
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              DS.pageInset,
              DS.space8,
              DS.pageInset,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact =
                          constraints.maxWidth < 340 ||
                          MediaQuery.textScalerOf(context).scale(14) > 22;
                      return Row(
                        children: [
                          Container(
                            width: DS.avatarLarge,
                            height: DS.avatarLarge,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                DS.radiusMedium,
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  p.primary.withValues(alpha: .5),
                                  p.primary,
                                ],
                              ),
                            ),
                            child: Text(
                              library.initial,
                              style: TextStyle(
                                fontSize: DS.displaySize,
                                color: p.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: DS.space12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(library.displayName, style: DS.heading),
                                const SizedBox(height: DS.space8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: DS.space8,
                                    vertical: DS.space2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.tint,
                                    borderRadius: BorderRadius.circular(
                                      DS.radiusSmall,
                                    ),
                                  ),
                                  child: Text(
                                    library.preview
                                        ? '预览身份'
                                        : library.isGuest
                                        ? '本机访客'
                                        : '私有账户',
                                    style: DS.label.copyWith(color: p.onTint),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: DS.space8),
                          DSIllustration(
                            'account-identity-glass',
                            width: compact ? 64 : 112,
                            height: compact ? 88 : 128,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: DS.space12),
                  Stack(
                    children: [
                      Panel(
                        padding: const EdgeInsets.all(DS.space16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              library.isGuest ? '本机身份' : '登录账户',
                              style: DS.smallFor(context),
                            ),
                            const SizedBox(height: DS.space4),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    username ??
                                        (library.isGuest ? '本机访客' : '未登录'),
                                    key: const Key('account-username'),
                                    style: DS.body.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                IconTap(
                                  'copy',
                                  '复制账户名',
                                  username == null || library.preview
                                      ? null
                                      : () async {
                                          try {
                                            await Clipboard.setData(
                                              ClipboardData(text: username),
                                            );
                                            if (context.mounted)
                                              tell(context, '账户名已复制');
                                          } catch (_) {
                                            if (context.mounted)
                                              tell(context, '无法复制，请长按账户名手动复制。');
                                          }
                                        },
                                  color: p.muted,
                                ),
                              ],
                            ),
                            const Divider(height: DS.space24),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final large =
                                    MediaQuery.textScalerOf(context).scale(14) >
                                    22;
                                final width = large
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - DS.space24) / 2;
                                return Wrap(
                                  spacing: DS.space24,
                                  runSpacing: DS.space12,
                                  children: [
                                    SizedBox(
                                      width: width,
                                      child: _info(
                                        context,
                                        '显示名',
                                        library.displayName,
                                      ),
                                    ),
                                    SizedBox(
                                      width: width,
                                      child: _info(
                                        context,
                                        '账户类型',
                                        library.preview
                                            ? '预览身份'
                                            : library.isGuest
                                            ? '本机访客'
                                            : '个人账户',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 1,
                        left: 1,
                        child: Container(
                          width: DS.space4,
                          height: DS.space16,
                          decoration: BoxDecoration(
                            color: p.primary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(DS.panelRadius),
                              bottomRight: Radius.circular(DS.radiusSmall),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DS.space24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: DS.space8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DSIcon(
                          'lock-keyhole',
                          size: DS.navigationIcon,
                          color: p.muted,
                        ),
                        const SizedBox(width: DS.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                library.isGuest ? '本机记录' : '账户安全',
                                style: DS.secondarySection,
                              ),
                              const SizedBox(height: DS.space4),
                              Text(
                                library.isGuest
                                    ? '收藏与播放记录仅保存在当前设备。'
                                    : '忘记密码时，可在登录页使用恢复码重设。',
                                style: DS.smallFor(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DS.space24),
                  if (!library.isGuest)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.muted,
                        side: BorderSide(color: p.line),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => logout(context, library),
                      icon: DSIcon(
                        'log-out',
                        size: DS.iconSmall,
                        color: p.muted,
                      ),
                      label: const Text('退出登录'),
                    ),
                ],
              ),
            ),
          ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: DS.space24),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: .25,
                    child: Brand(size: DS.sectionSize, ringsFirst: true),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(BuildContext context, String name, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: DS.smallFor(context)),
      const SizedBox(height: DS.space4),
      Text(value, style: DS.body),
    ],
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
        const DSIntro(
          '遇到问题，先看看这里',
          '常见问题与使用方法。',
          artwork: 'conversation-glass',
        ),
        const SizedBox(height: DS.space24),
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
        const SizedBox(height: DS.space24),
        const Center(child: Brand(size: DS.brandSize + DS.space8)),
        const SizedBox(height: DS.space16),
        const Center(
          child: DSIllustration('duo-tickets-glass', width: 160, height: 120),
        ),
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
