import 'dart:convert';
import 'dart:io';

import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/tokens.dart';
import 'package:duoscene/features/catalog/collection_pages.dart';
import 'package:duoscene/features/catalog/library_state.dart';
import 'package:duoscene/features/catalog/profile_page.dart';
import 'package:duoscene/features/catalog/posters.dart';
import 'package:duoscene/features/experience/invite_pages.dart';
import 'package:duoscene/features/catalog/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('literal SVG icon references resolve to non-empty bundled assets', () {
    for (final film in films) {
      for (final name in [
        film.image,
        homeArtwork(film),
        homeArtwork(film, landscape: true),
      ]) {
        final media = File(name);
        expect(media.existsSync(), isTrue, reason: name);
        expect(media.lengthSync(), greaterThan(0), reason: name);
      }
    }
    final names = RegExp(r"DSIcon\(\s*'([^'$]+)'");
    for (final source in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!source.path.endsWith('.dart')) continue;
      for (final match in names.allMatches(
        source.readAsStringSync(encoding: utf8),
      )) {
        final asset = File('assets/design/icons/${match.group(1)}.svg');
        expect(
          asset.existsSync(),
          isTrue,
          reason: '${source.path}: ${asset.path}',
        );
        expect(asset.lengthSync(), greaterThan(0), reason: asset.path);
      }
    }
  });

  testWidgets('history and profile use the same compact toolbar baseline', (
    t,
  ) async {
    final library = LibraryState(accountId: 'alignment', preview: true);
    Future<void> show(Widget page) => t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: Scaffold(body: page),
      ),
    );
    await show(HistoryPage(library: library, onBrowse: () {}));
    await t.pumpAndSettle();
    final historyTop = t.getTopLeft(find.text('观看记录')).dy;
    await show(ProfilePage(library: library));
    await t.pumpAndSettle();
    expect(historyTop, closeTo(t.getTopLeft(find.text('我的')).dy, 2));
    expect(historyTop, lessThan(DS.toolbarHeight));
    await t.pumpWidget(const SizedBox());
    library.dispose();
  });

  testWidgets(
    'invitation sheet resets media text colors and scrolls at 200 percent',
    (t) async {
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final library = LibraryState(accountId: 'sheet-colors', preview: true);
      for (final p in [DSPalette.light, DSPalette.dark]) {
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildDuosceneTheme(p),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),
                  child: TextButton(
                    onPressed: () => showInvite(
                      context,
                      film: films.first,
                      library: library,
                    ),
                    child: const Text('打开邀请'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('打开邀请'));
        await t.pumpAndSettle();
        expect(
          DefaultTextStyle.of(t.element(find.text('邀请好友一起看'))).style.color,
          p.ink,
        );
        await t.ensureVisible(find.text('复制邀请'));
        await t.pumpAndSettle();
        expect(find.text('复制邀请').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
      library.dispose();
    },
  );
}
