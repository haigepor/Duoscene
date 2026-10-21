import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/account_access_page.dart';
import 'package:duoscene/features/auth/login_page.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'session_test.dart' show MemoryTokenStore, ok;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'auth forms remain reachable with keyboard and large text (${dark ? 'dark' : 'light'})',
      (t) async {
        t.view.physicalSize = const Size(320, 720);
        t.view.devicePixelRatio = 1;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        final session = Session(
          ApiClient(
            Uri.parse('http://localhost:3000'),
            client: MockClient((_) async => ok({})),
          ),
          MemoryTokenStore(),
        );
        for (final page in [
          LoginPage(session: session),
          AccountAccessPage(session: session),
          AccountAccessPage(session: session, recover: true),
        ]) {
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? duosceneDarkTheme : duosceneTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 280),
                ),
                child: child!,
              ),
              home: page,
            ),
          );
          await t.pumpAndSettle();
          final lastField = find.byType(TextFormField).last;
          await t.ensureVisible(lastField);
          await t.enterText(lastField, 'a-long-test-password');
          await t.ensureVisible(find.byType(FilledButton));
          await t.pumpAndSettle();
          expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        }
        session.dispose();
      },
    );
  }
}
