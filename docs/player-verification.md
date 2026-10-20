# Playra 播放器验收记录

日期：2026-10-19。播放器迁入与 Android 基础验收 PASS；iOS/真机专项验收尚未覆盖。
范围见 player-migration-scope.md；双人同步仍为 NEXT，未将单机播放称为同步。

## 已通过的检查

| 检查 | 结果与证据 |
| --- | --- |
| Flutter 完整分析 | flutter analyze，无 issues |
| Flutter 单元/widget | 19/19：原账户房间 12 项，播放器来源/取消/旧代际/截图/大字号布局 7 项 |
| Android 9 / API 28 / x64 官方模拟器 | 原生 MP4/HLS、本地视频、字幕、控制、全屏、画中画、换片与释放通过；.local/player-native-official-final.log |
| 雷电 14.0.29 / Android 14 / API 34 / x64 | 独立 DuosceneTest（index 1），GPU/OpenGL 路线通过；.local/player-native-ldplayer-final.log |
| Flutter 真实 HTTP + MySQL | 登录、创建、邀请、加入、恢复/注销通过；临时数据已清理 |
| Android 页面 + 安全存储 + MySQL | 新 SDK 与 API 28 上原有完整房间流程再次通过；.local/mobile-native-player-regression.log |
| API | typecheck、20 项默认测试（3 契约 + 17 API）、build 通过；后端业务代码及迁移未改动 |
| 编码/来源 | 108 个本轮拥有的文本文件严格 UTF-8、无新增 BOM/U+FFFD；26 个 Playra 原文件 SHA-256 仍与来源记录一致 |

原生媒体用例生成自有 32 秒 H.264/AAC 测试图案与正弦音轨、4 秒分片 HLS。
真实首帧尺寸 640×360，原生 PNG 已检查；暂停后位置稳定，seek 到 12 秒保持暂停，1.5 倍速生效。
外部 SRT 的文本流和画面、全屏进入/退出、实际播放/暂停按钮与 AudioSession 激活、
Android 画中画回调、快速 MP4/HLS 替换、本地文件播放及最终控制器释放均有实际断言。
音轨已解码并枚举；未把这些结果当作人耳、蓝牙、来电或真机硬解的验证。

最终两台模拟器的请求统计均为 MP4 2 次、HLS 清单 4 次、分片 16 次、拒绝 0 次、PNG 2 张。
所有媒体与 HLS 分片需要随机测试头，MP4 实际 Range 请求成功。
夹具仅监听宿主 127.0.0.1，ADB reverse 让 USB/官方模拟器/雷电统一使用设备回环，
结束时移除映射、测试头与 dart-defines；测试构建未作为交付 APK。

## 复现

```powershell
. .\scripts\mobile-env.ps1
.\scripts\create-player-fixtures.ps1 -Ffmpeg <ffmpeg.exe的绝对路径>
$env:DUOSCENE_GRADLE_OFFLINE = '1' # 仅依赖已缓存时使用
$env:FLUTTER_DEVICE = 'emulator-5554'
node scripts/test-player-media.mjs
# 雷电需先启动 DuosceneTest，通过 SDK ADB 连接 127.0.0.1:5557
$env:FLUTTER_DEVICE = '127.0.0.1:5557'
$env:PLAYER_TEST_RENDERER = 'gpu'
node scripts/test-player-media.mjs
```

雷电的普通播放器设置为“视频渲染器 → GPU”，保持此设备兼容配置。
原 index 0 实例未改动。API 24 的旧 AVD/SDK 保留；新 AVD 为 duoscene_player_api28，
镜像官方 SHA-1 d47a85c8f4e9fd57df97814ad8884eeb0f3a0ef0 已核验。
官方无窗口模拟器已在回归完成后关闭；雷电 DuosceneTest 保留并已安装、启动普通 APK。

## 交付物

- .local/artifacts/duoscene-android-debug.apk：从 lib/main.dart 独立构建，开发包名 com.example.duoscene。
- 最低 Android 9/API 28，target/compile SDK 36；arm64-v8a 和 x86_64 均含 libflutter、libmpv。
- SHA-256：09c90a307c8d434182f0f910d3073df679b625b6799d8d55e6ddb74049f851b5；226091415 字节。
- 已检查不存在不完整 armeabi-v7a 目录，Dart kernel 不含播放器/房间测试入口或夹具 define。
- .local/screenshots/player-ldplayer-page.png / player-ldplayer-native.png：雷电页面与原生帧。
- .local/screenshots/player-official-page.png / player-official-native.png：官方模拟器页面与原生帧。
- .local/player-changed-existing.json：与本轮前备份相比的既有文件变更清单；新增目录按下表归属。

普通 APK 仍是 debug 签名，未配置发行身份、商店签名或生产部署。登录后从房间详情“打开播放器”进入。
API 仍需按 README 在本地启动，不保留测试 HTTP 服务器或测试账户。

## 修改归属与影响

| 文件/目录 | 作用与影响 |
| --- | --- |
| apps/mobile/lib/features/playback/** | Playra 控制器/控件迁入，来源、生命周期、音频、页面和设置接线 |
| apps/mobile/lib/features/rooms/room_detail_page.dart | 增加播放器入口；原 REST 语义不变 |
| apps/mobile/pubspec.yaml / lock / third_party/media-kit/** / assets/shaders/** | 固定依赖和原生构建输入，保留源码与 GLSL |
| apps/mobile/android/** / ios/Runner/Info.plist | 最低 API 28、ABI 打包、后台媒体、画中画、亮度/网络/相册权限通道与用途声明 |
| apps/mobile/test/** / integration_test/player_media_test.dart | 来源边界、旧代际、取消、布局和实际媒体/平台回归 |
| scripts/mobile-env.ps1 / windows/vswhere-shim.cs | 项目 Flutter 3.47.6 和中文 Windows C 工具链兼容；不覆盖全局 PATH |
| scripts/create-player-fixtures.ps1 / test-player-media.mjs | 自有 MP4/HLS、鉴权夹具、设备回环、原生测试执行与清理 |
| scripts/check-structure.mjs | 保留第三方快照换行及原解码器字面量，继续检查来源与自有文本 |
| third_party/playra-player/** / docs/** / README | 来源、许可证、补丁、环境、验收和后续计划 |

## 修复与仍未覆盖的范围

已修复：native_toolchain_c 的 Windows vswhere 代码页问题、Kotlin C/D 盘增量缓存错误、
SDK integration_test 动态 AndroidX 版本离线解析、插件重新带入不完整 ABI 目录、
模拟器硬解策略被显式 hwdec 绕过、大字号进度栏溢出、旧页面音频解绑与旧 Surface seek。
未修改 Playra 源项目，原生 libmpv/FFmpeg 二进制未更换；快照只有两个本地补丁，见
third_party/playra-player/media-kit-patches.md。

- API 24 实测缺 Vulkan 1.1 导出符号，不能使用此固定内核；最低版本已明确提高到 28。
- 雷电默认 GPU Next 曾使宿主 Ld9BoxHeadless.exe 在 ucrtbase.dll 以 0xc0000409 退出；
  这是实际 Windows 事件，未推断唯一根因；GPU/OpenGL 兼容路线完整通过，未关闭 Hyper-V/WSL。
- iOS 编译/签名、真机硬解/GPU Next/Anime4K、相册授权保存、耳机/蓝牙/来电/长时锁屏仍需专门验证。
- Flutter 对现有 Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 给出未来兼容性警告；本轮实际构建成功，未绕过失败。
- 全仓 npm run check:structure 受 output/ui-design/2026-10-19/design-kit-v2/icons-manifest.json 的 CRLF 阻断。
  该设计输出不属于本次修改，未改写；播放器拥有的源码/配置与第三方例外已分别检查。
- WS、权威房间状态、共同缓冲/断线恢复/双端误差测量未实现；不能将两个单机通过用例称为双人同步。

保留失败日志 .local/player-native-test.log、player-native-retry.log、player-native-online.log、
player-native-api28-diagnosis.log、player-native-ldplayer.log、player-native-ldplayer-opengl.log。
后者记录旧 Surface 销毁竞争，修复后在雷电和官方模拟器均通过。

## 回退

.local/backup/2026-10-19-player/manifest.json 是本轮前 121 个文件的 SHA-256，
按路径逐文件恢复，移除本轮新增 playback、vendored 依赖/GLSL、测试和来源记录。
旧普通 APK 为同备份目录下 duoscene-android-debug-before-player.apk。
scripts/mobile-env.ps1/check-structure.mjs 不在该快照中：回退时手动恢复旧默认 SDK 3.38.6，
移除本轮 vswhere 包装器接线和两处 vendor 检查例外。原 SDK、AVD、MySQL 和原 Playra 均保留。
不要以整个目录覆盖的方式回退用户后续修改。
