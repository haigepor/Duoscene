# Duoscene Mobile

Flutter + Dart，Android/iOS 优先。已实现登录、会话恢复、房间列表/创建、邀请码加入、
成员详情与邀请生成/复制/撤销，直接使用现有 REST 接口。

## 当前默认入口

当前直接进入真实片库，无需登录或配置 API；访客收藏与播放记录仅保存在本机，和原账号数据隔离。
浏览、搜索和个人播放正常使用，双人房间暂不在免登录模式开放。旧账号凭据不会在访客启动时读取或清除。
需要恢复原账号入口时，构建/运行增加 `--dart-define=REQUIRE_LOGIN=true`，并配置下面的 `API_BASE_URL`。
后端鉴权与房间协议保持原有规则。

## 本机开发

需要 Flutter 3.47.6 / Dart 3.13.5、Android SDK 36、NDK 28.2.13676358 和 JDK 21。
环境脚本优先读取 FLUTTER_ROOT、ANDROID_HOME、JAVA_HOME；Flutter 也可从 PATH 发现。
目录不在这些位置时，显式传入 `-FlutterSdk`、`-AndroidSdk`、`-Jdk`，不再依赖旧机器的 D 盘路径。
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

## GitHub Actions 安卓测试包

仓库 Actions 的 `Android APK` 工作流在相关文件推送到 main 时运行，也支持手动执行。
固定 Flutter 源码提交、Node 版本和 Action 提交，使用锁文件安装，先执行后端与移动端检查，
再构建正常 `lib/main.dart` 入口的 arm64 debug APK。产物包含 APK、SHA256 和构建来源。
这不是集成测试专用入口，也不是正式发行签名包。

默认 API origin 为 `http://127.0.0.1:3000`，适合 USB 联调；下载 artifact 后执行：

```powershell
adb -s <adb-device-id> reverse tcp:3000 tcp:3000
adb -s <adb-device-id> install -r .\duoscene-arm64-debug.apk
adb -s <adb-device-id> shell am start -n com.example.duoscene/.MainActivity
```

手机需要 Android 9/API 28 及以上、arm64-v8a。电脑必须另行启动真实 API/MySQL 才能登录和使用房间；
端口转发不会自动启动后端。已有不同签名的同包名 App 时不要直接卸载，以免丢失数据。
云端调试密钥不是稳定发行身份，后续跨构建覆盖安装仍需核对签名。
手动工作流可传入自己的 HTTPS API origin；不要包含路径、查询、凭据或账户密码。
完整源码分析与本次验证见 [Android 构建分析](../../docs/android-build-analysis-20261021.zh.md)。

Android/iOS 工程已由 `flutter create --project-name duoscene --platforms android,ios --no-pub .`
生成，不要重复覆盖。Android 最低 API 28（固定 Playra 原生 libmpv 的实际符号要求），iOS 最低 13。
默认 `com.example.duoscene` 仅供开发；正式 ID、签名和商店身份待确定。

后端在仓库根目录的另一终端启动：

```powershell
npm run dev:api
```

API 默认仅绑定 127.0.0.1:3000。`10.0.2.2` 是官方 Android Emulator 的宿主映射，
不能直接用于雷电模拟器。当前本机调试统一通过 ADB 回环转发；从仓库根目录执行：

```powershell
.\scripts\start-mobile-debug.ps1 -Device 127.0.0.1:5557
```

该脚本设置端口转发并显式传入 `API_BASE_URL=http://127.0.0.1:3000`，保留热更新终端。
`flutter attach` 只能连接已启动的应用，不能更换其编译时服务地址；更换地址需要重新 `flutter run`。
USB 手机或其他设备连接并授权后，也可手动执行：

```powershell
adb -s <adb-device-id> reverse tcp:3000 tcp:3000
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

## Web 样式预览

浏览器入口位于 [`web/`](web/README.md)，直接复用 Android / iOS 的页面、
组件和主题，不另做一套网页。项目根目录运行
`.\scripts\start-web-preview.ps1`，然后打开 <http://127.0.0.1:7357>。
Web 仅用于查看样式，不接入真实账户、播放或双人同步功能。

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
