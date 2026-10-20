import 'dart:async';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/app_shell.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/experience/conversation.dart';
import 'package:duoscene/features/experience/episode_sheet.dart';
import 'package:duoscene/features/experience/chat_panel.dart';
import 'package:duoscene/features/experience/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RacingCatalog implements CatalogRepository {
  final first = Completer<List<Film>>(), second = Completer<List<Film>>();
  @override
  Future<List<Film>> search(String query) =>
      query == '旧' ? first.future : second.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'search fences stale successes and failures and safely disposes',
    () async {
      final repo = RacingCatalog();
      final state = SearchState(repo);
      final old = state.search('旧'), latest = state.search('新');
      repo.second.complete([films.first]);
      await latest;
      repo.first.completeError(StateError('late network failure'));
      await old;
      expect(state.query, '新');
      expect(state.results, [films.first]);
      expect(state.error, isNull);
      state.dispose();
    },
  );
  test(
    'account-scoped local library separates personal and shared progress',
    () async {
      final a = LibraryState(accountId: 'a'), b = LibraryState(accountId: 'b');
      await a.restore();
      await b.restore();
      await a.toggleFavorite(films.first);
      await a.record(const WatchEntry('mountains', 40, 1));
      await a.record(const WatchEntry('mountains', 90, 1, shared: true));
      await a.record(const WatchEntry('mountains', 55, 1));
      final restored = LibraryState(accountId: 'a');
      await restored.restore();
      expect(restored.history.length, 2);
      expect(restored.history.singleWhere((e) => e.shared).seconds, 90);
      expect(restored.history.singleWhere((e) => !e.shared).seconds, 55);
      expect(restored.favorites, {'mountains'});
      expect(b.history, isEmpty);
      expect(b.favorites, isEmpty);
      await restored.removeHistory({'mountains:personal'});
      expect(restored.history.single.shared, true);
      a.dispose();
      b.dispose();
      restored.dispose();
    },
  );
  test(
    'preview cannot persist or contaminate an authenticated account',
    () async {
      final preview = LibraryState(accountId: 'a', preview: true);
      await preview.toggleFavorite(films.first);
      final real = LibraryState(accountId: 'a');
      await real.restore();
      expect(real.favorites, isEmpty);
      expect(real.history, isEmpty);
      preview.dispose();
      real.dispose();
    },
  );
  test('message retry keeps the original bubble and identifier', () async {
    final adapter = PreviewChatAdapter()..fail = true;
    final chat = Conversation(adapter);
    await chat.send('保留这条消息');
    final original = chat.messages.single;
    expect(original.delivery, Delivery.failed);
    adapter.fail = false;
    await chat.retry(original);
    expect(chat.messages.length, 1);
    expect(identical(chat.messages.single, original), true);
    expect(original.delivery, Delivery.sent);
    chat.dispose();
  });
  test('peer recovery never cancels manual pause', () {
    final intent = WatchIntent()
      ..pause()
      ..peer(false)
      ..peer(true);
    expect(intent.mayPlay, false);
    intent.play();
    expect(intent.mayPlay, true);
    intent.dispose();
  });
  testWidgets(
    'four tabs preserve favorites and history and no fifth tab appears',
    (tester) async {
      final l = LibraryState(accountId: 'preview', preview: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: AppShell(preview: true, library: l),
        ),
      );
      await tester.pumpAndSettle();
      for (final index in [1, 2, 3, 0]) {
        await tester.tap(find.byKey(Key('tab-$index')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('tab-4')), findsNothing);
      expect(l.favorites.length, 5);
      await tester.pumpWidget(const SizedBox());
      l.dispose();
    },
  );
  testWidgets(
    'shared episode cancellation and waiting never return a new episode',
    (tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showEpisodes(
                    context,
                    films.last,
                    8,
                    shared: true,
                  );
                },
                child: const Text('选集'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选集'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('09'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('09'), findsOneWidget);
      await tester.tap(find.text('09'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('请求换集'));
      await tester.pumpAndSettle();
      expect(find.textContaining('尚未换集'), findsOneWidget);
      expect(result, isNull);
    },
  );
  testWidgets(
    'chat keyboard insets keep composer visible and send clears draft',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      final l = LibraryState(accountId: 'preview', preview: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => showPrivateChat(c, l),
                child: const Text('打开私聊'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开私聊'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('chat-input')), '这段好好看');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byKey(const Key('chat-send'))).dy,
        lessThan(544),
      );
      await tester.tap(find.byKey(const Key('chat-send')));
      await tester.pumpAndSettle();
      expect(find.text('这段好好看'), findsOneWidget);
      expect(find.text('已发送 · 预览'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      l.dispose();
    },
  );
  testWidgets(
    'privacy clear requires confirmation and leaves favorites intact',
    (tester) async {
      final l = LibraryState(accountId: 'preview', preview: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: PrivacyPage(library: l),
        ),
      );
      await tester.ensureVisible(find.text('清理我的本机观看记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理我的本机观看记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(l.history.length, 3);
      await tester.tap(find.text('清理我的本机观看记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理记录'));
      await tester.pumpAndSettle();
      expect(l.history, isEmpty);
      expect(l.favorites.length, 5);
      await tester.pumpWidget(const SizedBox());
      l.dispose();
    },
  );
}
