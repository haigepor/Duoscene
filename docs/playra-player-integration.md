# Playra 播放器集成

2026-10-19。已按项目维护者授权迁入播放内核、控制器、播放器操作控件和独立播放页面。
用户最新要求优先保留播放器功能，再调整产品差异；此前“首片不接截图/后台/超分”等建议已被本轮范围替代。
实际运行结果见 [播放器验证](player-verification.md)，代码存在不能替代平台验收。

## 源码与依赖

来源只读：D:/project/Playra；HEAD 02fcd555fbf2fa049caf9c20377b2c47638a165c，源工程含未提交修改。
26 个迁入源文件的路径和 SHA-256 记录在 third_party/playra-player/source-manifest.json。
保留 GPL v3 原文、来源和修改说明；media-kit wrapper 自身的 MIT 许可保留在 vendored 目录。
原生 libmpv/FFmpeg 与 GLSL 的许可独立，正式分发仍需附带相应声明和源码获取说明。

播放分支固定为 Predidit/media-kit 803c4a27912091db6f839d48d1b984a0d9f588c7；
media_kit 1.1.11 / media_kit_video 1.2.5 的源码快照在 apps/mobile/third_party/media-kit。
build hook 按 native_bundles.json 下载、校验与打包 Playra 相同的原生库，未额外混入 media_kit_libs_video。
wakelock_plus 从 1.3.3 适配到 1.8.1，以兼容 Duoscene 现有安全存储所需的 win32 6.x；
AndroidVideoController 增加销毁代际防护，修复雷电快速换片发现的迟到 Surface seek。
具体差异和补丁前后 SHA-256 见 third_party/playra-player/media-kit-patches.md。
选择官方 file_selector 代替依赖冲突的 file_picker。运行/构建不依赖 Playra 的目录路径。

## 已迁入的功能

| 功能 | 实现位置 |
| --- | --- |
| MP4/HLS/本地视频、请求头、串行换片和释放 | playback_session.dart、playback_source.dart、playra/controller/player_playback_controller.dart |
| 进度/缓冲、播放/暂停、seek、倍速、跳过片头、播放列表 | widgets/player_surface.dart、Playra transport/gesture/buffering 控件 |
| 全屏、锁定、左右亮度/音量、长按倍速、键盘操作 | widgets/player_surface.dart |
| 比例、音轨、内嵌/外部字幕、硬解/渲染器/音频输出 | widgets/player_settings.dart |
| Anime4K GLSL、计费网络低内存缓存、播放信息 | Playra core/cache/debug、assets/shaders |
| 截图候选、选择/移除、保存到系统相册 | Playra screenshot 控制器、player_page.dart |
| 后台播放、媒体通知/耳机按键、音频中断、定时暂停 | player_audio.dart、player_page.dart、PlaybackSession |
| Android 画中画 | MainActivity.kt 与 player_page.dart 的原生通道 |

房间详情的“打开播放器”进入 PlayerPage。来源支持手动网络地址及本地系统文件选择，
没有迁入 Playra 的搜索/解析 SDK、收藏/个人历史、下载器、弹幕和 Syncplay 服务。
Playra 的业务导航/全局存储/注入替换为 Duoscene 的参数、局部设置和回调，页面保留视频控件叠层和交互。
这不是整个 Playra 应用或所有业务页的逐像素复制。

## 必需的行为适配

- 原生 open 一开始使用 play:false；没有先自动播放再补 pause。
- seek 保留暂停，取消拖动不提交；媒体代际隔离旧拖动、长按、截图与加载回调。
- prepare 单次初始化，load/control/close 串行；旧页面不能解绑新页面的媒体控制。
- URL/请求头独立于 Duoscene 账户凭据，错误日志对媒体地址脱敏；拒绝 mpv 可执行协议与含换行请求头。
- 窄屏大字号将时间移到进度栏上方，保留触控尺寸；设置面板继承播放器主题。
- 原缓存行为保留，计费网络自动切换 2 MiB；普通网络的大缓存上限沿用 Playra，可显式更改。
- 中断只暂停，不在中断结束后绕过用户暂停自动恢复。
- 页面播放按钮与通知控制复用 AudioSession 激活；可识别模拟器使用软解，解码器探测诊断不误报为媒体终止。

## 工具链与平台

本项目 scripts/mobile-env.ps1 使用独立 Flutter 3.47.6 / Dart 3.13.5，
框架提交 5fc346839b5d0eef006ed8404392afb4dfae428d，与官方 3.47.6 tag 一致。
原 3.38.6 及全局用户 PATH 保留；复制来源的 SDK 缓存仅用于加速，本项目有独立安装。
meta 版本与 native_toolchain_c 的实际依赖冲突使旧 SDK 无法解析该分支当前依赖。

Android 编译 SDK 36、JDK 21、最低 API 28；沿用 Playra 的 EnableImpeller=false，匹配 SurfaceTexture/Skia 输出。
固定 libmpv 直接导入 Vulkan 1.1 的
vkGetPhysicalDeviceQueueFamilyProperties2 / vkGetPhysicalDeviceProperties2，API 24 运行时确实加载失败。
因此不能仅沿用 wrapper 的 API 21 或原安全存储 API 24 下限。
Windows Kotlin 增量缓存跨 C/D 盘错误通过项目内关闭 incremental 并进程内编译解决；
integration_test 的三个动态 AndroidX 依赖固定为 SDK 示例锁文件版本。
可用 DUOSCENE_GRADLE_OFFLINE=1 显式离线构建，前提是当前仓库对应的依赖元数据和制品均已缓存。
中文 Windows 的 vswhere JSON 代码页问题由项目内包装器解决，不修改系统 vswhere。

画中画需要 Android 8 以上和设备功能支持；本内核自身要求 Android 9。
雷电 14 的 Android 14 默认 GPU Next 路线曾引发宿主 Ld9BoxHeadless.exe 退出；
在该设备的播放设置选择 GPU（OpenGL）后完整测试通过。保留普通设备原有自动选择策略。
iOS 的后台音频/相册用途声明已接入，但 Windows 无法执行 Xcode 构建或真机验收。
硬解、GPU Next、Anime4K、蓝牙/来电和相册权限还需覆盖具体设备，不能从模拟器推断全部通过。

## 双人同步接缝

PlaybackSession.applyTarget 为应用权威播放目标的入口，与 UI 控制回调分开。
PlaybackSource.toRoomMedia 拒绝共享本地路径或带私有请求头的来源；签名播放地址与稳定媒体身份分开。
目前房间 REST 的鉴权/席位语义保留；不能把双方进入播放器称为已经同步。
后续实现一次性 WS 票据、串行房间状态机、epoch/revision/generation/commandId、校时、ready/缓冲屏障与重连。
断线暂停且丢弃离线意图，远端快照落地不回声；音量/亮度等本机设置不广播。

回退依据：.local/backup/2026-10-19-player/manifest.json，逐文件恢复旧内容并移除本轮新增文件。
本仓库尚无 Git；不要用整目录覆盖来恢复用户后续改动。

官方依据：[media-kit](https://github.com/media-kit/media-kit)、
[Flutter 3.47.6 tag](https://dart.googlesource.com/external/github.com/flutter/flutter/+/refs/tags/3.47.6)、
[Android Vulkan 版本](https://source.android.com/docs/core/graphics/implement-vulkan)、
[Kotlin 编译缓存](https://kotlinlang.org/docs/gradle-compilation-and-caches.html)。
