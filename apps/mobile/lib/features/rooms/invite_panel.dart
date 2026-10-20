import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/components.dart';

import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';
import 'room_repository.dart';

class InvitePanel extends StatefulWidget {
  const InvitePanel({
    super.key,
    required this.rooms,
    required this.roomId,
    required this.enabled,
  });
  final RoomRepository rooms;
  final String roomId;
  final bool enabled;
  @override
  State<InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<InvitePanel> with WidgetsBindingObserver {
  Invite? _invite;
  bool _busy = false;
  String? _error;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 进入后台时隐藏敏感邀请码，避免切换预览长期暴露。
    if (state != AppLifecycleState.resumed && _invite != null && mounted) {
      _expiry?.cancel();
      setState(() => _invite = null);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = await widget.rooms.invite(widget.roomId);
      if (!mounted) return;
      setState(() => _invite = invite);
      _expiry?.cancel();
      final remaining = invite.expiresAt.difference(DateTime.now());
      _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
        if (mounted) setState(() {});
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    if (_busy || _invite == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.rooms.revoke(widget.roomId, _invite!.id);
      if (mounted) setState(() => _invite = null);
      _expiry?.cancel();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final invite = _invite;
    if (invite == null || invite.expired) return;
    try {
      await Clipboard.setData(ClipboardData(text: invite.token));
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: const Text('邀请码已复制，请仅发送给受邀人。')));
    } catch (_) {
      if (mounted) setState(() => _error = '无法复制，请长按邀请码手动复制。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    final expiry = invite?.expiresAt.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('邀请另一位', style: DS.secondarySection),
        const SizedBox(height: 12),
        Text(
          '邀请限用一次，15 分钟后失效。只发给你想邀请的人。',
          style: TextStyle(color: DSPalette.of(context).muted, height: 1.6),
        ),
        if (_error != null) ErrorNotice(_error!),
        const SizedBox(height: 20),
        if (invite == null || invite.expired) ...[
          if (invite?.expired == true)
            const Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: const Text('邀请已到期，请生成新邀请。'),
            ),
          FilledButton.icon(
            onPressed: _busy || !widget.enabled ? null : _create,
            icon: DSIcon(
              'link',
              size: DS.navigationIcon,
              color: DSPalette.of(context).onPrimary,
            ),
            label: Text(_busy ? '正在生成…' : '生成一次性邀请'),
          ),
        ] else ...[
          SelectableText(
            invite.token,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
          ),
          const SizedBox(height: 12),
          Text(
            '到期时间：${expiry!.hour.toString().padLeft(2, '0')}:${expiry.minute.toString().padLeft(2, '0')} · 仅可使用一次',
            style: TextStyle(color: DSPalette.of(context).muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || !widget.enabled ? null : _copy,
            icon: DSIcon(
              'copy',
              size: DS.navigationIcon,
              color: DSPalette.of(context).onPrimary,
            ),
            label: const Text('复制邀请码'),
          ),
          TextButton(
            onPressed: _busy || !widget.enabled ? null : _revoke,
            child: Text(_busy ? '正在撤销…' : '撤销这份邀请'),
          ),
        ],
      ],
    );
  }
}
