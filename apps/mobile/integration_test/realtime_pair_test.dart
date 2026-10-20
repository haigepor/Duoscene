import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:duoscene/app/duoscene_app.dart';
import 'package:duoscene/features/auth/session.dart';
import 'package:duoscene/features/auth/token_store.dart';
import 'package:duoscene/core/api_client.dart';
import 'package:duoscene/design/theme_preferences.dart';
import 'package:duoscene/features/experience/appearance_page.dart';
import 'package:duoscene/features/playback/player_page.dart';
import 'package:duoscene/features/playback/playback_session.dart';
import 'package:duoscene/features/playback/playra/player_support.dart';
import 'package:duoscene/features/realtime/room_watch_page.dart';
import 'package:duoscene/features/realtime/room_connection.dart';
import 'package:duoscene/features/voice/room_voice.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two Android users: room invitation, media sync, private chat and WebRTC',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      const role = String.fromEnvironment('TEST_ROLE');
      const fixture = String.fromEnvironment('PAIR_FIXTURE');
      const api = String.fromEnvironment('API_BASE_URL');
      const owner = role == 'owner';
      Future<void> pump([int count = 3]) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> until(
        bool Function() condition,
        String reason, {
        int seconds = 70,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(end)) {
          await pump(2);
        }
        expect(condition(), true, reason: reason);
      }

      Future<Map<String, dynamic>> get(String path) async => (jsonDecode(
        (await http.get(Uri.parse('$fixture/$path'))).body,
      ) as Map).cast<String, dynamic>();
      Future<void> report(
        String phase, [
        Map<String, dynamic> details = const {},
      ]) async {
        await http.post(
          Uri.parse('$fixture/report/$role'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'phase': phase, ...details}),
        );
      }

      Future<void> barrier(String phase) async {
        await report(phase);
        final end = DateTime.now().add(const Duration(seconds: 80));
        while (DateTime.now().isBefore(end)) {
          final data = await get('phases');
          if ((data[owner ? 'guest' : 'owner'] as List? ?? []).contains(phase))
            return;
          await pump(3);
        }
        fail('Other Android client did not reach $phase');
      }

      Future<void> tap(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await pump(5);
        await tester.ensureVisible(finder);
        await pump(5);
        await tester.tap(finder.hitTestable().first);
        await pump(5);
      }

      final auth = Session(ApiClient(Uri.parse(api)), _MemoryStore());
      await auth.restore();
      final preferences = PlaybackPreferences();
      await preferences.load();
      await preferences.putSetting(SettingsKeys.androidVideoRenderer, 'gpu');
      await preferences.dispose();
      await tester.pumpWidget(DuosceneApp(session: auth));
      await pump(8);
      final username = owner
          ? const String.fromEnvironment('TEST_OWNER')
          : const String.fromEnvironment('TEST_GUEST');
      const initialPassword = String.fromEnvironment('TEST_PASSWORD');
      final password = '$initialPassword-reset';
      await tap(find.text('注册账号'));
      Future<void> fill(String key, String value) async {
        final field = find.byKey(Key('access-$key'));
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
      }

      await fill('username', username);
      await fill('nickname', owner ? '知夏' : '小满');
      await fill('password', initialPassword);
      await fill('repeat', initialPassword);
      await tap(find.text('创建账号'));
      await until(
        () =>
            find.byKey(const Key('issued-recovery-code')).evaluate().isNotEmpty,
        'registration issues recovery code',
      );
      final recovery = tester
          .widget<SelectableText>(find.byKey(const Key('issued-recovery-code')))
          .data!;
      await tap(find.byType(CheckboxListTile));
      await tap(find.text('返回登录'));
      await tap(find.text('忘记密码？'));
      await fill('username', username);
      await fill('recovery', recovery);
      await fill('password', password);
      await fill('repeat', password);
      await tap(find.text('重设密码'));
      await until(
        () =>
            find.byKey(const Key('issued-recovery-code')).evaluate().isNotEmpty,
        'password recovery rotates code',
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('issued-recovery-code')),
            )
            .data,
        isNot(recovery),
      );
      await tap(find.byType(CheckboxListTile));
      await tap(find.text('返回登录'));
      await report('register-recover');
      await tap(find.byTooltip('切换外观'));
      await tap(find.text('晴空'));
      await tap(find.text('深色'));
      expect(Theme.of(tester.element(find.byType(AppearancePage))).brightness,
        Brightness.dark);
      await tap(find.text('森林'));
      await tap(find.text('晴空'));
      await tap(find.text('浅色'));
      expect(Theme.of(tester.element(find.byType(AppearancePage))).brightness,
        Brightness.light);
      await tap(find.byTooltip('返回'));
      await report('appearance-controls');
      await tester.enterText(find.byKey(const Key('username')), username);
      await tester.enterText(find.byKey(const Key('password')), password);
      await tap(find.text('登录 Duoscene'));
      await until(
        () => find.byKey(const Key('tab-3')).evaluate().isNotEmpty,
        'real login',
      );
      await tap(find.byKey(const Key('tab-3')));
      await tap(find.text('观影邀请'));
      await tap(find.text('邀请与房间'));
      await until(() => find.text('我们的房间').evaluate().isNotEmpty, 'room list');
      if (owner) {
        await tap(find.text('创建房间'));
        await tester.enterText(find.byKey(const Key('room-name')), '两个人的实时影院');
        await tap(find.text('创建并进入'));
        await until(
          () => find.text('1 / 2 席').evaluate().isNotEmpty,
          'owner room',
        );
        await tap(find.text('生成一次性邀请'));
        await until(
          () => find.text('复制邀请码').evaluate().isNotEmpty,
          'invite creation',
        );
        await tap(find.text('复制邀请码'));
        final token = (await Clipboard.getData('text/plain'))!.text!;
        expect(token.length, 43);
        await http.post(
          Uri.parse('$fixture/invite'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'token': token}),
        );
      } else {
        Map<String, dynamic> invitation = {};
        final end = DateTime.now().add(const Duration(seconds: 80));
        while (invitation['token'] == null && DateTime.now().isBefore(end)) {
          invitation = await get('invite');
          await pump(3);
        }
        expect(invitation['token'], isNotNull);
        await tap(find.text('使用邀请码加入'));
        await tester.enterText(
          find.byKey(const Key('invite-token')),
          invitation['token'] as String,
        );
        await tap(find.text('加入房间'));
        await until(
          () => find.text('2 / 2 席').evaluate().isNotEmpty,
          'guest joins by form',
        );
      }
      await barrier('joined');
      if (owner) {
        await tap(find.byTooltip('刷新成员'));
        await until(
          () => find.text('2 / 2 席').evaluate().isNotEmpty,
          'both membership rows',
        );
      }
      await tap(find.text('打开播放器'));
      await until(
        () => find.byType(RoomWatchPage).evaluate().isNotEmpty,
        'live watch entry',
      );
      // 读取当前路由已创建的公共控制器，不替换真实页面或网络。
      final dynamic page = tester.state(find.byType(RoomWatchPage));
      final RoomConnection room = page.room as RoomConnection;
      final RoomVoice voice = page.voice as RoomVoice;
      final PlaybackSession player = tester
          .widget<PlayerPage>(find.byType(PlayerPage))
          .session!;
      await until(
        () =>
            room.connected &&
            (room.snapshot?['peers'] as List? ?? []).length == 2,
        'two WS clients',
      );
      Future<void> choose(String url, String title) async {
        if (find.text('视频地址').hitTestable().evaluate().isNotEmpty) {
          await tap(find.text('视频地址'));
        } else {
          await tap(find.text('视频').hitTestable());
          await tap(find.text('更换视频地址'));
        }
        await tester.enterText(find.byKey(const Key('media-title')), title);
        await tester.enterText(find.byKey(const Key('media-url')), url);
        await tap(find.widgetWithText(FilledButton, '载入视频'));
        if (find.text('交流').evaluate().isNotEmpty) await tap(find.text('交流'));
      }

      if (owner) await choose('$fixture/media/video.mp4', '本地 MP4 双人测试');
      await until(
        () =>
            player.source != null &&
            player.core.playerDuration > Duration.zero &&
            player.debug.playerWidth > 0,
        'native first frame',
      );
      await until(
        () =>
            (room.snapshot?['ready'] as Map? ?? {}).length == 2 &&
            (room.snapshot!['ready'] as Map).values.every((e) => e == true),
        'both decoded and ready',
      );
      await barrier('media-ready');
      if (owner) {
        await player.play();
        await until(
          () => room.snapshot?['playing'] == true && player.core.playerPlaying,
          'owner play',
        );
      } else
        await until(() => player.core.playerPlaying, 'guest follows play');
      await barrier('playing');
      // 切换外观只能重绘界面，不能重建媒体或 WebSocket 控制器。
      final appearance = ThemePreferencesScope.of(
        tester.element(find.byType(RoomWatchPage)),
      )!;
      final nativePlayer = player.core.mediaPlayer;
      for (final theme in [DSTheme.forest, DSTheme.sky]) {
        await appearance.change(theme: theme, brightness: ThemeMode.light);
        await pump(5);
        expect(identical(page.room, room), isTrue);
        expect(identical(player.core.mediaPlayer, nativePlayer), isTrue);
        expect(room.connected, isTrue);
        expect(player.core.playerPlaying, isTrue);
      }
      await appearance.change(brightness: ThemeMode.dark);
      await pump(5);
      expect(identical(player.core.mediaPlayer, nativePlayer), isTrue);
      await appearance.change(brightness: ThemeMode.light);
      await barrier('theme-preserved');
      if (owner) {
        await player.seek(const Duration(seconds: 10));
      }
      await until(
        () => player.core.playerPosition.inSeconds >= 9,
        'both seek to 10s',
      );
      await barrier('seeked');
      if (owner) {
        await player.setRate(1.5);
      }
      await until(
        () => (player.core.playerSpeed - 1.5).abs() < .02,
        'rate follows',
      );
      await barrier('rate');
      if (owner) {
        await player.pause();
      }
      await until(
        () => !player.core.playerPlaying && room.snapshot?['wanted'] == false,
        'manual pause',
      );
      await tester.enterText(
        find.byKey(const Key('live-chat-input')),
        owner ? '我已经准备好了，一起看吧' : '收到，我们已经同步啦',
      );
      await pump(8);
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(identical(player.core.mediaPlayer, nativePlayer), isTrue,
        reason: 'opening the keyboard must retain the native player');
      await tap(find.byKey(const Key('live-chat-send')));
      await until(
        () => room.messages.any(
          (m) => m['text'] == (owner ? '收到，我们已经同步啦' : '我已经准备好了，一起看吧'),
        ),
        'real private chat reaches peer',
      );
      await barrier('chat');
      await tap(find.byKey(const Key('voice-toggle')));
      await until(() => voice.enabled, 'real microphone permission');
      await until(
        () => voice.state == '语音已连接',
        'WebRTC connected through TURN',
        seconds: 80,
      );
      final statsEnd = DateTime.now().add(const Duration(seconds: 20));
      while ((voice.bytesReceived == 0 || voice.bytesSent == 0) &&
          DateTime.now().isBefore(statsEnd)) {
        await voice.sampleStats();
        await pump(5);
      }
      expect(voice.bytesReceived, greaterThan(0));
      expect(voice.bytesSent, greaterThan(0));
      await report('voice-stats', {
        'bytesReceived': voice.bytesReceived,
        'bytesSent': voice.bytesSent,
        'state': voice.state,
      });
      await barrier('voice');
      await tap(find.byKey(const Key('voice-toggle')));
      expect(voice.muted, true);
      expect(voice.stream!.getAudioTracks().every((t) => !t.enabled), true);
      await tap(find.byKey(const Key('voice-toggle')));
      expect(voice.muted, false);
      await binding.convertFlutterSurfaceToImage();
      await pump(3);
      await http.post(
        Uri.parse('$fixture/capture/$role.png'),
        headers: {'content-type': 'image/png'},
        body: await binding.takeScreenshot('live-$role'),
      );
      await barrier('captured');
      if (!owner) {
        await room.reconnect();
      }
      await until(
        () =>
            room.connected &&
            (room.snapshot?['peers'] as List? ?? []).length == 2,
        'reconnected clients',
      );
      await pump(20);
      expect(
        player.core.playerPlaying,
        false,
        reason: 'reconnect never cancels manual pause',
      );
      if (!owner)
        expect(
          voice.enabled,
          false,
          reason: 'reconnect requires explicit microphone opt-in',
        );
      await barrier('reconnected');
      if (owner) {
        await choose('$fixture/media/main.m3u8', '本地 HLS 双人测试');
      }
      await until(
        () =>
            player.source?.isHls == true &&
            !player.loading &&
            player.core.playerDuration > Duration.zero,
        'both follow HLS switch',
      );
      await barrier('hls');
      expect(tester.takeException(), isNull);
      await voice.leave();
      await tester.pumpWidget(const SizedBox());
      await pump(5);
      await auth.logout();
      auth.dispose();
      await Clipboard.setData(const ClipboardData(text: ''));
      await report('complete');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

class _MemoryStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
