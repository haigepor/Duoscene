import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../design/illustrations.dart';
import '../catalog/library_state.dart';
import 'conversation.dart';
import '../rooms/room_list_page.dart';
import '../rooms/room_repository.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.library,
    this.sheet = false,
    this.subtitle = '私密交流',
    this.onInvite,
    this.onVolumeChanged,
    this.compact = false,
    this.composerHeader,
  });
  final LibraryState library;
  final bool sheet;
  // 观看页在标签栏显示隐私说明，音频统一收进状态栏弹层。
  final bool compact;
  final Widget? composerHeader;
  final String subtitle;
  final VoidCallback? onInvite;
  final ValueChanged<double>? onVolumeChanged;
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final input = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  late final adapter = PreviewChatAdapter()
    ..fail = widget.library.scenario == 'message-send-failed';
  late final chat = Conversation(
    adapter,
    seed:
        widget.library.preview &&
        widget.library.scenario != 'private-chat-empty',
  );
  bool get enabled =>
      widget.library.preview && widget.library.scenario != 'private-chat-empty';
  @override
  void initState() {
    super.initState();
    if (widget.library.scenario == 'message-send-failed') chat.send('这一段好好看');
    focus.addListener(_focusChanged);
    input.addListener(_focusChanged);
    if (widget.library.scenario == 'chat-keyboard')
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          input.text = '这段好好看';
          focus.requestFocus();
        }
      });
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    scroll.dispose();
    input.dispose();
    focus.removeListener(_focusChanged);
    focus.dispose();
    chat.dispose();
    super.dispose();
  }

  void send() {
    if (input.text.trim().isEmpty) return;
    final text = input.text;
    input.clear();
    chat.send(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients)
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: DSMotion.duration(context),
          curve: DSMotion.curve,
        );
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !focus.hasFocus || MediaQuery.viewInsetsOf(context).bottom == 0,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) focus.unfocus();
    },
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          if (widget.sheet)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 6, 4),
              child: Row(
                children: [
                  const Expanded(child: Text('一起聊聊', style: DS.heading)),
                  IconTap('x', '关闭私聊', () {
                    if (focus.hasFocus)
                      focus.unfocus();
                    else
                      Navigator.pop(context);
                  }),
                ],
              ),
            ),
          if (!widget.compact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  DSIcon(
                    'lock-keyhole',
                    size: 14,
                    color: DSPalette.of(context).primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      enabled
                          ? '${widget.subtitle} · 仅你和小满可见 · 预览'
                          : '邀请好友后开始交流',
                      style: DS.smallFor(context),
                      maxLines: constraints.maxHeight < 300 ? 1 : null,
                      overflow: constraints.maxHeight < 300
                          ? TextOverflow.ellipsis
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: enabled
                ? ListenableBuilder(
                    listenable: chat,
                    builder: (context, _) => ListView(
                      controller: scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.composerHeader == null
                            ? DS.space16
                            : DS.pageInset * 2,
                        vertical: DS.space16,
                      ),
                      children: [
                        for (final m in chat.messages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: m.mine
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                if (!m.mine) ...[
                                  const MountainAvatar(
                                    initial: '满',
                                    size: DS.avatarSmall,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: m.mine
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 9,
                                        ),
                                        decoration: BoxDecoration(
                                          color: m.mine
                                              ? DSPalette.of(context).tint
                                              : DSPalette.of(context).line
                                                    .withValues(alpha: .5),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          m.text,
                                          style: TextStyle(
                                            color: m.mine
                                                ? DSPalette.of(context).onTint
                                                : DSPalette.of(context).ink,
                                          ),
                                        ),
                                      ),
                                      if (m.mine)
                                        m.delivery == Delivery.failed
                                            ? TextButton(
                                                onPressed: () {
                                                  adapter.fail = false;
                                                  chat.retry(m);
                                                },
                                                child: Text(
                                                  '发送失败，点击重试',
                                                  style: TextStyle(
                                                    color: DSPalette.of(context)
                                                        .amber,
                                                    fontSize: DS.captionSize,
                                                  ),
                                                ),
                                              )
                                            : Text(
                                                m.delivery == Delivery.pending
                                                    ? '发送中…'
                                                    : '已发送 · 预览',
                                                style: DS.smallFor(context),
                                              ),
                                    ],
                                  ),
                                ),
                                if (m.mine) ...[
                                  const SizedBox(width: 10),
                                  MountainAvatar(
                                    initial: widget.library.initial,
                                    size: DS.avatarSmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(DS.space16),
                    child: Column(
                      children: [
                        const SizedBox(height: DS.space12),
                        const DSIllustration(
                          'conversation-glass',
                          width: 112,
                          height: 84,
                        ),
                        const SizedBox(height: DS.space16),
                        const Text(
                          '好看的，想和你聊聊',
                          style: DS.section,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: DS.space8),
                        Text(
                          widget.library.preview
                              ? '邀请好友后开始交流'
                              : '进入同看房间后，可与好友实时交流。',
                          textAlign: TextAlign.center,
                          style: DS.smallFor(context),
                        ),
                        const SizedBox(height: DS.space16),
                        FilledButton(
                          onPressed: widget.onInvite,
                          child: const Text('邀请一起看'),
                        ),
                      ],
                    ),
                  ),
          ),
          if (widget.library.preview || widget.composerHeader != null)
            Padding(
              padding: widget.composerHeader == null
                  ? const EdgeInsets.fromLTRB(12, 4, 12, 10)
                  // 播放器页：与上方个人观看栏对齐，左右各留一道边。
                  : const EdgeInsets.fromLTRB(
                      DS.space12,
                      DS.space4,
                      DS.space12,
                      DS.space8,
                    ),
              child: _composerSurface(
                context,
                Row(
                  crossAxisAlignment: widget.composerHeader == null
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.end,
                  children: [
                    if (widget.sheet)
                      IconTap(
                        'mic-off',
                        '麦克风已关闭',
                        () => tell(
                          context,
                          widget.library.scenario == 'mic-denied'
                              ? '麦克风权限被拒，仍可观看和发送文字。'
                              : '请在同看房间内开启语音，麦克风默认关闭。',
                        ),
                      ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          // 输入区最多占用消息区的一部分，键盘和大字号下仍留出消息空间。
                          maxHeight: widget.composerHeader == null
                              ? double.infinity
                              : (constraints.maxHeight * .45).clamp(
                                  DS.inputHeight,
                                  DS.inputHeight * 3,
                                ),
                        ),
                        child: TextField(
                          key: const Key('chat-input'),
                          controller: input,
                          focusNode: focus,
                          enabled: enabled,
                          minLines: 1,
                          maxLines: widget.composerHeader == null ? 3 : 5,
                          keyboardType: TextInputType.multiline,
                          textInputAction: widget.composerHeader == null
                              ? TextInputAction.send
                              : TextInputAction.newline,
                          onSubmitted: widget.composerHeader == null
                              ? (_) => send()
                              : null,
                          decoration: InputDecoration(
                            hintText: enabled ? '和小满说点什么…' : '邀请好友后开始交流',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(28),
                              ),
                            ),
                            filled: widget.composerHeader == null,
                            enabledBorder: widget.composerHeader == null
                                ? null
                                : InputBorder.none,
                            disabledBorder: widget.composerHeader == null
                                ? null
                                : InputBorder.none,
                            focusedBorder: widget.composerHeader == null
                                ? null
                                : InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const Key('chat-send'),
                      tooltip: '发送消息',
                      style: widget.composerHeader == null
                          ? null
                          : IconButton.styleFrom(
                              fixedSize: const Size.square(
                                DS.buttonHeight - DS.space4,
                              ),
                              minimumSize: const Size.square(
                                DS.buttonHeight - DS.space4,
                              ),
                              maximumSize: const Size.square(
                                DS.buttonHeight - DS.space4,
                              ),
                              padding: const EdgeInsets.all(DS.space4),
                              // 收掉 padded 的 48 最小布局盒，行高由输入框决定。
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                      onPressed: enabled && input.text.trim().isNotEmpty
                          ? send
                          : null,
                      icon: DSIcon(
                        'arrow-up',
                        size: widget.composerHeader == null
                            ? DS.iconSize
                            : DS.iconSmall,
                        color: DSPalette.of(context).onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!widget.compact &&
              widget.library.preview &&
              !widget.sheet &&
              !focus.hasFocus &&
              constraints.maxHeight >= 300)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 14, 4),
              child: Row(
                children: [
                  IconTap(
                    'mic-off',
                    '麦克风已关闭',
                    () => tell(context, '预览麦克风保持关闭；登录并进入同看房间可开启语音。'),
                  ),
                  Expanded(child: Text('麦克风已关闭', style: DS.smallFor(context))),
                  const DSIcon('volume-2', size: 18),
                  SizedBox(
                    width: 100,
                    child: Slider(
                      value: widget.library.movieVolume,
                      onChanged: (v) {
                        setState(() => widget.library.movieVolume = v);
                        widget.onVolumeChanged?.call(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _composerSurface(BuildContext context, Widget inputRow) {
    if (widget.composerHeader == null) return inputRow;
    final p = DSPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 状态栏不做色块，直接坐在页面背景上；左右各收一道，起点窄于输入框。
        Padding(
          padding: const EdgeInsets.only(
            left: DS.space12,
            right: DS.space12,
            bottom: DS.space4,
          ),
          child: widget.composerHeader,
        ),
        DecoratedBox(
          key: const Key('watch-composer-input-surface'),
          decoration: BoxDecoration(
            color: p.panel,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(DS.panelRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DS.space4,
              vertical: DS.space2,
            ),
            child: inputRow,
          ),
        ),
      ],
    );
  }
}

Future<void> showPrivateChat(BuildContext context, LibraryState library) {
  // 真实账户从房间入口进入已有的实时聊天，不创建第二套消息适配器。
  if (!library.preview && library.session != null) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RoomListPage(
          session: library.session!,
          rooms: RoomRepository(library.session!),
        ),
      ),
    );
  }
  return showDSSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: DSPalette.of(context).panel,
    builder: (c) => AnimatedPadding(
      duration: DSMotion.duration(c),
      curve: DSMotion.curve,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: SizedBox(
        height: (MediaQuery.sizeOf(c).height * .55).clamp(
          120,
          (MediaQuery.sizeOf(c).height - MediaQuery.viewInsetsOf(c).bottom - 80)
              .clamp(120, MediaQuery.sizeOf(c).height),
        ),
        child: ChatPanel(
          library: library,
          sheet: true,
          subtitle: '回到风起时 · 第 8 集',
        ),
      ),
    ),
  );
}
