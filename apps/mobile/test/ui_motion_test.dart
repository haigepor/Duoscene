import 'package:duoscene/app/theme.dart';
import 'package:duoscene/design/motion.dart';
import 'package:duoscene/design/components.dart';
import 'package:duoscene/design/scroll_chrome.dart';
import 'package:duoscene/features/experience/preview_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'selected media rows paint and respond above the forest backdrop',
    (t) async {
      var taps = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: Forest(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('本地视频'),
                    selected: true,
                    onTap: () => taps++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('本地视频'));
      await t.pumpAndSettle();
      expect(taps, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'tab reversal is continuous, preserves state and excludes inactive focus',
    (t) async {
      var index = 0;
      late StateSetter update;
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: MotionTabs(
                  index: index,
                  children: const [
                    _CounterPage(key: Key('a')),
                    _CounterPage(key: Key('b')),
                    _CounterPage(key: Key('c')),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await t.tap(find.text('count 0'));
      await t.pump();
      update(() => index = 1);
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      final before = t.getTopLeft(find.byKey(const Key('a'))).dx;
      update(() => index = 0);
      await t.pump();
      expect(t.getTopLeft(find.byKey(const Key('a'))).dx, closeTo(before, .01));
      await t.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
      expect(find.text('count 0'), findsNothing);
      expect(find.byKey(const Key('b'), skipOffstage: false), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'reduced motion switches immediately without retaining a transition',
    (t) async {
      var index = 0;
      late StateSetter update;
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Scaffold(
                  body: MotionTabs(
                    index: index,
                    children: const [Text('first'), Text('second')],
                  ),
                );
              },
            ),
          ),
        ),
      );
      update(() => index = 1);
      await t.pump();
      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
      expect(t.hasRunningAnimations, false);
    },
  );
  testWidgets(
    'scroll header fades continuously and stays pinned while content scrolls',
    (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollChrome(
              header: const SizedBox(height: 48, child: Text('header')),
              child: ListView(
                controller: controller,
                children: const [SizedBox(height: 1600)],
              ),
            ),
          ),
        ),
      );
      double alpha() =>
          (t
                      .widget<DecoratedBox>(
                        find.byKey(const Key('scroll-chrome')),
                      )
                      .decoration
                  as BoxDecoration)
              .color!
              .a;
      expect(alpha(), 0);
      controller.jumpTo(36);
      await t.pump();
      await t.pump();
      expect(alpha(), closeTo(.49, .02));
      expect(t.getTopLeft(find.text('header')).dy, 0);
      controller.jumpTo(100);
      await t.pump();
      await t.pump();
      expect(alpha(), closeTo(.98, .02));
      controller.jumpTo(0);
      await t.pump();
      await t.pump();
      expect(alpha(), 0);
      await t.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('short scroll extents complete the header fade at the end', (
    t,
  ) async {
    final controller = ScrollController();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollChrome(
            header: const SizedBox(height: 48),
            child: ListView(
              controller: controller,
              children: const [SizedBox(height: 640)],
            ),
          ),
        ),
      ),
    );
    expect(controller.position.maxScrollExtent, lessThan(72));
    controller.jumpTo(controller.position.maxScrollExtent);
    await t.pump();
    await t.pump();
    final decoration =
        t
                .widget<DecoratedBox>(find.byKey(const Key('scroll-chrome')))
                .decoration
            as BoxDecoration;
    expect(decoration.color!.a, closeTo(.98, .01));
    await t.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('compact pages remain scrollable at 320dp and 160 percent text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    for (var page = 0; page < 18; page++) {
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey(page),
          theme: duosceneTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: PreviewHost(page: page, scenario: 'normal'),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'page ${page + 1}');
    }
    await t.pumpWidget(const SizedBox());
  });
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({super.key});
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int value = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => value++),
    child: Text('count $value'),
  );
}
