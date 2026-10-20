import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import 'session.dart';
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
  Widget build(BuildContext context) => Scaffold(
    body: Forest(
      hero: true,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageBody(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(DS.space24),
                      children: [
                        // 键盘展开后根据可用高度收紧顶部留白，登录操作仍可滚动到达。
                        SizedBox(
                          height: (constraints.maxHeight * .12).clamp(
                            DS.space16,
                            80.0,
                          ),
                        ),
                        const Center(
                          child: Brand(size: DS.brandSize + DS.space8),
                        ),
                        const SizedBox(height: DS.space24),
                        Text(
                          '下一场，一起开始。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: DS.pageTitleSize,
                            height: 1.4,
                            color: DSPalette.of(context).ink,
                          ),
                        ),
                        const SizedBox(height: DS.space32),
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
                                    controller: _username,
                                    key: const Key('username'),
                                    enabled: !(widget.session?.busy ?? false),
                                    decoration: _decoration(
                                      '输入账户',
                                      'user-round',
                                    ),
                                    style: DS.body,
                                    cursorColor: DSPalette.of(context).primary,
                                    keyboardType: TextInputType.text,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    textInputAction: TextInputAction.next,
                                    maxLength: 32,
                                    validator: (value) =>
                                        RegExp(r'^[A-Za-z0-9_]{3,32}$')
                                            .hasMatch(value?.trim() ?? '')
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
                                    controller: _password,
                                    key: const Key('password'),
                                    enabled: !(widget.session?.busy ?? false),
                                    decoration: _decoration(
                                      '输入密码',
                                      'lock-keyhole',
                                      suffix: IconButton(
                                        tooltip: _hidden ? '显示密码' : '隐藏密码',
                                        icon: DSIcon(
                                          _hidden ? 'eye-off' : 'eye',
                                          color: DSPalette.of(context).muted,
                                          size: DS.navigationIcon,
                                        ),
                                        onPressed:
                                            (widget.session?.busy ?? false)
                                            ? null
                                            : () => setState(
                                                () => _hidden = !_hidden,
                                              ),
                                      ),
                                    ),
                                    style: DS.body,
                                    cursorColor: DSPalette.of(context).primary,
                                    obscureText: _hidden,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    maxLength: 128,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _login(),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                        ? '请输入密码'
                                        : null,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: (widget.session?.busy ?? false)
                                        ? null
                                        : () => _access(true),
                                    child: const Text('忘记密码？'),
                                  ),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(
                                      DS.primaryButtonHeight,
                                    ),
                                  ),
                                  onPressed: (widget.session?.busy ?? false)
                                      ? null
                                      : _login,
                                  child: Text(
                                    (widget.session?.busy ?? false)
                                        ? '正在登录…'
                                        : '登录 Duoscene',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: (widget.session?.busy ?? false)
                                      ? null
                                      : () => _access(false),
                                  child: const Text('注册账号'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 8,
              child: IconTap(
                'sun',
                '切换外观',
                () => openPage(context, const AppearancePage()),
              ),
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
  InputDecoration _decoration(String hint, String icon, {Widget? suffix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DS.radiusMedium),
      borderSide: BorderSide(color: DSPalette.of(context).outline),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: DS.body.copyWith(color: DSPalette.of(context).muted),
      counterText: '',
      filled: true,
      fillColor: DSPalette.of(context).panel,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DS.space12,
        vertical: 14,
      ),
      prefixIcon: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: DSIcon(
          icon,
          size: DS.navigationIcon,
          color: DSPalette.of(context).muted,
        ),
      ),
      prefixIconConstraints: const BoxConstraints(
        minWidth: DS.primaryButtonHeight,
        minHeight: DS.touchTarget,
      ),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(
        minWidth: DS.touchTarget,
        minHeight: DS.touchTarget,
      ),
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(
        borderSide: BorderSide(
          color: DSPalette.of(context).line.withValues(alpha: .5),
        ),
      ),
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: DSPalette.of(context).primary),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      errorStyle: DS
          .smallFor(context)
          .copyWith(color: Theme.of(context).colorScheme.error),
      errorMaxLines: 3,
    );
  }
}
