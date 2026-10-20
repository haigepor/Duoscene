# 固定 media-kit 快照的本地补丁

来源提交：803c4a27912091db6f839d48d1b984a0d9f588c7，原文件保留在只读来源 Git 缓存。
不修改或回写 D:/project/Playra。

1. media_kit_video/pubspec.yaml：wakelock_plus 1.3.3 → 1.8.1，兼容既有登录安全存储的 win32 6.x。
2. media_kit_video/lib/src/video_controller/android_video_controller/real.dart：
   Android Surface 事件与 NativePlayer.dispose 竞争时，旧 widListener 的 seek 会排到销毁操作后面，
   随后触发 `[Player] has been disposed`。雷电真实快速换片已复现。
   添加释放标记与 NativePlayer.disposed 检查，先移除监听再释放 notifier，
   在异步返回后再次检查所有权，并只忽略销毁期间迟到的属性/seek 异常；同时格式化该文件。

real.dart 原 SHA-256：6a7d9c00c33fd306ae256b7f47a20907c98aa5507e3b7a640cd25dd63e026be2。
补丁后 SHA-256：888d17b1fd5476123398a02d9acd40eed7c1624c312e8d95da9d4dc450a816eb。
回归入口：scripts/test-player-media.mjs，必须验证换片和关闭，不能只验证首次打开。

其余运行时源码保持来源字节；build/.gradle 等生成物不属于快照比较范围。
根结构检查对 vendored 源文件保留来源 CRLF，仍严格验证 UTF-8/JSON；
ffi/src/utf8.dart 中两个 U+FFFD 字面量是原解码器逻辑，单独校验其个数，未视为编码损坏。
