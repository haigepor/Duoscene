import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duoscene/features/playback/playra/widgets/player_transport_bar.dart';

void main() {
  testWidgets(
    'Playra transport remains usable on narrow screens and large text',
    (tester) async {
      for (final width in [320.0, 640.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 500),
                textScaler: const TextScaler.linear(2),
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: PlayerTransportBar(
                      compact: width < 580,
                      playPause: IconButton(
                        tooltip: '播放',
                        onPressed: () {},
                        icon: const Icon(Icons.play_arrow),
                      ),
                      nextEpisode: const SizedBox(width: 48, height: 48),
                      progressBuilder: (placement) => ProgressBar(
                        progress: const Duration(seconds: 12),
                        total: const Duration(seconds: 32),
                        timeLabelLocation: placement,
                      ),
                      timeLabel: const Text(
                        '00:12 / 00:32',
                        style: TextStyle(fontSize: 11),
                      ),
                      timePlacement: PlayerTimeLabelPlacement.aboveProgress,
                      controls: const SizedBox(height: 48),
                      fullscreen: IconButton(
                        tooltip: '全屏',
                        onPressed: () {},
                        icon: const Icon(Icons.fullscreen),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'width=$width');
        expect(find.byTooltip('播放'), findsOneWidget);
        expect(find.byTooltip('全屏'), findsOneWidget);
      }
    },
  );
}
