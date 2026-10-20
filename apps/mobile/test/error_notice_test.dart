import 'package:duoscene/app/theme.dart';
import 'package:duoscene/core/widgets.dart';
import 'package:duoscene/design/components.dart';
import 'package:duoscene/features/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const message = '登录信息无效或已过期，请重新登录。\n参考编号：request-example';
  testWidgets('bubble hides the request ID until details are opened', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: const Scaffold(body: ErrorNotice(message)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('登录信息无效或已过期，请重新登录。'), findsOneWidget);
    expect(find.textContaining('request-example'), findsNothing);
    expect(t.widgetList<DSIcon>(find.byType(DSIcon)).map((i) => i.name), [
      'circle-alert',
    ]);
    await t.tap(find.text('登录信息无效或已过期，请重新登录。'));
    await t.pumpAndSettle();
    expect(find.text('提示详情'), findsNothing);
    expect(t.getSize(find.byTooltip('查看错误详情')).width, greaterThanOrEqualTo(48));
    await t.tap(find.byTooltip('查看错误详情'));
    await t.pumpAndSettle();
    expect(find.textContaining('request-example'), findsOneWidget);
    await t.tap(find.text('知道了'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 7));
    expect(find.text('登录信息无效或已过期，请重新登录。'), findsOneWidget);
  });

  testWidgets(
    'floating bubble dismisses, restarts for new errors and respects accessible navigation',
    (t) async {
      var text = message;
      var accessible = false;
      late StateSetter update;
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(accessibleNavigation: accessible),
                child: Scaffold(body: ErrorNotice(text, floating: true)),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.widgetList<DSIcon>(find.byType(DSIcon)).map((i) => i.name), [
        'circle-alert',
        'x',
      ]);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.byTooltip('关闭提示'), findsNothing);
      update(() => text = '连接暂时中断，请重试。');
      await t.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      await t.tap(find.byTooltip('关闭提示'));
      await t.pumpAndSettle();
      expect(find.text(text), findsNothing);
      expect(find.text('提示详情'), findsNothing);
      update(() {
        accessible = true;
        text = '请重新登录。';
      });
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 7));
      expect(find.text(text), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('login bubble does not move the form at 320dp with large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    var error = false;
    late StateSetter update;
    await t.pumpWidget(
      MaterialApp(
        theme: duosceneTheme,
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: LoginPage(
                key: ValueKey(error),
                session: null,
                previewError: error,
              ),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    final original = t.getTopLeft(find.byKey(const Key('username')));
    update(() => error = true);
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const Key('username'))), original);
    expect(find.text('登录信息无效，请检查账户和密码。'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
