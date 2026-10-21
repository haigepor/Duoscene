import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';
import 'invite_panel.dart';
import 'room_repository.dart';
import '../realtime/room_watch_page.dart';
import '../../design/tokens.dart';
import '../../design/components.dart';
import '../../design/illustrations.dart';

class RoomDetailPage extends StatefulWidget {
  const RoomDetailPage({
    super.key,
    required this.initialRoom,
    required this.rooms,
    required this.userId,
  });
  final Room initialRoom;
  final RoomRepository rooms;
  final String userId;
  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage>
    with WidgetsBindingObserver {
  late Room _room;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await widget.rooms.get(_room.id);
      if (mounted) setState(() => _room = room);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '房间',
    actions: [
      IconButton(
        tooltip: '刷新成员',
        onPressed: _loading ? null : _load,
        icon: const DSIcon('refresh-cw'),
      ),
    ],
    child: PageBody(
      child: RefreshIndicator(
        onRefresh: () async {
          if (!_loading) await _load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DS.pageInset),
          children: [
            DSIntro(
              _room.name,
              _room.isOpen ? '双人私密房间 · 仅受邀加入' : '房间已关闭',
              artwork: 'duo-tickets-glass',
            ),
            const SizedBox(height: DS.space24),
            FilledButton.icon(
              icon: DSIcon(
                'play',
                size: DS.navigationIcon,
                color: DSPalette.of(context).onPrimary,
              ),
              label: const Text('打开播放器'),
              onPressed: !_room.isOpen
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoomWatchPage(
                          room: _room,
                          auth: widget.rooms.session,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const LinearProgressIndicator(semanticsLabel: '正在更新成员'),
            if (_error != null) ErrorNotice(_error!),
            Text(
              '${_room.members.length} / 2 席',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            for (var seat = 1; seat <= 2; seat++) _seat(seat),
            const SizedBox(height: 24),
            if (_room.isOpen &&
                _room.ownerUserId == widget.userId &&
                _room.members.length < 2)
              InvitePanel(
                key: ValueKey(_room.id),
                rooms: widget.rooms,
                roomId: _room.id,
                enabled: !_loading && _error == null,
              ),
            if (_room.isOpen && _room.members.length == 2)
              const Text('两席已齐。', style: DS.secondarySection),
            if (!_room.isOpen) const Text('这个房间已关闭，不能再邀请或加入。'),
          ],
        ),
      ),
    ),
  );

  Widget _seat(int seat) {
    final members = _room.members.where((member) => member.seatNo == seat);
    final member = members.isEmpty ? null : members.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: DSPalette.of(context).panel,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DS.space12,
          vertical: DS.space8,
        ),
        leading: CircleAvatar(
          child: Icon(
            member == null ? Icons.person_add_alt : Icons.person_outline,
          ),
        ),
        title: Text(member?.displayName ?? '留给另一位'),
        subtitle: Text(
          member == null
              ? '等待邀请加入'
              : '${member.userId == _room.ownerUserId ? '房主' : '成员'}${member.userId == widget.userId ? ' · 我' : ''}',
        ),
      ),
    );
  }
}
