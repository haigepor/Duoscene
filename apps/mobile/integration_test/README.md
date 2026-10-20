# 真机验收入口

rooms_flow_test.dart 提供实际页面与系统安全存储的 Android 集成入口。
从根目录运行 scripts/test-mobile-backend.mjs --native，由执行器创建并清理隔离 MySQL 账户/房间。
实际运行结果见 docs/mobile-verification.md；widget 或宿主 HTTP 测试不能当作原生验收。

后续覆盖两台 Android/iOS 的播放同步、锁屏/前后台、网络切换、蓝牙/来电、
媒体与 WebRTC 音频会话共存，以及强制 TURN 的双向语音。
连续 60–120 分钟测试需记录漂移、缓冲、重连次数与资源增长。
