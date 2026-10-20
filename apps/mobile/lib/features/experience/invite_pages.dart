import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
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
}) => showModalBottomSheet<void>(
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
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && invite != null) setState(() {});
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(child: Text('邀请好友一起看', style: DS.heading)),
                IconTap('x', '关闭邀请', () => Navigator.pop(context)),
              ],
            ),
            Text(
              '把这一刻，分享给想一起看的人。',
              style: TextStyle(color: DSPalette.of(context).muted),
            ),
            const SizedBox(height: 20),
            Panel(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.asset(
                      widget.film.image,
                      width: 90,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.film.title,
                          style: const TextStyle(
                            fontSize: DS.sectionSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${widget.film.episodes == 1 ? '完整正片' : '第 ${widget.episode} 集'} · 从 ${widget.position ~/ 60}:${(widget.position % 60).toString().padLeft(2, '0')} 开始',
                          style: TextStyle(
                            color: DSPalette.of(context).amber,
                            fontSize: DS.labelSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    MountainAvatar(
                      initial: widget.library.initial,
                      size: DS.avatarLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('我'),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: SizedBox(width: 30, child: Divider()),
                ),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 33,
                      backgroundColor: DSPalette.of(context).bg,
                      child: Text(
                        '+',
                        style: TextStyle(
                          fontSize: 32,
                          color: DSPalette.of(context).muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('等待好友'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              expired ? '邀请已过期，请重新生成。' : '好友加入后，双方准备好再开始',
              textAlign: TextAlign.center,
              style: TextStyle(color: DSPalette.of(context).muted),
            ),
            if (!widget.library.preview)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '加入同一房间后，选择双方可访问的视频地址，即可同步播放、私聊和开启语音。',
                  style: DS.smallFor(context),
                ),
              ),
            if (error != null) ErrorNotice(error!),
            if (invite != null && !expired)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '剩余 ${invite!.expiresAt.difference(DateTime.now()).inMinutes + 1} 分钟 · 一次性邀请已生成',
                  textAlign: TextAlign.center,
                  style: DS.smallFor(context),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : () => generate(share: true),
              icon: DSIcon('share-2', color: DSPalette.of(context).bg),
              label: Text(
                busy
                    ? '正在生成…'
                    : expired
                    ? '重新生成并分享'
                    : '分享观影邀请',
              ),
            ),
            if (room != null && !widget.library.preview)
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => openPage(
                        context,
                        RoomWatchPage(
                          room: room!,
                          auth: widget.library.session!,
                        ),
                      ),
                icon: DSIcon('play', color: DSPalette.of(context).primary),
                label: const Text('进入同看房间'),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : () => generate(),
              icon: const DSIcon('copy'),
              label: const Text('复制邀请'),
            ),
            if (invite != null && !expired)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await RoomRepository(widget.library.session!)
                              .revoke(room!.id, invite!.id);
                          if (mounted) setState(() => invite = null);
                        } catch (e) {
                          if (mounted) tell(context, friendlyError(e));
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('撤销这份邀请'),
              ),
            const SizedBox(height: 12),
            Text(
              '一次性邀请 · 15 分钟有效 · 私密交流',
              style: DS.smallFor(context),
              textAlign: TextAlign.center,
            ),
            if (widget.library.preview)
              const PreviewLabel(text: '预览 · 不生成可分享的真实邀请'),
          ],
        ),
      ),
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
        padding: const EdgeInsets.all(16),
        children: [
          if (preview)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FilmHero(films.first, height: 275),
            ),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  preview ? '知夏邀请你一起看' : '接受私密观影邀请',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: DS.sectionSize),
                ),
                const SizedBox(height: 12),
                Text(
                  preview ? '山海之间' : '粘贴完整邀请码',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: DS.displaySize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  preview ? '完整正片 · 从 36:20 开始 · 预览' : '加入前无法查询发送者和影片，请向邀请人核对。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DSPalette.of(context).amber),
                ),
                const SizedBox(height: 25),
                Wrap(
                  alignment: WrapAlignment.spaceAround,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    const Column(
                      children: [
                        const MountainAvatar(size: 65),
                        const SizedBox(height: 10),
                        const Text('邀请人'),
                      ],
                    ),
                    DSIcon('users-round', color: DSPalette.of(context).muted),
                    const Column(
                      children: [
                        const MountainAvatar(initial: '满', size: 65),
                        const SizedBox(height: 10),
                        const Text('我 · 准备加入'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Panel(
                  child: Text('麦克风默认关闭，可先用文字交流。', style: DS.smallFor(context)),
                ),
                if (!preview)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextField(
                      key: const Key('invite-token'),
                      controller: token,
                      minLines: 2,
                      maxLines: 3,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '邀请码'),
                    ),
                  ),
                if (error != null) ErrorNotice(error!),
                const SizedBox(height: 20),
                if (blocked)
                  Text(
                    {
                      'invite-expired-receiver': '邀请已过期，请联系邀请人重新发送。',
                      'room-full': '房间已满，仅限两位成员。',
                      'room-closed': '房间已关闭，请向好友索取新的邀请。',
                      'invite-revoked': '邀请已被撤销，请联系邀请人。',
                    }[state]!,
                    style: TextStyle(color: DSPalette.of(context).amber),
                  ),
                FilledButton(
                  onPressed: busy || blocked ? null : join,
                  child: Text(busy ? '正在加入…' : '加入并准备'),
                ),
                const SizedBox(height: 12),
                Text(
                  '加入不代表同步完成。双方准备好后再开始。',
                  style: DS.smallFor(context),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (preview) const PreviewLabel(text: '邀请接收界面预览 · 无真实邀请码'),
        ],
      ),
    );
  }
}
