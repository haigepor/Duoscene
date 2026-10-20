import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import 'session.dart';

/// 注册和恢复成功后先保存恢复码，再返回登录；凭据不会写进普通偏好存储。
class AccountAccessPage extends StatefulWidget {
  const AccountAccessPage({
    super.key,
    required this.session,
    this.recover = false,
  });
  final Session session;
  final bool recover;
  @override
  State<AccountAccessPage> createState() => _AccountAccessPageState();
}

class _AccountAccessPageState extends State<AccountAccessPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(), nickname = TextEditingController();
  final password = TextEditingController(), repeat = TextEditingController();
  final recovery = TextEditingController();
  bool busy = false, hidden = true, saved = false;
  String? error, issuedCode;
  @override
  void dispose() {
    for (final c in [username, nickname, password, repeat, recovery]) {
      c.clear();
      c.dispose();
    }
    issuedCode = null;
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.session.api.request(
        'POST',
        widget.recover ? '/auth/recover' : '/auth/register',
        body: {
          'username': username.text.trim(),
          'password': password.text,
          if (widget.recover) 'recoveryCode': recovery.text.trim(),
          if (!widget.recover) 'displayName': nickname.text.trim(),
        },
      );
      if (mounted)
        setState(() {
          issuedCode = result['recoveryCode'] as String;
          password.clear();
          repeat.clear();
          recovery.clear();
        });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && (issuedCode == null || saved),
    onPopInvokedWithResult: (popped, _) {
      if (!popped && issuedCode != null) tell(context, '请先保存新的恢复码，再返回登录。');
    },
    child: PageFrame(
      title: widget.recover ? '找回密码' : '注册账号',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (issuedCode != null) ...[
            Text(widget.recover ? '密码已更新' : '账号已创建', style: DS.heading),
            const SizedBox(height: 12),
            Text(
              '请保存恢复码。它只在此时显示，可用于重设密码。请勿与他人分享。'
              '${widget.recover ? '旧恢复码和旧登录会话已失效。' : ''}',
              style: DS.body,
            ),
            const SizedBox(height: 20),
            Panel(
              child: SelectableText(
                issuedCode!,
                key: const Key('issued-recovery-code'),
                style: DS.body,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: issuedCode!));
                if (context.mounted) tell(context, '已复制恢复码，请保存到安全位置。');
              },
              icon: const DSIcon('copy', size: 18),
              label: const Text('复制恢复码'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: saved,
              onChanged: (v) => setState(() => saved = v ?? false),
              title: const Text('我已安全保存恢复码', style: DS.body),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saved
                  ? () => Navigator.pop(context, username.text.trim())
                  : null,
              child: const Text('返回登录'),
            ),
          ] else
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.recover ? '使用恢复码重设密码' : '开启你的下一场',
                    style: DS.heading,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.recover
                        ? '输入注册时保存的恢复码。重设成功会退出其他设备，并生成新的恢复码。'
                        : '创建账号后，请保存用于找回密码的恢复码。',
                    style: DS.smallFor(context),
                  ),
                  const SizedBox(height: 24),
                  _field(
                    '账户',
                    username,
                    key: 'access-username',
                    validator: (v) =>
                        RegExp(r'^[A-Za-z0-9_]{3,32}$')
                            .hasMatch(v?.trim() ?? '')
                        ? null
                        : '请输入3–32位字母、数字或下划线',
                  ),
                  if (!widget.recover)
                    _field(
                      '昵称',
                      nickname,
                      key: 'access-nickname',
                      validator: (v) =>
                          (v?.trim().isNotEmpty ?? false) &&
                              v!.trim().length <= 80
                          ? null
                          : '请输入1–80字昵称',
                    ),
                  if (widget.recover)
                    _field(
                      '恢复码',
                      recovery,
                      key: 'access-recovery',
                      validator: (v) =>
                          RegExp(r'^[A-Za-z0-9_-]{43}$')
                              .hasMatch(v?.trim() ?? '')
                          ? null
                          : '请粘贴完整的恢复码',
                    ),
                  _field(
                    widget.recover ? '新密码' : '密码',
                    password,
                    key: 'access-password',
                    secret: true,
                    validator: (v) => (v?.length ?? 0) >= 12 && v!.length <= 128
                        ? null
                        : '密码需12–128个字符',
                  ),
                  _field(
                    '确认密码',
                    repeat,
                    key: 'access-repeat',
                    secret: true,
                    validator: (v) => v == password.text ? null : '两次密码不一致',
                  ),
                  if (error != null) ErrorNotice(error!),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? '正在提交…'
                          : widget.recover
                          ? '重设密码'
                          : '创建账号',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  Widget _field(
    String label,
    TextEditingController controller, {
    required String key,
    bool secret = false,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DS.label),
        const SizedBox(height: 8),
        TextFormField(
          key: Key(key),
          controller: controller,
          enabled: !busy,
          obscureText: secret && hidden,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: key == 'access-repeat'
              ? TextInputAction.done
              : TextInputAction.next,
          onFieldSubmitted: key == 'access-repeat' ? (_) => submit() : null,
          maxLength: secret
              ? 128
              : key == 'access-recovery'
              ? 43
              : key == 'access-nickname'
              ? 80
              : 32,
          validator: validator,
          style: DS.body,
          decoration: InputDecoration(
            counterText: '',
            hintText: '请输入$label',
            suffixIcon: secret
                ? IconButton(
                    tooltip: hidden ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: DSIcon(hidden ? 'eye-off' : 'eye', size: 18),
                  )
                : null,
          ),
        ),
      ],
    ),
  );
}
