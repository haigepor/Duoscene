import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/catalog/app_shell.dart';
import 'package:duoscene/features/catalog/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 交互打磨的回归用例：双击当前标签回顶、下拉刷新外壳。
void main() {
  testWidgets('re-selecting the current tab asks the page to scroll to top', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(theme: duosceneTheme, home: const AppShell(preview: true)),
    );
    await t.pumpAndSettle();
    final home = t.state<State<WatchHome>>(find.byType(WatchHome));
    final library = home.widget.library;
    final before = library.scrollTopRequest.value;

    await t.tap(find.byKey(const Key('tab-0')));
    await t.pump();
    expect(library.scrollTopRequest.value, before + 1);

    // 连点两次应各自发一次信号，页面侧自行去重（已在顶部时不动）。
    await t.tap(find.byKey(const Key('tab-0')));
    await t.pump();
    expect(library.scrollTopRequest.value, before + 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('home list is wrapped in a pull-to-refresh host', (t) async {
    await t.pumpWidget(
      MaterialApp(theme: duosceneTheme, home: const AppShell(preview: true)),
    );
    await t.pumpAndSettle();
    expect(find.byType(RefreshIndicator), findsWidgets);
    // 片库很短时也要能下拉触发，列表必须允许在顶部继续拖动。
    final list = find.descendant(
      of: find.byType(RefreshIndicator).first,
      matching: find.byType(ListView),
    );
    expect(list, findsWidgets);
    expect(
      t.widget<ListView>(list.first).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('gesture hint only exists for remote feeds', (t) async {
    // 预览模式没有真实片源，双击收藏与滑动手势都无意义，不应出现引导。
    await t.pumpWidget(
      MaterialApp(theme: duosceneTheme, home: const AppShell(preview: true)),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tab-1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('short-gesture-hint')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
