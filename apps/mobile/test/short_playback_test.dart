import 'package:duoscene/app/theme.dart';
import 'package:duoscene/features/experience/short_playback.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends PlaybackSession {
  int mediaGeneration = 1;
  final seeks = <Duration>[];
  @override
  int get generation => mediaGeneration;
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'tiktok scrub line rejects a seek after media replacement and seeks on drag end',
    (tester) async {
      final session = _Session();
      session.core.duration = const Duration(minutes: 3);
      Future<void> noop() async {}
      final player = PlayerPresentation(
        session: session,
        settings: noop,
        network: noop,
        local: noop,
        screenshots: noop,
        capture: noop,
        pip: noop,
        toggle: noop,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: duosceneTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 300,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: ShortScrubLine(
                    key: const Key('short-seek'),
                    player: player,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final seekKey = find.byKey(const Key('short-seek'));
      final width = tester.getSize(seekKey).width;
      final detector = tester.widget<GestureDetector>(
        find
            .descendant(of: seekKey, matching: find.byType(GestureDetector))
            .first,
      );
      // 换代拒绝：拖动开始后媒体被替换，松手不得落 seek。
      detector.onHorizontalDragStart!(
        DragStartDetails(localPosition: Offset(width / 2, 12)),
      );
      session.mediaGeneration++;
      detector.onHorizontalDragEnd!(DragEndDetails());
      expect(session.seeks, isEmpty);
      // 同一代内拖到 3/4 处松手：整长 3 分钟 → seek 到 135 秒。
      detector.onHorizontalDragStart!(
        DragStartDetails(localPosition: Offset(width / 2, 12)),
      );
      detector.onHorizontalDragUpdate!(
        DragUpdateDetails(
          globalPosition: Offset.zero,
          localPosition: Offset(width * .75, 12),
        ),
      );
      detector.onHorizontalDragEnd!(DragEndDetails());
      expect(session.seeks, [const Duration(milliseconds: 135000)]);
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      session.dispose();
    },
  );
}
