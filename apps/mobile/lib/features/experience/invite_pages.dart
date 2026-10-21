import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/illustrations.dart';
import '../catalog/catalog.dart';
import '../catalog/library_state.dart';
import '../catalog/posters.dart';
import '../rooms/room_repository.dart';
import '../realtime/room_watch_page.dart';

Future<void> showInvite(
  BuildContext context, {
  required Film film,
  required LibraryState library,
  int episode = 1,
  int position = 0,
}) => showDSSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => InviteSheet(
    film: film,
    library: library,
    episode: episode,
    position: position,
  ),
);

class InviteSheet extends StatefulWidget {
  const InviteSheet({
    super.key,
    required this.film,
    required this.library,
    this.episode = 1,
    this.position = 0,
  });
  final Film film;
  final LibraryState library;
  final int episode, position;
  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  Invite? invite;
  Room? room;
  bool busy = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    if (widget.library.scenario == 'invite-busy') {
      busy = true;
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => busy = false);
      });
    }
  }

  // 倒计时只在显示的分钟数变化或到期时刷新，不再每秒重建整张弹层。
  void _scheduleExpiry() {
    timer?.cancel();
    final value = invite;
    if (value == null || value.expired) return;
    final remaining = value.expiresAt.difference(DateTime.now());
    final next = Duration(seconds: remaining.inSeconds % 60 + 1);
    timer = Timer(next < remaining ? next : remaining, () {
      if (!mounted) return;
      setState(() {});
      _scheduleExpiry();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> generate({bool share = false}) async {
    if (busy) return;
    if (widget.library.preview) {
      tell(context, '预览邀请不会创建房间或生成真实邀请码。请登录后使用真实邀请。');
      return;
    }
    final session = widget.library.session;
    if (session?.user == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rooms = RoomRepository(session!);
      room ??= await rooms.create(widget.film.title);
      if (invite == null || invite!.expired)
        invite = await rooms.invite(room!.id);
      _scheduleExpiry();
      final text =
          'Duoscene 私密观影邀请\n${invite!.token}\n15 分钟有效，仅限使用一次。加入后等待双方准备。';
      if (share) {
        try {
          await const MethodChannel('duoscene/player')
              .invokeMethod<void>('shareText', {'text': text});
        } on MissingPluginException {
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) tell(context, '此平台已复制邀请，请手动分享。');
        }
      } else {
        await Clipboard.setData(ClipboardData(text: invite!.token));
        if (mounted) tell(context, '一次性邀请已复制');
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired =
        invite?.expired == true ||
        widget.library.scenario == 'invite-expired-sender';
    final p = DSPalette.of(context);
    return DSSheetContent(
      title: '邀请好友一起看',
      closeLabel: '关闭邀请',
      subtitle: '把这一刻，分享给想一起看的人。',
      children: [
        Panel(
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(DS.radiusSmall),
                child: Image.asset(
                  homeArtwork(widget.film),
                  width: 64,
                  height: 48,
                  cacheWidth: 192,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: DS.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.film.title, style: DS.title),
                    const SizedBox(height: DS.space4),
                    Text(
                      '${widget.film.episodes == 1 ? '完整正片' : '第 ${widget.episode} 集'} · 从 ${widget.position ~/ 60}:${(widget.position % 60).toString().padLeft(2, '0')} 开始',
                      style: DS.smallFor(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DS.space12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.subtle,
            borderRadius: BorderRadius.circular(DS.radiusMedium),
          ),
          child: Padding(
            padding: const EdgeInsets.all(DS.space12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          MountainAvatar(
                            initial: widget.library.initial,
                            size: DS.avatarSmall,
                          ),
                          const SizedBox(height: DS.space4),
                          const Text('我', style: DS.label),
                        ],
                      ),
                    ),
                    const DSIllustration(
                      'duo-tickets-glass',
                      width: 64,
                      height: 48,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: DS.avatarSmall / 2,
                            backgroundColor: p.panel,
                            child: DSIcon(
                              'user-round',
                              size: DS.iconSmall,
                              color: p.muted,
                            ),
                          ),
                          const SizedBox(height: DS.space4),
                          const Text('等待好友', style: DS.label),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DS.space8),
                Text(
                  '好友加入后，双方准备好再开始',
                  textAlign: TextAlign.center,
                  style: DS.smallFor(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: DS.space8),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DS.touchTarget),
          child: Row(
            children: [
              DSIcon('clock-3', size: DS.iconSmall, color: p.muted),
              const SizedBox(width: DS.space8),
              Expanded(
                child: Text(
                  expired
                      ? '邀请已过期，请重新生成'
                      : invite != null
                      ? '剩余 ${invite!.expiresAt.difference(DateTime.now()).inMinutes + 1} 分钟 · 仅限一次'
                      : '一次性邀请 · 15 分钟有效',
                  style: DS.smallFor(context),
                ),
              ),
              if (invite != null && !expired)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: p.muted),
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            await RoomRepository(widget.library.session!)
                                .revoke(room!.id, invite!.id);
                            timer?.cancel();
                            if (mounted) setState(() => invite = null);
                          } catch (e) {
                            if (mounted) tell(context, friendlyError(e));
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: const Text('撤销这份邀请'),
                ),
            ],
          ),
        ),
        if (error != null) ErrorNotice(error!),
        const SizedBox(height: DS.space12),
        FilledButton.icon(
          onPressed: busy ? null : () => generate(share: true),
          icon: DSIcon('share-2', size: DS.iconSmall, color: p.onPrimary),
          label: Text(
            busy
                ? '正在生成…'
                : expired
                ? '重新生成并分享'
                : '分享观影邀请',
          ),
        ),
        const SizedBox(height: DS.space8),
        LayoutBuilder(
          builder: (context, constraints) {
            final copy = OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: p.ink,
                side: BorderSide(color: p.line),
              ),
              onPressed: busy ? null : () => generate(),
              icon: DSIcon('copy', size: DS.iconSmall, color: p.muted),
              label: const Text('复制邀请'),
            );
            if (room == null || widget.library.preview) return copy;
            final enter = FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: p.tint,
                foregroundColor: p.onTint,
              ),
              onPressed: busy
                  ? null
                  : () => openPage(
                      context,
                      RoomWatchPage(room: room!, auth: widget.library.session!),
                    ),
              icon: DSIcon('play', size: DS.iconSmall, color: p.onTint),
              label: const Text('进入同看房间'),
            );
            // 大字号需要完整按钮宽度，不能为压缩弹层牺牲文字或触控区。
            final stacked =
                constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(DS.bodySize) > 18;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copy,
                  const SizedBox(height: DS.space8),
                  enter,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: copy),
                const SizedBox(width: DS.space8),
                Expanded(child: enter),
              ],
            );
          },
        ),
        const SizedBox(height: DS.space12),
        Text(
          '仅房间成员可见 · 加入后选择双方可访问的视频',
          textAlign: TextAlign.center,
          style: DS.smallFor(context),
        ),
        if (widget.library.preview)
          const PreviewLabel(text: '预览 · 不生成可分享的真实邀请'),
      ],
    );
  }
}

class ReceivedInvitePage extends StatefulWidget {
  const ReceivedInvitePage({
    super.key,
    required this.library,
    this.initialToken = '',
  });
  final LibraryState library;
  final String initialToken;
  @override
  State<ReceivedInvitePage> createState() => _ReceivedInvitePageState();
}

class _ReceivedInvitePageState extends State<ReceivedInvitePage> {
  late final token = TextEditingController(text: widget.initialToken);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Future<void> join() async {
    if (busy) return;
    if (widget.library.preview) {
      tell(context, '预览：已准备加入，尚未同步。实际加入需登录并使用真实邀请码。');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token.text.trim())) {
      setState(() => error = '请粘贴完整的 43 位邀请码');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final room = await RoomRepository(widget.library.session!)
          .join(token.text);
      if (mounted) {
        tell(context, '已加入房间，等待双方准备。');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                RoomWatchPage(room: room, auth: widget.library.session!),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.library.preview;
    final state = widget.library.scenario;
    final blocked = [
      'invite-expired-receiver',
      'room-full',
      'room-closed',
      'invite-revoked',
    ].contains(state);
    return PageFrame(
      title: '观影邀请',
      child: ListView(
        padding: const EdgeInsets.all(DS.pageInset),
        children: [
          const DSIntro(
            '另一席，为你留着。',
            '粘贴完整邀请码，加入好友的房间。',
            artwork: 'duo-tickets-glass',
          ),
          const SizedBox(height: DS.space24),
          const Text('邀请码', style: DS.secondarySection),
          const SizedBox(height: DS.space12),
          if (!preview)
            TextField(
              key: const Key('invite-token'),
              controller: token,
              minLines: 3,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: '粘贴完整的 43 位邀请码'),
            )
          else
            const Panel(child: Text('预览身份不使用真实邀请码', style: DS.small)),
          const SizedBox(height: DS.space12),
          Text('加入前无法查询发送者和影片，请向邀请人核对。', style: DS.smallFor(context)),
          if (error != null) ErrorNotice(error!),
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(top: DS.space16),
              child: Text(
                {
                  'invite-expired-receiver': '邀请已过期，请联系邀请人重新发送。',
                  'room-full': '房间已满，仅限两位成员。',
                  'room-closed': '房间已关闭，请向好友索取新的邀请。',
                  'invite-revoked': '邀请已被撤销，请联系邀请人。',
                }[state]!,
                style: TextStyle(color: DSPalette.of(context).error),
              ),
            ),
          const SizedBox(height: DS.space24),
          FilledButton(
            onPressed: busy || blocked ? null : join,
            child: Text(busy ? '正在加入…' : '加入并准备'),
          ),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('稍后再说'),
          ),
          const SizedBox(height: DS.space16),
          Text(
            '一次性邀请 · 15 分钟有效\n加入后双方准备好再开始，麦克风默认关闭。',
            textAlign: TextAlign.center,
            style: DS.smallFor(context),
          ),
          if (preview) const PreviewLabel(text: '邀请接收界面预览 · 无真实邀请码'),
        ],
      ),
    );
  }
}
