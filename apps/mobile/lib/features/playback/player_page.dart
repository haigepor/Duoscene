import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import '../../app/theme.dart';
import '../../design/tokens.dart';
import 'playback_session.dart';
import 'playback_source.dart';
import 'player_audio.dart';
import 'playra/player_support.dart';
import 'playra/widgets/player_screenshot_image.dart';
import 'widgets/player_surface.dart';
import 'widgets/player_settings.dart';
import 'widgets/player_library_view.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.roomName,
    this.roomId,
    this.initialSource,
    this.session,
    this.presentation,
    this.canStartPlayback,
    this.onManualPause,
    this.respectSafeArea = true,
    this.title,
    this.subtitle,
    this.onMore,
  });
  final String roomName;
  final String? roomId;
  final PlaybackSource? initialSource;
  final PlaybackSession? session;
  final Widget Function(BuildContext, PlayerPresentation, Widget)? presentation;
  final bool Function()? canStartPlayback;
  final VoidCallback? onManualPause;
  final String? title;
  final String? subtitle;
  final VoidCallback? onMore;

  /// 竖屏信息流等全屏媒体页传 false：画面顶到状态栏后，控件自行避开安全区。
  final bool respectSafeArea;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  static const stylePreview =
      kIsWeb && bool.fromEnvironment('DUOSCENE_STYLE_PREVIEW');
  late final s = widget.session ?? PlaybackSession();
  PlayerAudio? _audio;
  bool _fullscreen = false;
  bool _pip = false;
  bool _enteringPip = false;
  bool _background = false;
  bool _closing = false;
  String? _initialError;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  BuildContext get _panelContext => _scaffoldKey.currentContext ?? context;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlatformEnvironmentService.channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged' && mounted)
        setState(() => _pip = call.arguments == true);
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    // 浏览器样式预览复用页面与控制器外观，不启动 Android 插件或真实媒体。
    if (stylePreview) return;
    try {
      await s.prepare();
      if (_closing) return;
      _audio = await PlayerAudio.instance();
      if (_closing) return;
      await _audio!.attach(
        s,
        play: () async {
          if (widget.canStartPlayback?.call() != false) await s.play();
        },
        pause: () async {
          widget.onManualPause?.call();
          await s.pause();
        },
        seek: s.seek,
      );
      if (widget.initialSource != null)
        await s.setPlaylist([widget.initialSource!]);
    } catch (_) {
      if (mounted) setState(() => _initialError = '播放器初始化失败，请重试。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing || stylePreview) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(s.preferences.updateNetworkCost());
      unawaited(s.core.setPrefetchSuspended(false));
    } else if (state == AppLifecycleState.paused &&
        !_pip &&
        !_enteringPip &&
        !_background) {
      unawaited(s.pause());
      unawaited(s.core.setPrefetchSuspended(true));
    }
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    PlatformEnvironmentService.channel.setMethodCallHandler(null);
    unawaited(_audio?.detach(owner: s));
    if (!stylePreview)
      unawaited(
        ScreenBrightnessPlatform.instance
            .resetApplicationScreenBrightness()
            .catchError((Object _) {}),
      );
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    if (widget.session == null) s.dispose();
    super.dispose();
  }

  Future<void> _fullscreenToggle() async {
    setState(() => _fullscreen = !_fullscreen);
    await SystemChrome.setPreferredOrientations(
      _fullscreen
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
    );
    await SystemChrome.setEnabledSystemUIMode(
      _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _enterPip() async {
    if (!Platform.isAndroid) {
      _notice('此版本仅接入 Android 画中画。');
      return;
    }
    _enteringPip = true;
    try {
      final success = await PlatformEnvironmentService.channel
          .invokeMethod<bool>('enterPip', {
            'width': s.debug.playerWidth > 0 ? s.debug.playerWidth : 16,
            'height': s.debug.playerHeight > 0 ? s.debug.playerHeight : 9,
          });
      if (success != true) _notice('此设备不支持画中画，需要 Android 8.0 及系统支持。');
    } finally {
      _enteringPip = false;
    }
  }

  void _notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sourcePicker({bool local = false}) async {
    if (stylePreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网页用于样式预览；视频播放与双人同步请在 Android 端体验。')),
      );
      return;
    }
    PlaybackSource? source;
    if (local) {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '视频',
            extensions: ['mp4', 'mkv', 'mov', 'webm', 'm4v'],
            mimeTypes: ['video/*'],
          ),
        ],
      );
      if (file != null)
        source = PlaybackSource.local(file.path, title: file.name);
    } else if (mounted) {
      source = await showModalBottomSheet<PlaybackSource>(
        context: _panelContext,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => const _NetworkSourceForm(),
      );
    }
    if (source == null || !mounted) return;
    final items = [...s.playlist, source];
    try {
      await s.setPlaylist(items, index: items.length - 1);
    } on FormatException catch (error) {
      _notice(error.message.toString());
    }
  }

  Future<void> _settings() => showPlayerSettings(
    _panelContext,
    s,
    pip: _enterPip,
    capture: s.capture,
    screenshots: _screenshots,
    background: _background,
    toggleBackground: () async {
      if (!_background && Platform.isAndroid)
        await PlatformEnvironmentService.channel.invokeMethod<void>(
          'requestNotifications',
        );
      if (mounted) setState(() => _background = !_background);
    },
    seek: s.seek,
    rate: s.setRate,
  );
  Future<void> _togglePlayback() async {
    if (s.core.playerPlaying) {
      widget.onManualPause?.call();
      await s.pause();
    } else if (widget.canStartPlayback?.call() != false) {
      await (_audio?.play() ?? s.play());
    }
  }

  Future<void> _screenshots() => showModalBottomSheet<void>(
    context: _panelContext,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Observer(
          builder: (_) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '挑选截图',
                        style: TextStyle(
                          fontSize: DS.pageTitleSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: s.screenshots.selectedCount == 0
                          ? null
                          : () => unawaited(_saveScreenshots()),
                      child: const Text('保存到相册'),
                    ),
                    IconButton(
                      tooltip: '移除所选截图',
                      onPressed: s.screenshots.removeSelected,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              if (s.screenshots.message case final String message)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(message),
                ),
              Expanded(
                child: s.screenshots.candidates.isEmpty
                    ? const Center(child: Text('还没有截图，先截取当前画面。'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 280,
                              childAspectRatio: 16 / 11,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: s.screenshots.candidates.length,
                        itemBuilder: (context, index) {
                          final item = s.screenshots.candidates[index];
                          return Observer(
                            builder: (_) => InkWell(
                              onTap: () => s.screenshots.toggle(item),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        PlayerScreenshotImage(
                                          bytes: item.bytes,
                                          cacheWidth: 480,
                                        ),
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: Checkbox(
                                            value: s.screenshots.isSelected(
                                              item,
                                            ),
                                            onChanged: (_) =>
                                                s.screenshots.toggle(item),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${item.title} · ${item.timeLabel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _saveScreenshots() => s.screenshots.save(
    chooseDestination: () async {
      if (Platform.isAndroid) {
        final granted = await PlatformEnvironmentService.channel
            .invokeMethod<bool>('requestGalleryPermission');
        if (granted != true) throw StateError('Gallery permission denied');
      }
      return 'gallery';
    },
    write: (item, _) async {
      final result = await SaverGallery.saveImage(
        item.bytes,
        fileName: 'duoscene_${item.id}',
        extension: 'png',
        skipIfExists: false,
      );
      if (!result.isSuccess) throw StateError('Unable to save screenshot');
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 播放器是媒体暗色环境：Scaffold 底色与画面一致，SafeArea 外露出的
    // 状态栏/导航条区域不再用内容页的米白底。
    return mediaSystemBars(
      context,
      Theme(
        data: theme,
        child: PopScope(
          canPop: !_fullscreen,
          onPopInvokedWithResult: (popped, _) {
            if (!popped && _fullscreen) unawaited(_fullscreenToggle());
          },
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: DSPalette.media,
            body: SafeArea(
              top: !_fullscreen && widget.respectSafeArea,
              bottom: !_fullscreen,
            child: AnimatedBuilder(
              animation: s.presentationChanges,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final surface = PlayerSurface(
                    session: s,
                    fullscreen: _fullscreen,
                    pictureInPicture: _pip,
                    title: widget.title,
                    subtitle: widget.subtitle,
                    onMore: widget.onMore,
                    onFullscreen: () => unawaited(_fullscreenToggle()),
                    onBack: () {
                      if (_fullscreen) {
                        unawaited(_fullscreenToggle());
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    onSettings: _settings,
                    onScreenshots: _screenshots,
                    onPip: _enterPip,
                    onToggle: _togglePlayback,
                    onSeek: s.seek,
                    onRate: s.setRate,
                  );
                  if (_fullscreen || _pip) return surface;
                  if (widget.presentation != null) {
                    return widget.presentation!(
                      context,
                      PlayerPresentation(
                        session: s,
                        settings: _settings,
                        network: () => _sourcePicker(),
                        local: () => _sourcePicker(local: true),
                        screenshots: _screenshots,
                        capture: s.capture,
                        pip: _enterPip,
                        toggle: _togglePlayback,
                        error: _initialError,
                      ),
                      surface,
                    );
                  }
                  return PlayerLibraryView(
                    roomName: widget.roomName,
                    surface: surface,
                    player: PlayerPresentation(
                      session: s,
                      settings: _settings,
                      network: () => _sourcePicker(),
                      local: () => _sourcePicker(local: true),
                      screenshots: _screenshots,
                      capture: s.capture,
                      pip: _enterPip,
                      toggle: _togglePlayback,
                      error: _initialError,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }
}

/// 产品页面只组合界面，播放器仍由原页面持有，统一管理音频、PIP 和销毁。
class PlayerPresentation {
  const PlayerPresentation({
    required this.session,
    required this.settings,
    required this.network,
    required this.local,
    required this.screenshots,
    required this.capture,
    required this.pip,
    required this.toggle,
    this.error,
  });
  final PlaybackSession session;
  final Future<void> Function() settings,
      network,
      local,
      screenshots,
      capture,
      pip,
      toggle;
  final String? error;
}

class _NetworkSourceForm extends StatefulWidget {
  const _NetworkSourceForm();
  @override
  State<_NetworkSourceForm> createState() => _NetworkSourceFormState();
}

class _NetworkSourceFormState extends State<_NetworkSourceForm> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _headers = TextEditingController();
  String? _error;
  bool _hls = false;
  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _headers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '载入视频',
              style: TextStyle(
                fontSize: DS.pageTitleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('media-title'),
              controller: _title,
              maxLength: 100,
              decoration: const InputDecoration(labelText: '视频名称（选填）'),
            ),
            TextField(
              key: const Key('media-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 4096,
              decoration: const InputDecoration(
                labelText: 'MP4 / HLS 地址',
                hintText: 'https://…',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('按 HLS 打开'),
              subtitle: const Text('地址无 .m3u8 后缀时可手动开启'),
              value: _hls,
              onChanged: (value) => setState(() => _hls = value),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('媒体请求头（选填）'),
              children: [
                TextField(
                  controller: _headers,
                  maxLines: 3,
                  maxLength: 16000,
                  decoration: const InputDecoration(
                    hintText: '{"Referer":"https://…"}',
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: () {
                try {
                  final parsed = _headers.text.trim().isEmpty
                      ? <String, dynamic>{}
                      : jsonDecode(_headers.text);
                  if (parsed is! Map<String, dynamic> ||
                      parsed.values.any((value) => value is! String))
                    throw const FormatException('请求头必须为字符串 JSON 对象。');
                  final source = PlaybackSource.network(
                    _url.text,
                    title: _title.text,
                    headers: parsed.cast<String, String>(),
                    hls: _hls ? true : null,
                  );
                  Navigator.pop(context, source);
                } on FormatException catch (error) {
                  setState(() => _error = error.message);
                }
              },
              child: const Text('载入视频'),
            ),
          ],
        ),
      ),
    ),
  );
}
