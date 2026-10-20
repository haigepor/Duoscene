import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/components.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';
import '../auth/session.dart';
import 'room_detail_page.dart';
import 'room_form_page.dart';
import 'room_repository.dart';

class RoomListPage extends StatefulWidget {
  const RoomListPage({super.key, required this.session, required this.rooms});
  final Session session;
  final RoomRepository rooms;
  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  final List<Room> _items = [];
  String? _cursor;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.rooms.list(after: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        // 分页期间成员变化可能造成重复，按房间 ID 合并。
        for (final room in page.items) {
          final index = _items.indexWhere((item) => item.id == room.id);
          if (index < 0) {
            _items.add(room);
          } else {
            _items[index] = room;
          }
        }
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Room room) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RoomDetailPage(
          initialRoom: room,
          rooms: widget.rooms,
          userId: widget.session.user!.id,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _form(bool join) async {
    final room = await Navigator.of(context).push<Room>(
      MaterialPageRoute(
        builder: (_) => RoomFormPage(rooms: widget.rooms, join: join),
      ),
    );
    if (!mounted || room == null) return;
    await _open(room);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('下次进入需要重新输入账户和密码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.session.logout();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'DUOSCENE',
        style: const TextStyle(fontSize: 16, letterSpacing: 3),
      ),
      actions: [
        IconButton(
          tooltip: '刷新房间',
          onPressed: _loading ? null : _load,
          icon: const DSIcon('refresh-cw'),
        ),
        IconButton(
          tooltip: '退出登录',
          onPressed: _logout,
          icon: const DSIcon('log-out', size: DS.navigationIcon),
        ),
      ],
    ),
    body: SafeArea(
      child: PageBody(
        child: RefreshIndicator(
          onRefresh: () async {
            if (!_loading) await _load();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(DS.pageInset),
            children: [
              Text(
                '${widget.session.user!.displayName}，欢迎回来',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 12),
              const Text('我们的房间', style: DS.heading),
              const SizedBox(height: 12),
              Text(
                '相隔再远，也有一个共同的地方。',
                style: TextStyle(color: DSPalette.of(context).muted),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _form(false),
                icon: const Icon(Icons.add),
                label: const Text('创建房间'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _form(true),
                icon: const DSIcon('ticket', size: DS.navigationIcon),
                label: const Text('使用邀请码加入'),
              ),
              const SizedBox(height: 32),
              if (_error != null) ...[
                ErrorNotice(_error!),
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('重新加载房间'),
                ),
              ],
              if (_loading)
                const LinearProgressIndicator(semanticsLabel: '正在加载房间'),
              if (!_loading && _error == null && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.weekend_outlined,
                        size: 32,
                        color: DSPalette.of(context).muted,
                      ),
                      const SizedBox(height: 20),
                      const Text('第一场，从这里开始。', style: DS.secondarySection),
                      const SizedBox(height: 12),
                      Text(
                        '创建一个房间，或者使用对方的邀请加入。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: DSPalette.of(context).muted),
                      ),
                    ],
                  ),
                ),
              for (final room in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: DS.space12,
                        vertical: DS.space4,
                      ),
                      leading: Icon(
                        room.isOpen
                            ? Icons.meeting_room_outlined
                            : Icons.door_back_door_outlined,
                      ),
                      title: Text(
                        room.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${room.ownerUserId == widget.session.user!.id ? '你是房主' : '你是成员'} · ${room.isOpen ? '开放中' : '已关闭'}',
                      ),
                      trailing: DSIcon(
                        'chevron-right',
                        size: DS.chevronSize,
                        color: DSPalette.of(context).muted,
                      ),
                      onTap: () => _open(room),
                    ),
                  ),
                ),
              if (_cursor != null)
                TextButton(
                  onPressed: _loading ? null : () => _load(more: true),
                  child: const Text('加载更多房间'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
