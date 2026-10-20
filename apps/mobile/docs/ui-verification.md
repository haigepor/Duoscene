# Flutter UI 实施与验证记录

日期：2026-10-19。范围为原稿 Flutter 页面、交互适配和 Playra 组合界面。复杂度 XL，按基础组件、主页面、二级页、状态和原生回归分段实施。当前不包含实时同步、聊天或语音服务开发。

## 验证结论

| 检查 | 结果与证据 |
| --- | --- |
| Flutter 静态分析 | PASS：无问题，`.local/ui-analyze.log` |
| 组件与行为回归 | PASS：28 项，包含搜索竞态、账户隔离、个人/共同进度、失败原条重发、暂停意图、换集确认、键盘合成 insets、清理确认、小屏 1.6 倍字体；`.local/ui-unit.log` |
| 雷电 Android 页面/状态 | PASS：18 页 + 24 预览状态，共 42 PNG；`.local/ui-native.log`、`.local/screenshots/ui/` |
| 原生关键操作 | PASS：加载错误重试、原条消息重发、记录清理/退出/同看换集取消、输入焦点与发送按钮位置检查 |
| MP4/HLS 原生回归 | PASS：MP4 请求 2、HLS 4、分片 16、拒绝请求 0、截图 2；覆盖首帧、鉴权头/Range、暂停、定位、倍速、音轨/字幕、截图、全屏、快速换源、本地视频、PiP 与释放；`.local/ui-player-regression.log` |
| 真实后端 Android UI | PASS：Fastify/MySQL 隔离测试库、登录、Android 安全存储恢复/凭据轮换、创建、一次性邀请、两人加入与重复加入、退出清凭据；临时账户/房间已删除；`.local/ui-backend-native.log` |
| 资源与编码 | PASS：六张无字媒体与原始交付逐字节相同，字体许可/来源和 SHA256 有记录；文字文件严格 UTF-8，无替换字符或新增 BOM |
| 普通 APK | PASS：普通 debug APK 已构建并安装启动到 DuosceneTest，`.local/artifacts/duoscene-ui-android-debug.apk`；SHA256 `08de5f0a029e8962ceddd54b97074aa000aefdb437c8abea1cc012020434bbc5`；构建日志 `.local/ui-build.log`，安装后屏幕 `.local/screenshots/ui-install-login.png` |

## 视觉结论与边界

完成了整体偏大的首轮校正，并在与原稿相同比例的 390×780dp 测试画布检查所有页面。主要变化是角色字号、按钮可见高度、头图高度、纯封面收藏区、共用底栏、搜索头部和播放器聊天空间。分析与尺寸表见 `ui-visual-calibration.md`；Playra 新版样式与布局参考见 `playra-layout-reference.md`。

**渲染通过不等于已经逐像素一致。** 原稿生成字形、部分封面裁切/背景与目前可复用资源仍有视觉差异；Android 真实系统边距和 iOS 原稿装饰栏也不同。未给出虚假的视觉一致率。当前完整原生截图可逐页审阅，后续精修需继续按原稿核对这些差异。

`state-chat-keyboard.png` 为原生输入焦点场景；测试环境的 Flutter Surface 截图没有提供 Android 系统软键盘的完整画面。300dp 键盘遮挡由组件测试显式注入 insets 验证，不能把这张截图说成已证实所有设备软键盘表现。

目录与示例身份只在明确的开发预览中出现；未声称有可观看的虚构电影片源。聊天已读、实时双方同步、麦克风通话均未伪造成功；加入房间不等于在线或同步完成。影片音量操作实际播放器，语音音量在无服务时为不可用或预览。

## 重跑

在仓库根目录先加载 `scripts/mobile-env.ps1`，原生测试设置 `DUOSCENE_GRADLE_OFFLINE=1`、`FLUTTER_DEVICE=127.0.0.1:5557`。

- `node apps/mobile/tool/ui-native.mjs`：42 个页面/状态截图与关键操作。
- `node scripts/test-player-media.mjs`：设置 `PLAYER_TEST_RENDERER=gpu`，雷电使用已验证的 OpenGL 渲染器。
- `node --env-file=.env scripts/test-mobile-backend.mjs --native`：使用已配置隔离测试库，只通过 ADB 回环访问当前测试服务，不输出凭据。
- `flutter analyze --no-pub` 和 `flutter test --no-pub`：在 `apps/mobile` 运行。

普通调试包使用 `API_BASE_URL=http://127.0.0.1:3000`，本机后端启动后需为当前 Android 设备配置 `adb reverse tcp:3000 tcp:3000`。测试服务是临时端口并已结束；交付不声称 3000 服务正在运行。未登录时可点“开发预览 · 查看完整界面”，在“我的”进入 18 页与状态入口。无正式生产环境地址或测试账户写入 APK。

## 修改与回滚

完整文件清单见 `ui-change-manifest.json`；资源来源见 `ui-asset-manifest.json`。

| 修改组 | 目的与影响 |
| --- | --- |
| `lib/design`、`app/theme.dart` | 统一样式 token、背景、品牌、图标、公共组件与四标签；影响新 UI |
| `lib/features/catalog` | 四主页面、搜索、详情、收藏/记录及账户隔离本机存储 |
| `lib/features/experience` | 播放组合、私聊/选集/邀请、音频及辅助页、隔离开发预览 |
| `lib/app/duoscene_app.dart`、`features/auth/login_page.dart` | 真实 Session 登录入口、身份切换销毁旧导航、待接受邀请 |
| `features/playback/player_page.dart` | 可选呈现与播放意图钩子，继续复用现有 Session/Surface、所有高级功能 |
| `android/.../MainActivity.kt` | 只补实际应用版本查询和系统文本分享，保留原播放原生逻辑 |
| `pubspec.yaml/lock`、`assets/design`、`main.dart` | SVG 纯 Dart 依赖、原稿资源、字体与许可登记 |
| `test`、`integration_test`、`tool/ui-native.mjs` | 新 UI 与真实后端回归入口，42 项原生采集 |
| `scripts/test-mobile-backend.mjs` | 兼容雷电与 AVD 的测试回环地址，测试结束清理映射 |

旧文件原样备份：`.local/backup/2026-10-19-flutter-ui/`，`manifest.json` 记录基线 SHA256。无 Git，因此必须按文件对照恢复，不能覆盖其他人的后续更新；新增文件按变更清单撤销。未修改桌面设计原稿、Playra 仓库、vendor 播放核心、后端业务、数据库结构、原生 minSdk/打包或全局配置。

## 计划收口

- DONE：18 页面、公共样式与本轮尺寸校正。
- DONE：24 状态和关键操作验证，真实播放/登录/房间回归。
- DONE：Playra 新版 token/Android 布局源码分析。
- NEXT：继续逐页精修原稿字形、封面裁切与背景素材差异；当前未达到逐像素一致。
- NEXT：真实双人同步、私聊、语音服务按独立范围实施。
