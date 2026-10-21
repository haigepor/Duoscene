import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/components.dart';
import '../../design/illustrations.dart';
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
  Widget build(BuildContext context) => PageFrame(
    title: widget.join ? '邀请加入' : '创建房间',
    child: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(DS.pageInset),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Center(
            child: DSIllustration('duo-tickets-glass', width: 128, height: 100),
          ),
          const SizedBox(height: DS.space16),
          Text(widget.join ? '另一席，为你留着。' : '给这一场起个名字。', style: DS.heading),
          const SizedBox(height: DS.space8),
          Text(
            widget.join ? '粘贴完整邀请码，加入好友的房间。' : '房间仅限两位成员，创建后即可邀请好友。',
            style: DS.smallFor(context),
          ),
          const SizedBox(height: DS.space24),
          Text(widget.join ? '邀请码' : '房间名称', style: DS.secondarySection),
          const SizedBox(height: DS.space12),
          if (_error != null) ErrorNotice(_error!),
          Form(
            key: _form,
            child: TextFormField(
              key: Key(widget.join ? 'invite-token' : 'room-name'),
              controller: _input,
              enabled: !_busy,
              decoration: InputDecoration(
                hintText: widget.join ? '粘贴完整的 43 位邀请码' : '例如：周末放映室',
              ),
              maxLength: widget.join ? null : 100,
              minLines: widget.join ? 3 : 1,
              maxLines: widget.join ? 4 : 1,
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
          const SizedBox(height: DS.space24),
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
          const SizedBox(height: DS.space24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DSIcon(
                'lock-keyhole',
                size: DS.iconSmall,
                color: DSPalette.of(context).muted,
              ),
              const SizedBox(width: DS.space8),
              Flexible(
                child: Text(
                  widget.join ? '一次性邀请 · 15 分钟有效' : '仅受邀加入 · 双人私密房间',
                  style: DS.smallFor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
