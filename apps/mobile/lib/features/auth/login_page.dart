import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import 'session.dart';
import 'auth_widgets.dart';
import 'account_access_page.dart';
import '../experience/appearance_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.session,
    this.previewError = false,
  });
  final Session? session;
  final bool previewError;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  late String? _error = widget.previewError ? '登录信息无效，请检查账户和密码。' : null;
  @override
  void initState() {
    super.initState();
    if (widget.previewError) _username.text = 'zhixia';
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if ((widget.session?.busy ?? false) || !_form.currentState!.validate())
      return;
    if (widget.session == null) {
      tell(context, '登录界面预览，请返回真实登录入口。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    try {
      await widget.session!.login(_username.text, _password.text);
      TextInput.finishAutofillContext();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  Future<void> _access(bool recover) async {
    final session = widget.session;
    if (session == null) {
      tell(context, '请从真实登录页注册或找回密码。');
      return;
    }
    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountAccessPage(session: session, recover: recover),
      ),
    );
    if (name != null && mounted)
      setState(() {
        _username.text = name;
        _password.clear();
        _error = null;
      });
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session?.busy ?? false;
    return Scaffold(
      body: Forest(
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: DS.space24,
                          right: DS.space12,
                        ),
                        child: SizedBox(
                          height: DS.toolbarHeight,
                          child: Row(
                            children: [
                              const Expanded(child: Brand(ringsFirst: true)),
                              IconTap(
                                'sun',
                                '切换外观',
                                () => openPage(context, const AppearancePage()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AuthBody(
                      filmstrip: true,
                      children: [
                        const AuthIntro(
                          '下一场，一起开始。',
                          '登录，继续你的观影时光。',
                          artwork: 'duo-tickets-glass',
                        ),
                        AutofillGroup(
                          child: Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('账户', style: DS.label),
                                const SizedBox(height: DS.space8),
                                Semantics(
                                  label: '账户',
                                  child: TextFormField(
                                    key: const Key('username'),
                                    controller: _username,
                                    enabled: !busy,
                                    decoration: authInputDecoration(
                                      context,
                                      '请输入账户',
                                      'user-round',
                                    ),
                                    style: DS.body,
                                    keyboardType: TextInputType.text,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    textInputAction: TextInputAction.next,
                                    maxLength: 32,
                                    validator: (v) =>
                                        RegExp(r'^[A-Za-z0-9_]{3,32}$')
                                            .hasMatch(v?.trim() ?? '')
                                        ? null
                                        : '账户为 3–32 位字母、数字或下划线',
                                  ),
                                ),
                                const SizedBox(height: DS.space16),
                                const Text('密码', style: DS.label),
                                const SizedBox(height: DS.space8),
                                Semantics(
                                  label: '密码',
                                  child: TextFormField(
                                    key: const Key('password'),
                                    controller: _password,
                                    enabled: !busy,
                                    decoration: authInputDecoration(
                                      context,
                                      '请输入密码',
                                      'lock-keyhole',
                                      suffix: IconButton(
                                        tooltip: _hidden ? '显示密码' : '隐藏密码',
                                        onPressed: busy
                                            ? null
                                            : () => setState(
                                                () => _hidden = !_hidden,
                                              ),
                                        icon: DSIcon(
                                          _hidden ? 'eye-off' : 'eye',
                                          size: DS.navigationIcon,
                                          color: DSPalette.of(context).muted,
                                        ),
                                      ),
                                    ),
                                    style: DS.body,
                                    obscureText: _hidden,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    maxLength: 128,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _login(),
                                    validator: (v) =>
                                        v == null || v.isEmpty ? '请输入密码' : null,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _access(true),
                                    child: const Text('忘记密码？'),
                                  ),
                                ),
                                const SizedBox(height: DS.space12),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    textStyle: DS.title.copyWith(
                                      fontSize: DS.itemTitleSize,
                                    ),
                                  ),
                                  onPressed: busy ? null : _login,
                                  child: Text(busy ? '正在登录…' : '登录'),
                                ),
                                const SizedBox(height: DS.space12),
                                AuthLink(
                                  '注册账号',
                                  busy ? null : () => _access(false),
                                  prefix: '还没有账号？',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_error ?? widget.session?.notice case final String message)
                Positioned(
                  top: DS.space12,
                  left: DS.space16,
                  right: DS.space16,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: ErrorNotice(message, floating: true),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
