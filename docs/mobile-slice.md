# 移动端账户与房间切片

复杂度 L，按研究、设计、实现、验证、审查推进；沿用现有契约，不创建 OpenSpec。

## 范围与验收

- Flutter 使用已安装的 stable 3.38.6 / Dart 3.10.7，Android SDK 复用 D:\Android\Sdk。
- 实现私有账户登录、设备安全存储 refresh token、启动恢复、单通道轮换、退出登录。
- 实现分页房间列表、创建、粘贴邀请码加入、成员详情、房主生成/复制/撤销邀请。
- 页面包含加载、空数据、错误、重试、输入校验和防重复提交；不展示虚假的在线状态。
- 对接现有 REST 接口，不修改后端鉴权语义、数据库结构和同步/播放器/语音模块。
- 验证静态分析、单元与 widget 测试、真实 MySQL 后端双账户流程、Android 构建/运行。

## 边界与失败处理

refresh 严格一次轮换。并发 401 共用同一个刷新任务；旧 access token 的迟到 401 只用最新凭据重发。
刷新前删除本地旧 refresh token，防止中途终止后重放；刷新超时或安全存储失败要求重新登录。
业务写请求发生网络错误不自动重试，提示先刷新房间列表核实结果。
登录密码不落盘，access token 只驻留内存，refresh token 使用系统安全存储并按 API 地址隔离。
正式构建只允许 HTTPS；本地 HTTP 仅限 debug 的回环与 Android 模拟器宿主地址。

## 文件范围与回退

允许修改 apps/mobile/**、相关 docs/**、README.md、.gitignore，以及 scripts/mobile-env.ps1、
scripts/test-mobile-backend.mjs 和结构检查器的生成缓存排除项。
后端业务源码不在修改范围。外部改动仅限 Flutter/Android/JDK 的开发环境配置。
当前目录未初始化 Git，改动前文件备份位于 .local/backup/2026-10-19-mobile/。
Android/iOS 原生工程由 Flutter 官方生成器创建，备份包含生成后的原始平台工程；不是正式签名发行配置。
环境变量修改前快照为该目录下 user-environment.json。现有 Oracle JDK 25 保留。

## 依据

- https://docs.flutter.dev/install/manual
- https://docs.flutter.dev/platform-integration/android/setup
- https://docs.flutter.dev/cookbook/forms/validation
- https://docs.flutter.dev/cookbook/testing/unit/mocking
- https://pub.dev/packages/http
- https://pub.dev/packages/flutter_secure_storage
- https://docs.gradle.org/current/userguide/compatibility.html

## 结果

本片验收结果、普通 APK 和平台限制已记录在 mobile-verification.md。
