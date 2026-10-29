import 'package:duoscene/app/duoscene_app.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/app_shell.dart';
import 'package:duoscene/features/catalog/media_provider.dart';
import 'package:duoscene/features/catalog/providers/whisklet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_test.dart' show MemoryTokenStore, ok;

class _GuestCatalog implements MediaProvider {
  @override
  Future<List<Film>> recommendations() async => films.take(4).toList();
  @override
  Future<CatalogPage> browse(int category, {int page = 1}) async =>
      CatalogPage(const [], page: page, pages: 1);
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('default entry opens live catalog without an account', (t) async {
    await t.pumpWidget(const DuosceneApp());
    await t.pumpAndSettle();
    expect(find.byType(WatchHome), findsOneWidget);
    final library = t.widget<WatchHome>(find.byType(WatchHome)).library;
    expect(library.preview, isFalse);
    expect(library.provider, isA<WhiskletProvider>());
    expect(library.session, isNull);
    expect(find.byKey(const Key('username')), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('guest startup leaves saved credentials and auth API untouched', (
    t,
  ) async {
    var requests = 0;
    final store = MemoryTokenStore()..value = 'saved-private-refresh';
    final session = Session(
      ApiClient(
        Uri.parse('http://127.0.0.1:3000'),
        client: MockClient((_) async {
          requests++;
          return ok({});
        }),
      ),
      store,
    );
    await t.pumpWidget(DuosceneApp(session: session));
    await t.pumpAndSettle();
    expect(find.byType(WatchHome), findsOneWidget);
    expect(requests, 0);
    expect(store.value, 'saved-private-refresh');
    await t.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  test(
    'guest favorites survive restart without mixing account storage',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'duoscene.library.v1.owner',
        'private-account-data',
      );
      final first = LibraryState.guest();
      await first.restore();
      await first.toggleFavorite(films.first);
      first.dispose();
      final restored = LibraryState.guest();
      await restored.restore();
      expect(restored.favorites, contains(films.first.id));
      expect(restored.storageKey, 'duoscene.library.v1.local-guest');
      expect(
        prefs.getString('duoscene.library.v1.owner'),
        'private-account-data',
      );
      restored.dispose();
    },
  );

  testWidgets('guest room and profile actions stay safe without login', (
    t,
  ) async {
    final library = LibraryState.guest(provider: _GuestCatalog());
    await t.pumpWidget(MaterialApp(home: AppShell(library: library)));
    await t.pumpAndSettle();
    await t.tap(find.text('创建房间'));
    await t.pumpAndSettle();
    expect(find.text('当前免登录模式暂不支持双人房间。'), findsOneWidget);
    await t.tap(find.byKey(const Key('tab-3')));
    await t.pumpAndSettle();
    expect(find.text('访客'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
    await t.ensureVisible(find.text('观影邀请'));
    await t.tap(find.text('观影邀请'));
    await t.pumpAndSettle();
    expect(find.text('邀请与房间'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    library.dispose();
  });
}
