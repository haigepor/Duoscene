# 真机验收入口

rooms_flow_test.dart 提供实际页面与系统安全存储的 Android 集成入口。
从根目录运行 scripts/test-mobile-backend.mjs --native，由执行器创建并清理隔离 MySQL 账户/房间。
实际运行结果见 docs/mobile-verification.md；widget 或宿主 HTTP 测试不能当作原生验收。

后续覆盖两台 Android/iOS 的播放同步、锁屏/前后台、网络切换、蓝牙/来电、
媒体与 WebRTC 音频会话共存，以及强制 TURN 的双向语音。
连续 60–120 分钟测试需记录漂移、缓冲、重连次数与资源增长。

## 平板布局与真实视频

先用 `scripts/create-player-fixtures.ps1` 生成本机合成视频，再设置 `FLUTTER_DEVICE`、`FLUTTER_BIN`、`ADB_BIN` 与 Android/JDK 环境，从仓库根运行：

```powershell
node scripts/test-tablet-layout.mjs
```

请先在设备上手动解锁。执行器会检查系统锁屏状态，并临时保持供电常亮，避免 LiveTest 在息屏后一直等待绘制帧；结束后恢复原常亮和旋转设置、移除本轮反向端口。

该测试只使用 USB 反向端口和本机 MP4，验证真实首帧、宽屏分栏、旋转后的控制器/进度/草稿、瞬时报错恢复、系统键盘、全屏及设备支持的 PIP。使用隔离预览模型，不写入原账户记录或创建房间。输出默认保存到 `.local/tablet-layout-native`，可用 `TABLET_LAYOUT_OUTPUT` 指定目录。

测试会安装集成测试应用，完成后需重新安装正常应用包；它不替代真实源站、系统分屏和长时间播放验收。
