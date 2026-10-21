import 'dart:convert';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/account_access_page.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'session_test.dart' show MemoryTokenStore, ok;

void main() {
  testWidgets('password visibility only changes the selected access field', (
    t,
  ) async {
    final session = Session(
      ApiClient(
        Uri.parse('http://localhost:3000'),
        client: MockClient((_) async => ok({})),
      ),
      MemoryTokenStore(),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: AccountAccessPage(session: session),
      ),
    );
    final password = find.byKey(const Key('access-password'));
    final repeat = find.byKey(const Key('access-repeat'));
    await t.ensureVisible(password);
    await t.enterText(password, 'a-new-long-password');
    await t.ensureVisible(repeat);
    await t.enterText(repeat, 'a-new-long-password');
    final toggle = find.descendant(
      of: password,
      matching: find.byType(IconButton),
    );
    await t.ensureVisible(toggle);
    await t.tap(toggle);
    await t.pump();
    expect(
      t.widget<TextFormField>(password).controller!.text,
      'a-new-long-password',
    );
    expect(
      t
          .widget<EditableText>(
            find.descendant(of: password, matching: find.byType(EditableText)),
          )
          .obscureText,
      isFalse,
    );
    expect(
      t
          .widget<EditableText>(
            find.descendant(of: repeat, matching: find.byType(EditableText)),
          )
          .obscureText,
      isTrue,
    );
    await t.pumpWidget(const SizedBox());
    session.dispose();
  });
  for (final recover in [false, true]) {
    testWidgets(
      '${recover ? 'recover' : 'register'} validates and gates recovery-code dismissal',
      (t) async {
        var requests = 0;
        final session = Session(
          ApiClient(
            Uri.parse('http://localhost:3000'),
            client: MockClient((request) async {
              requests++;
              final body = jsonDecode(request.body) as Map;
              expect(
                request.url.path,
                '/api/v1/auth/${recover ? 'recover' : 'register'}',
              );
              expect(body['username'], 'new_user');
              expect(body['password'], 'a-new-long-password');
              if (recover) expect(body['recoveryCode'], 'A' * 43);
              return ok({'recoveryCode': 'B' * 43});
            }),
          ),
          MemoryTokenStore(),
        );
        await t.pumpWidget(
          MaterialApp(
            theme: duosceneTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AccountAccessPage(session: session, recover: recover),
                    ),
                  ),
                  child: const Text('开始'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('开始'));
        await t.pumpAndSettle();
        final submit = find.widgetWithText(
          FilledButton,
          recover ? '重设密码' : '创建账号',
        );
        await t.ensureVisible(submit);
        await t.pumpAndSettle();
        await t.tap(submit);
        await t.pumpAndSettle();
        expect(requests, 0);
        expect(find.text('密码需12–128个字符'), findsOneWidget);
        for (final entry in {
          'username': 'new_user',
          if (recover) 'recovery': 'A' * 43 else 'nickname': '新朋友',
          'password': 'a-new-long-password',
          'repeat': 'a-new-long-password',
        }.entries) {
          final field = find.byKey(Key('access-${entry.key}'));
          await t.ensureVisible(field);
          await t.enterText(field, entry.value);
        }
        await t.ensureVisible(submit);
        await t.pumpAndSettle();
        await t.tap(submit);
        await t.pumpAndSettle();
        expect(requests, 1);
        expect(find.byKey(const Key('issued-recovery-code')), findsOneWidget);
        expect(
          t
              .widget<FilledButton>(find.widgetWithText(FilledButton, '返回登录'))
              .onPressed,
          isNull,
        );
        await t.tap(find.byType(CheckboxListTile));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('返回登录'));
        await t.tap(find.text('返回登录'));
        await t.pumpAndSettle();
        expect(find.text('开始'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
}
