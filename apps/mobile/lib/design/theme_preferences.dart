import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DSTheme { sky }

class ThemePreferences extends ChangeNotifier {
  DSTheme selected = DSTheme.sky;
  ThemeMode mode = ThemeMode.system;
  bool loaded = false;
  bool _disposed = false;
  Future<void> _pending = Future.value();
  static const key = 'duoscene.appearance.v1';

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(key);
      // 旧森林偏好迁移到统一蓝色，保留用户原有明暗选择与账户数据。
      selected = DSTheme.sky;
      mode =
          ThemeMode.values
              .where((v) => v.name == stored?.split(':').last)
              .firstOrNull ??
          ThemeMode.system;
      if (stored?.startsWith('forest:') == true) {
        await prefs.setString(key, 'sky:${mode.name}');
      }
    } catch (_) {
      // 偏好损坏不阻止登录与媒体初始化，继续使用默认外观。
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> change({DSTheme? theme, ThemeMode? brightness}) {
    // 保存成功再通知，磁盘错误不伪装成已保存；快速操作串行，避免旧值覆盖。
    final next = _pending.catchError((Object _) {}).then((_) async {
      final nextTheme = theme ?? selected, nextMode = brightness ?? mode;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(key, '${nextTheme.name}:${nextMode.name}')) {
        throw StateError('外观设置保存失败');
      }
      selected = nextTheme;
      mode = nextMode;
      if (!_disposed) notifyListeners();
    });
    _pending = next;
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ThemePreferencesScope extends InheritedNotifier<ThemePreferences> {
  const ThemePreferencesScope({
    super.key,
    required ThemePreferences preferences,
    required super.child,
  }) : super(notifier: preferences);
  static ThemePreferences? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThemePreferencesScope>()
      ?.notifier;
}
