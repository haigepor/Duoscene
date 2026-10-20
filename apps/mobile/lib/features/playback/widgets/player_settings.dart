import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../../design/tokens.dart';

import '../playback_session.dart';
import '../playra/player_support.dart';
import '../playra/controller/player_aspect_ratio.dart';
import '../playra/controller/player_super_resolution.dart';

Future<void> showPlayerSettings(
  BuildContext context,
  PlaybackSession session, {
  required Future<void> Function() pip,
  required Future<void> Function() capture,
  required Future<void> Function() screenshots,
  required Future<void> Function() toggleBackground,
  required bool background,
  required Future<void> Function(Duration) seek,
  required Future<void> Function(double) rate,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _PlayerSettings(
    session: session,
    pip: pip,
    capture: capture,
    screenshots: screenshots,
    toggleBackground: toggleBackground,
    background: background,
    seek: seek,
    rate: rate,
  ),
);

class _PlayerSettings extends StatefulWidget {
  const _PlayerSettings({
    required this.session,
    required this.pip,
    required this.capture,
    required this.screenshots,
    required this.toggleBackground,
    required this.background,
    required this.seek,
    required this.rate,
  });
  final PlaybackSession session;
  final Future<void> Function() pip, capture, screenshots, toggleBackground;
  final bool background;
  final Future<void> Function(Duration) seek;
  final Future<void> Function(double) rate;
  @override
  State<_PlayerSettings> createState() => _PlayerSettingsState();
}

class _PlayerSettingsState extends State<_PlayerSettings> {
  PlaybackSession get s => widget.session;
  late bool _background = widget.background;
  String? _error;
  double? _skipPreview;
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = '操作未完成，请检查设备支持和权限后重试。');
    }
  }

  Future<void> _set(SettingsKeys key, Object value) => _run(() async {
    await s.preferences.putSetting(key, value);
    if (mounted) setState(() {});
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .85,
      child: AnimatedBuilder(
        animation: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text('播放设置', style: DS.heading),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<double>(
              initialValue: s.core.playerSpeed,
              decoration: const InputDecoration(labelText: '播放速度'),
              items: [
                for (final speed in [
                  .25,
                  .5,
                  .75,
                  1.0,
                  1.25,
                  1.5,
                  1.75,
                  2.0,
                  3.0,
                  4.0,
                  8.0,
                ])
                  DropdownMenuItem(value: speed, child: Text('$speed×')),
              ],
              onChanged: (value) {
                if (value != null) unawaited(_run(() => widget.rate(value)));
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PlayerAspectRatio>(
              initialValue: s.panel.aspectRatioMode,
              decoration: const InputDecoration(labelText: '画面比例'),
              items: [
                for (final mode in PlayerAspectRatio.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (value) {
                if (value != null)
                  setState(() => s.panel.aspectRatioMode = value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('跳过片头'),
              subtitle: const Text('跳过时长可在下方修改'),
              trailing: Text(
                '${s.preferences.getSetting<int>(SettingsKeys.skipSeconds)} 秒',
              ),
              onTap: () => unawaited(
                _run(
                  () => widget.seek(
                    s.core.playerPosition +
                        Duration(
                          seconds: s.preferences.getSetting<int>(
                            SettingsKeys.skipSeconds,
                          ),
                        ),
                  ),
                ),
              ),
            ),
            Slider(
              value:
                  _skipPreview ??
                  s.preferences
                      .getSetting<int>(SettingsKeys.skipSeconds)
                      .toDouble(),
              min: 5,
              max: 180,
              divisions: 35,
              label:
                  '${s.preferences.getSetting<int>(SettingsKeys.skipSeconds)} 秒',
              onChanged: (value) => setState(() => _skipPreview = value),
              onChangeEnd: (value) =>
                  unawaited(_set(SettingsKeys.skipSeconds, value.round())),
            ),
            _tracks(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.subtitles_outlined),
              title: const Text('载入外部字幕'),
              subtitle: const Text('SRT / VTT / ASS / SSA'),
              onTap: () => unawaited(
                _run(() async {
                  final file = await openFile(
                    acceptedTypeGroups: [
                      const XTypeGroup(
                        label: '字幕',
                        extensions: ['srt', 'vtt', 'ass', 'ssa'],
                        mimeTypes: [
                          'text/plain',
                          'text/vtt',
                          'application/x-subrip',
                          'application/octet-stream',
                        ],
                      ),
                    ],
                  );
                  if (file != null)
                    await s.core.mediaPlayer?.setSubtitleTrack(
                      SubtitleTrack.uri(
                        Uri.file(file.path).toString(),
                        title: file.name,
                      ),
                    );
                }),
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('截取当前画面'),
              onTap: () => unawaited(_run(widget.capture)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('挑选截图 · ${s.screenshots.candidates.length} 张'),
              onTap: () {
                Navigator.pop(context);
                unawaited(widget.screenshots());
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_in_picture_alt_outlined),
              title: const Text('进入画中画'),
              subtitle: Text(
                !kIsWeb && Platform.isAndroid
                    ? '需要 Android 8.0 及设备支持'
                    : '此版本仅接入 Android 画中画',
              ),
              onTap: () {
                Navigator.pop(context);
                unawaited(widget.pip());
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('后台继续播放'),
              subtitle: const Text('媒体通知与耳机按键可继续控制播放'),
              value: _background,
              onChanged: (_) => unawaited(
                _run(() async {
                  await widget.toggleBackground();
                  if (mounted) setState(() => _background = !_background);
                }),
              ),
            ),
            DropdownButtonFormField<int>(
              initialValue: s.sleepAt == null ? 0 : -1,
              decoration: const InputDecoration(labelText: '定时暂停'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('关闭')),
                if (s.sleepAt != null)
                  DropdownMenuItem(
                    value: -1,
                    child: Text(
                      '已设置 · ${s.sleepAt!.hour}:${s.sleepAt!.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                for (final minutes in [15, 30, 60, 90])
                  DropdownMenuItem(value: minutes, child: Text('$minutes 分钟后')),
              ],
              onChanged: (value) {
                if (value != null && value >= 0)
                  setState(
                    () => s.setSleep(
                      value == 0 ? null : Duration(minutes: value),
                    ),
                  );
              },
            ),
            const SizedBox(height: 20),
            const Divider(),
            const Text('解码与缓存', style: DS.section),
            const Text('以下解码设置在重新载入视频后生效。', style: TextStyle(fontSize: 12)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('硬件解码'),
              value: s.preferences.getSetting<bool>(SettingsKeys.hAenable),
              onChanged: (value) =>
                  unawaited(_set(SettingsKeys.hAenable, value)),
            ),
            DropdownButtonFormField<String>(
              initialValue: s.preferences.getSetting<String>(
                SettingsKeys.androidVideoRenderer,
              ),
              decoration: const InputDecoration(labelText: '视频渲染器'),
              items: [
                for (final entry in {
                  'auto': '自动',
                  'gpu': 'GPU',
                  'gpu-next': 'GPU Next',
                  'mediacodec_embed': 'MediaCodec 嵌入',
                }.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null)
                  unawaited(_set(SettingsKeys.androidVideoRenderer, value));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Android OpenSLES 音频输出'),
              subtitle: const Text('关闭后使用 AudioTrack'),
              value: s.preferences.getSetting<bool>(
                SettingsKeys.androidEnableOpenSLES,
              ),
              onChanged: (value) =>
                  unawaited(_set(SettingsKeys.androidEnableOpenSLES, value)),
            ),
            DropdownButtonFormField<String>(
              initialValue: s.preferences.getSetting<String>(
                SettingsKeys.lowMemoryPolicy,
              ),
              decoration: const InputDecoration(labelText: '低内存缓存'),
              items: [
                for (final entry in {
                  'auto': '计费网络自动开启',
                  'always': '始终开启（2 MiB）',
                  'never': '关闭（沿用 Playra 大缓存上限）',
                }.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null)
                  unawaited(_set(SettingsKeys.lowMemoryPolicy, value));
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SuperResolutionMode>(
              initialValue: s.core.superResolutionMode,
              decoration: const InputDecoration(labelText: 'Anime4K 超分辨率'),
              items: [
                for (final mode in SuperResolutionMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (value) {
                if (value != null)
                  unawaited(
                    _run(() async {
                      await s.core.setShader(value);
                      await s.preferences.putSetting(
                        SettingsKeys.defaultSuperResolutionMode,
                        value.storageValue,
                      );
                    }),
                  );
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: s.source == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      unawaited(s.load(s.source!));
                    },
              child: const Text('重新载入视频'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('播放信息'),
              subtitle: Text(
                '${s.debug.playerWidth} × ${s.debug.playerHeight}\n${s.debug.playerVideoParams}\n${s.debug.playerAudioParams}',
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _tracks() {
    final player = s.core.mediaPlayer;
    if (player == null) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue:
              player.state.tracks.audio.any(
                (track) => track.id == player.state.track.audio.id,
              )
              ? player.state.track.audio.id
              : null,
          decoration: const InputDecoration(labelText: '音轨'),
          items: [
            for (final track in player.state.tracks.audio)
              DropdownMenuItem(
                value: track.id,
                child: Text(
                  track.title ??
                      track.language ??
                      (track.id == 'auto' ? '自动' : track.id),
                ),
              ),
          ],
          onChanged: (id) {
            if (id != null)
              unawaited(
                _run(
                  () => player.setAudioTrack(
                    player.state.tracks.audio.firstWhere(
                      (track) => track.id == id,
                    ),
                  ),
                ),
              );
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue:
              player.state.tracks.subtitle.any(
                (track) => track.id == player.state.track.subtitle.id,
              )
              ? player.state.track.subtitle.id
              : null,
          decoration: const InputDecoration(labelText: '字幕'),
          items: [
            for (final track in player.state.tracks.subtitle)
              DropdownMenuItem(
                value: track.id,
                child: Text(
                  track.title ??
                      track.language ??
                      (track.id == 'no'
                          ? '关闭'
                          : track.id == 'auto'
                          ? '自动'
                          : track.id),
                ),
              ),
          ],
          onChanged: (id) {
            if (id != null)
              unawaited(
                _run(
                  () => player.setSubtitleTrack(
                    player.state.tracks.subtitle.firstWhere(
                      (track) => track.id == id,
                    ),
                  ),
                ),
              );
          },
        ),
      ],
    );
  }
}
