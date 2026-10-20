// Ported from Playra; see third_party/playra-player/NOTICE.md.
import '../player_support.dart';

import 'dart:async';

import 'package:media_kit/media_kit.dart';

class PlaybackCachePolicy {
  PlaybackCachePolicy({
    required bool Function() isLocalPlayback,
    required Player? Function() currentPlayer,
    required this.preferences,
  }) : _isLocalPlayback = isLocalPlayback,
       _currentPlayer = currentPlayer;

  static const int _lowMemoryBufferSize = 2 * 1024 * 1024;
  static const int _defaultBufferSize = 1500 * 1024 * 1024;

  final PlaybackPreferences preferences;
  final bool Function() _isLocalPlayback;
  final Player? Function() _currentPlayer;
  final AsyncSerialQueue _writes = AsyncSerialQueue();

  StreamSubscription<void>? _settingsSubscription;

  bool get networkAutomatic =>
      preferences.lowMemoryMode == LowMemoryMode.auto &&
      !_isLocalPlayback() &&
      preferences.isMetered;

  int get bufferSize =>
      preferences.lowMemoryMode.isEnabled(
        isMetered: preferences.isMetered,
        isLocalPlayback: _isLocalPlayback(),
      )
      ? _lowMemoryBufferSize
      : _defaultBufferSize;

  void startWatching() {
    if (_settingsSubscription != null) {
      return;
    }
    _settingsSubscription = preferences
        .watchSettings([])
        .listen((_) => _onChanged());
  }

  void stopWatching() {
    unawaited(_settingsSubscription?.cancel());
    _settingsSubscription = null;
  }

  Future<void> apply() async {
    final player = _currentPlayer();
    if (player == null) {
      return;
    }
    try {
      final pp = nativePlayerAccess(player);
      // A stale player's initialization must not block its replacement's writes.
      await pp.waitForPlayerInitialization;
      await _writes.run(() async {
        if (!identical(_currentPlayer(), player)) {
          return;
        }
        final size = bufferSize.toString();
        await pp.setProperty('demuxer-max-bytes', size);
        await pp.setProperty('demuxer-max-back-bytes', size);
      });
    } catch (e) {
      KazumiLogger().w(
        'PlaybackCachePolicy: failed to apply demuxer cache size',
        error: e,
      );
    }
  }

  void _onChanged() {
    unawaited(apply());
  }
}
