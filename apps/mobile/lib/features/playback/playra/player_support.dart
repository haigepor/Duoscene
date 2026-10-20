import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'dart:io' show Platform;

export 'services/async_serial_queue.dart';
export 'services/player_error_mapper.dart';
export 'services/playback_start_position.dart';

enum VideoSourceFormat { auto, hls }

enum SettingsKeys {
  defaultSuperResolutionMode,
  hAenable,
  androidEnableOpenSLES,
  hardwareDecoder,
  autoPlay,
  playerDebugMode,
  proxyEnable,
  proxyUrl,
  androidVideoRenderer,
  showPlayerError,
  defaultPlaySpeed,
  lowMemoryMode,
  lowMemoryPolicy,
  skipSeconds,
}

enum LowMemoryMode {
  auto,
  always,
  never;

  bool isEnabled({required bool isMetered, bool isLocalPlayback = false}) =>
      this == always || (this == auto && isMetered && !isLocalPlayback);
}

/// 仅属于播放器的非敏感设置；账户凭据始终由 auth 的安全存储管理。
class PlaybackPreferences {
  final Map<SettingsKeys, Object> _values = {
    SettingsKeys.defaultSuperResolutionMode: 1,
    SettingsKeys.hAenable: true,
    SettingsKeys.androidEnableOpenSLES: true,
    SettingsKeys.hardwareDecoder: 'auto-safe',
    SettingsKeys.autoPlay: false,
    SettingsKeys.playerDebugMode: false,
    SettingsKeys.proxyEnable: false,
    SettingsKeys.proxyUrl: '',
    SettingsKeys.androidVideoRenderer: 'auto',
    SettingsKeys.showPlayerError: true,
    SettingsKeys.defaultPlaySpeed: 1.0,
    SettingsKeys.lowMemoryMode: false,
    SettingsKeys.lowMemoryPolicy: 'auto',
    SettingsKeys.skipSeconds: 80,
  };
  final _updates = StreamController<void>.broadcast();
  SharedPreferences? _storage;
  bool isMetered = true;
  LowMemoryMode get lowMemoryMode =>
      switch (getSetting<String>(SettingsKeys.lowMemoryPolicy)) {
        'always' => LowMemoryMode.always,
        'never' => LowMemoryMode.never,
        _ => LowMemoryMode.auto,
      };
  T getSetting<T>(SettingsKeys key) => _values[key] as T;
  Stream<void> watchSettings(List<SettingsKeys> _) => _updates.stream;
  Future<void> load() async {
    _storage = await SharedPreferences.getInstance();
    for (final key in SettingsKeys.values) {
      final value = _storage!.get('duoscene.player.${key.name}');
      if (value != null && value.runtimeType == _values[key].runtimeType)
        _values[key] = value;
    }
    await updateNetworkCost();
  }

  Future<void> updateNetworkCost() async {
    // iOS 未取得费用标志时保守使用小缓存，用户仍可显式覆盖。
    if (Platform.isAndroid)
      isMetered =
          await PlatformEnvironmentService.channel.invokeMethod<bool>(
            'isNetworkMetered',
          ) ??
          true;
    _updates.add(null);
  }

  Future<void> putSetting(SettingsKeys key, Object value) async {
    if (value.runtimeType != _values[key].runtimeType)
      throw ArgumentError('Invalid player setting');
    final storage = _storage;
    if (storage != null) {
      final name = 'duoscene.player.${key.name}';
      final saved = switch (value) {
        final bool v => await storage.setBool(name, v),
        final int v => await storage.setInt(name, v),
        final double v => await storage.setDouble(name, v),
        final String v => await storage.setString(name, v),
        _ => false,
      };
      if (!saved) throw StateError('Unable to save player setting');
    }
    _values[key] = value;
    _updates.add(null);
  }

  Future<void> dispose() => _updates.close();
}

String redactPlayerMessage(Object? message) =>
    '$message'.replaceAll(RegExp(r'https?://[^\s\]\)]+'), '[媒体地址]');

class KazumiLogger {
  void i(String value, {bool forceLog = false}) {
    if (kDebugMode) debugPrint(redactPlayerMessage(value));
  }

  void w(String value, {Object? error}) =>
      i('$value ${error == null ? '' : '（操作失败）'}');
  void e(String value, {Object? error, StackTrace? stackTrace}) =>
      w(value, error: error);
}

bool isDesktop() => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
NativePlayer nativePlayerAccess(Player player) =>
    player.platform as NativePlayer;
Future<String> getPlayerTempPath() async =>
    (await getTemporaryDirectory()).path;
Future<String> prepareMediaResource(
  String url,
  Map<String, String> headers,
) async => url;
void releaseMediaResource(
  String url,
) {} // 原 Playra 原生路径没有额外句柄，随 Player.dispose 释放。
Future<void> configureMediaPlayback(
  Player player,
) async {} // Web 网关配置不适用于原生播放器。

class PlatformEnvironmentService {
  static const channel = MethodChannel('duoscene/player');
  static Future<bool> isAndroidEmulator() async =>
      Platform.isAndroid &&
      await const MethodChannel('com.alexmercerind/media_kit_video')
              .invokeMethod<bool>('Utils.IsEmulator') ==
          true;
  static Future<int> getAndroidSdkVersion() async => Platform.isAndroid
      ? await channel.invokeMethod<int>('getAndroidSdkVersion') ?? 0
      : 0;
}

class ProxyUtils {
  static String? getFormattedProxyUrl(String input) {
    final uri = Uri.tryParse(input.contains('://') ? input : 'http://$input');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty)
      return null;
    return uri.origin;
  }
}

const nearEndWatchedThreshold = Duration(seconds: 90);
const mpvAnime4KShaders = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_VL.glsl',
  'Anime4K_Upscale_CNN_x2_VL.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
];
const mpvAnime4KShadersLite = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_M.glsl',
  'Anime4K_Restore_CNN_S.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl',
];
String buildShadersAbsolutePath(String directory, List<String> files) => files
    .map((name) => path.join(directory, name))
    .join(Platform.isWindows ? ';' : ':');

class ShaderAssetService {
  late Directory shadersDirectory;
  Future<void> prepare() async {
    shadersDirectory = Directory(
      path.join(
        (await getApplicationSupportDirectory()).path,
        'player-shaders',
      ),
    );
    await shadersDirectory.create(recursive: true);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets().where(
      (name) => name.startsWith('assets/shaders/') && name.endsWith('.glsl'),
    )) {
      final data = await rootBundle.load(asset);
      // 覆盖旧版本资源，避免升级后继续使用已缓存的旧 shader。
      await File(path.join(shadersDirectory.path, path.basename(asset)))
          .writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
    }
  }
}

String durationToString(Duration duration) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${duration.inHours > 0 ? '${pad(duration.inHours)}:' : ''}${pad(duration.inMinutes % 60)}:${pad(duration.inSeconds % 60)}';
}
