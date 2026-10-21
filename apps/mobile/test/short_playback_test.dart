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
    'short controls fit large text and reject a seek after media replacement',
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
            body: Center(
              child: SizedBox(
                width: 224,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: ShortPlaybackControls(player: player),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final slider = tester.widget<Slider>(find.byKey(const Key('short-seek')));
      expect(slider.onChanged, isNotNull);
      slider.onChangeStart!(0);
      session.mediaGeneration++;
      slider.onChangeEnd!(9000);
      expect(session.seeks, isEmpty);
      slider.onChangeStart!(0);
      slider.onChangeEnd!(12000);
      expect(session.seeks, [const Duration(seconds: 12)]);
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      session.dispose();
    },
  );
}
