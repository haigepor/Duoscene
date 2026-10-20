# Duoscene Mobile

Flutter + Dart，Android/iOS 优先。已实现登录、会话恢复、房间列表/创建、邀请码加入、
成员详情与邀请生成/复制/撤销，直接使用现有 REST 接口。

## 本机开发

本机复用 Flutter 3.47.6 / Dart 3.13.5、D:\Android\Sdk，并安装独立 JDK 21。
从仓库根目录打开 PowerShell：

```powershell
. .\scripts\mobile-env.ps1
flutter --version
flutter doctor -v
cd apps/mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter emulators --launch duoscene_player_api28
flutter run -d emulator-5554
```

Android/iOS 工程已由 `flutter create --project-name duoscene --platforms android,ios --no-pub .`
生成，不要重复覆盖。Android 最低 API 28（固定 Playra 原生 libmpv 的实际符号要求），iOS 最低 13。
默认 `com.example.duoscene` 仅供开发；正式 ID、签名和商店身份待确定。

后端在仓库根目录的另一终端启动：

```powershell
npm run dev:api
```

API 默认仅绑定 127.0.0.1:3000。Android 模拟器通过 10.0.2.2:3000 访问宿主机。
USB 手机连接并授权后，使用 `adb reverse tcp:3000 tcp:3000`，然后执行：

```powershell
flutter run -d <adb-device-id> --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

不开放局域网防火墙或暴露数据库。debug 仅允许回环/模拟器宿主 HTTP；正式构建需要显式
`--dart-define=API_BASE_URL=https://实际服务域名`。API_BASE_URL 必须是 origin，不带 /api/v1、路径、查询或凭据。
当前无默认账户，管理员通过根目录 `npm run account:create --workspace=@duoscene/api -- 用户名 显示名称`
交互式输入密码；不要把实际密码写进 Dart、命令行参数或夹具。

iOS 的 Keychain entitlement 已接线，但 Windows 无法执行 Xcode 编译/签名。
iOS 联调使用 HTTPS，后续在 macOS 验证 Keychain、ATS 和真机网络行为。

## 真实后端测试

在仓库根目录加载 mobile-env.ps1 后执行：

```powershell
node --env-file=.env scripts/test-mobile-backend.mjs
node --env-file=.env scripts/test-mobile-backend.mjs --native
```

第一条测试真实 Flutter HTTP 客户端 + Fastify + MySQL；第二条在 Android 模拟器上运行页面和安全存储测试。
第二条默认 emulator-5554，可设置 `FLUTTER_DEVICE` 覆盖设备 ID；当前宿主映射按 Android Emulator 设计。
执行器强制使用 DUOSCENE_TEST_DATABASE 指定的 duoscene_test_* 库，创建随机临时账户，
使用临时本地端口，结束后删除自己的账户/房间和凭据夹具。普通 `flutter test` 不依赖数据库。
测试凭据仅进入专用集成测试构建，不得将该构建分发给用户。

实际已运行项目及平台限制见 ../../docs/mobile-verification.md。

## 依赖边界

`app -> features -> core`。功能之间通过 app 层协调和窄接口连接。
复杂模块按需要逐步增加 domain/application/data/presentation；简单模块保持扁平。
使用原生 Navigator、ChangeNotifier/ListenableBuilder；播放器依赖和固定分支见 pubspec.yaml 与 ../../docs/playra-player-integration.md。
access token 只保留在内存，refresh token 按 API origin 隔离并存入系统安全存储。
并发 401 只刷新一次，刷新响应丢失不重放旧 token，退出时清理旧 Navigator 和敏感邀请。
业务写入遇到超时不自动重试，请先刷新列表核实结果。房间成员通过手动刷新/前台恢复更新，尚无在线状态推送。
media-kit 已固定为 Playra 当前分支；flutter_webrtc 尚未接入，
不能仅凭插件声明支持就认定两者能同时工作。

## Playra 播放器测试

先在房间详情点击“打开播放器”，可输入 MP4/HLS 地址或选择本地文件。网络请求头仅用于媒体，
不会把 Duoscene 的登录 token 转发到源站。首次载入保持暂停。

受控媒体由 FFmpeg 生成，不使用第三方影视内容；从仓库根目录运行：

```powershell
. .\scripts\mobile-env.ps1
.\scripts\create-player-fixtures.ps1 -Ffmpeg <ffmpeg.exe的绝对路径>
node scripts/test-player-media.mjs
```

测试默认 emulator-5554，需 Android 9/API 28 及以上。夹具仅监听 127.0.0.1，
媒体测试通过 ADB reverse 使用设备 127.0.0.1；临时测试头、映射和 dart-defines 文件在结束时清理。
测试 APK 不得分发，普通调试 APK 单独从 lib/main.dart 构建。
详细功能与平台证据见 ../../docs/player-verification.md。
