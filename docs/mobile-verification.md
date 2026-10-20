# 移动端账户与房间验收

日期：2026-10-19。下文保留此前账户/房间切片的环境和结果；本轮播放器已实际集成，
项目 SDK 更新为 Flutter 3.47.6 / Dart 3.13.5，最低 Android API 28。
播放器、雷电和新版 APK 的最新证据见 player-verification.md；下文的 API 24/旧 APK 哈希属于历史基线。

## 环境

| 项目 | 本机结果 |
| --- | --- |
| Flutter / Dart | 复用 D:\fluttersdk\versions\3.38.6，stable 3.38.6 / Dart 3.10.7 |
| Android SDK | 复用 D:\Android\Sdk，platform/build-tools 36，NDK 28.2.13676358 |
| Java | 独立安装 D:\tools\jdk-21.0.12.1+1，保留原 Oracle JDK 25；Flutter 指向新 JDK |
| cmdline-tools | latest junction 指向已存在的 19.0；原 latest 23.0 stub 保存在同目录 23.0 |
| SDK licenses | 已接受；flutter doctor 的 Flutter、Android toolchain 均通过 |
| Emulator | 37.2.12，官方归档 SHA1 校验通过，已注册 SDK 包元数据 |
| AVD | 新建 duoscene_api24，数据位于 D:\Android\avd\duoscene_api24；旧 AVD 不变 |
| 系统镜像 | Android 7 / API 24 / AOSP x86_64，用于最低 Android API 验证 |
| 加速 | 启用 Windows Hypervisor Platform；-accel-check 返回 WHPX installed and usable，模拟器实际启动成功 |
| 重启 | Windows 功能变更报告 RestartNeeded=true；未自动重启，本次运行已能使用 WHPX |
| 数据库 | 复用 Docker MySQL 8.4.11，127.0.0.1:3307；未触碰本机 3306 服务 |

用户 PATH 已补 Flutter、SDK platform-tools/cmdline-tools，ANDROID_HOME/ANDROID_SDK_ROOT 已设置。
JAVA_HOME 只由 scripts/mobile-env.ps1 在当前终端设置，不覆盖其他 Java 项目。
Flutter 配置位于用户 AppData/Roaming/.flutter_settings，仅设置 android-sdk 和 jdk-dir。
Windows 桌面 C++ 组件仍不完整；本片目标是 Android/iOS，没有安装该额外工作负载。
测试完成后已关闭本次无窗口模拟器以释放内存；可用 flutter emulators --launch duoscene_api24 再启动。

Temurin 安装包 SHA-256 对照 Adoptium 官方元数据通过。
Emulator 官方归档 SHA1 为 488ed747e82de7e9bb5247becd1ac043c7e5e85d。
API 24 镜像从 HuaweiCloud 下载，SHA1 对照 Google 官方 sys-img 元数据
f6559e1949a5879f31a9662f4f0e50ad60181684 通过。
Flutter 引擎 JAR 直连下载停滞，构建时仅在进程内设置 FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn；
x64 引擎 JAR 的 MD5 0bea9ac315db86b6a368acb6b8350065 与 Google Storage 官方响应头相同。
这些镜像设置没有写入用户环境或项目的生产网络配置。

## 实际验证

| 检查 | 结果与适用范围 |
| --- | --- |
| flutter analyze | PASS，无问题 |
| flutter test | PASS，12 项：7 个会话测试、5 个页面/widget 测试 |
| 真实 Flutter HTTP + Fastify + MySQL | PASS，1 项完整双账户流程；不是服务替身或 inject |
| Android 集成测试 | PASS，1 项，API 24 模拟器上的真实页面、网络及系统安全存储 |
| Android debug APK | PASS，普通 lib/main.dart 构建；交付产物信息见下方 |
| 后端默认测试 | PASS，20/20，无跳过 |
| MySQL 集成测试 | PASS，7/7，无跳过；隔离库保留迁移，测试自己的账户/房间已清理 |
| 原生 XML/plist/entitlements | PASS，13 个文件能解析 |
| 扩展源码/原生编码检查 | PASS，151 个文件严格 UTF-8、无 BOM、LF；临时凭据夹具已删除 |
| 结构与 UTF-8/LF | PASS，126 个项目文本文件；生成缓存不纳入源码检查 |
| 后端业务回归范围 | 对照数据库环境搭建前备份，业务源码未改变；迁移 README 有前一环境切片的说明更新 |

宿主 HTTP 流程覆盖：登录、创建、生成邀请、第二人加入、两席成员/列表、重复加入、
非房主邀请被拒绝、凭据恢复/轮换、注销后的本地请求拒绝。
宿主测试使用可替换 TokenStore；Android 测试另行实际验证 FlutterSecureStorage，不能混同。

Android 页面流程覆盖：按钮登录、房间创建、复制邀请到系统剪贴板、第二成员加入、成员刷新，
销毁页面后从系统安全存储恢复并轮换、退出后存储为空，以及第二用户通过软键盘完成键登录并粘贴邀请码加入。
本次是模拟器，不是物理 Android 手机或 iOS 真机。

首次原生测试出现软键盘视口变化导致点击坐标未命中，未计为通过；
测试修正为收起键盘后等待 hitTestable，并覆盖键盘完成键路径，完整重跑通过。
Gradle 离线诊断曾明确报告缺少 x86_64_debug 引擎 JAR；补齐镜像下载并核对摘要后构建通过。
SDK CLI 19 对已有 v4 元数据给出兼容提示，未影响本次 doctor、AVD 或 APK 运行。
交付 APK 另外检查了 ABI：Flutter 在 buildType 预填默认架构，已按 target-platform 替换筛选，
避免 JNI 插件单独的 ARM32 库让设备错误判断本次 APK 支持 ARM32。

## 文件与影响

| 文件范围 | 用途与影响 |
| --- | --- |
| apps/mobile/lib/app、core | 主题、身份变化重建导航、HTTP/模型/错误呈现 |
| apps/mobile/lib/features/auth | 私有登录、系统安全存储、会话恢复/并发轮换/退出 |
| apps/mobile/lib/features/rooms | 列表/创建/邀请加入、详情、邀请生成/复制/撤销 |
| apps/mobile/android、ios | 官方生成平台工程，Android 最低 API 24、debug 本机 HTTP 白名单、关闭备份，iOS Keychain 接线 |
| apps/mobile/pubspec.yaml、pubspec.lock | 固定 http 1.6.0、flutter_secure_storage 11.2.0，加入中文本地化与 integration_test |
| apps/mobile/test、integration_test | 会话竞态、页面边界与真实 HTTP/原生集成测试 |
| scripts/mobile-env.ps1 | 当前 PowerShell 的 Flutter/Android/JDK 环境入口 |
| scripts/test-mobile-backend.mjs | 强制隔离库、随机临时账户、临时本地 API、结束清理 |
| scripts/check-structure.mjs、.gitignore | 排除平台生成缓存和本地凭据/安装产物 |
| README.md、docs 与模块 README | 运行方法、版本、当前实现、验收/回退以及 Playra 播放器分析 |

没有修改后端业务接口、SQL 迁移、全局 Codex AGENTS/Skills/config、插件或 hooks。
没有初始化 Git、提交、推送、部署生产或创建远程资源。

## 安全与剩余边界

- 没有默认账户；管理员创建真实私有账户时交互输入密码，密码不放进命令行或 Dart。
- access token 仅内存；refresh token 按 API origin 隔离，放系统安全存储。
- 并发 401 共享一次轮换；迟到 401 使用最新 access；刷新结果不确定不重放旧 refresh。
- 业务写入超时不自动重试。退出优先清理本地，远端撤销遇到网络错误无法保证立即确认。
- 正式构建要求 HTTPS；debug cleartext 仅允许本机回环及 Android 模拟器宿主地址。
- 邀请只能由房主生成/撤销；后台切换隐藏邀请；复制需用户操作。系统剪贴板已复制内容由系统管理。
- 当前 com.example.duoscene、debug 签名仅用于开发；没有正式签名或商店发行配置。
- iOS 工程和 entitlement 已生成，但 Windows 无 Xcode，未构建/签名/验证 Keychain 真机行为。
- 尚未实现播放器、WebSocket 同步、语音、后台推送或跨设备在线状态。

## 回退

仓库无 Git 基线，改动前备份在 .local/backup/2026-10-19-mobile/。
该备份保存原移动端源文件、文档、根文件及官方生成后尚未适配的原生工程。
先核对后续编辑再逐文件还原，不能递归删除项目；新文件的归属见上表。
回退移动端不需要 DROP DATABASE 或回滚现有后端迁移。

环境修改前的 user-environment.json 在同一备份目录，可用于恢复用户 PATH、ANDROID_HOME/SDK_ROOT。
恢复其他项目所需的 Flutter android-sdk/jdk-dir 配置；原始 Flutter 配置未保存快照，不能声称可自动一键还原。
要恢复 cmdline-tools 原布局，先确认 latest 为本次 junction，再只移除该 junction，将 23.0 改回 latest；
不要递归删除 junction 的目标 19.0。
本次新增的 JDK、emulator、API 24 镜像和 duoscene_api24 AVD 可按各自路径单独卸载，先确认未被其他项目使用。
Windows Hypervisor Platform 原为关闭；如需恢复，通过 Windows 可选功能关闭并按系统提示重启，保留 WSL 所需 VirtualMachinePlatform。

## 交付产物

普通 Android 调试 APK：`.local/artifacts/duoscene-android-debug.apk`，123296313 字节。
支持 ARM64 手机与 x86_64 模拟器，最低 API 24、target API 36；没有 ARM32 引擎。
SHA-256：`37bc91eeced4fe1fe8dd807a65fc8fa3d9545881c5ccf0d447827952e471345e`。
已检查每个打包 ABI 都含 Flutter 引擎，普通入口的 kernel_blob 不含集成测试 fixture 标识。
该普通 APK 已实际安装、启动到登录页，截图位于 `.local/screenshots/login.png` 并已人工查看。
专用集成测试 APK 含短期测试夹具，不得分发；交付文件在测试后使用 lib/main.dart 重新构建。

Playra 分析用到的 14 个源文件 SHA-256 记录在 `.local/playra-player-source-manifest.json`，未改动来源项目。
