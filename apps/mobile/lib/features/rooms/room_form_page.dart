import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/components.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';
import 'room_repository.dart';

class RoomFormPage extends StatefulWidget {
  const RoomFormPage({super.key, required this.rooms, required this.join});
  final RoomRepository rooms;
  final bool join;
  @override
  State<RoomFormPage> createState() => _RoomFormPageState();
}

class _RoomFormPageState extends State<RoomFormPage> {
  final _form = GlobalKey<FormState>();
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Room room = widget.join
          ? await widget.rooms.join(_input.text)
          : await widget.rooms.create(_input.text);
      if (mounted) Navigator.of(context).pop(room);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.join ? '邀请加入' : '创建房间')),
    body: SafeArea(
      child: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(DS.pageInset),
          children: [
            DSIcon(
              widget.join ? 'ticket' : 'users-round',
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              widget.join ? '另一席，为你留着。' : '给这一场起个名字。',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              widget.join
                  ? '粘贴房主发来的完整邀请码。每份邀请限用一次，有效期 15 分钟。'
                  : '房间仅限两位成员。创建后，把限时邀请发给另一位。',
              style: DS.smallFor(context),
            ),
            const SizedBox(height: 32),
            if (_error != null) ErrorNotice(_error!),
            Form(
              key: _form,
              child: TextFormField(
                key: Key(widget.join ? 'invite-token' : 'room-name'),
                controller: _input,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: widget.join ? '邀请码' : '房间名称',
                  hintText: widget.join ? '粘贴完整邀请码' : '例如：周末放映室',
                ),
                maxLength: widget.join ? null : 100,
                minLines: widget.join ? 2 : 1,
                maxLines: widget.join ? 3 : 1,
                autocorrect: false,
                enableSuggestions: !widget.join,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (widget.join)
                    return RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(input)
                        ? null
                        : '请粘贴完整的 43 位邀请码';
                  return input.isEmpty ? '请输入房间名称' : null;
                },
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? '正在提交…'
                    : widget.join
                    ? '加入房间'
                    : '创建并进入',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
