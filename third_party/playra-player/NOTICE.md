# Playra 播放器来源与适配

2026-10-19，按维护者授权从 D:/project/Playra 当前工作区迁入。源仓库 HEAD：
02fcd555fbf2fa049caf9c20377b2c47638a165c；具体源文件 SHA-256 见 source-manifest.json，不能仅按提交推断工作区内容。
Playra 源于 Kazumi；本目录 LICENSE 保留 GNU GPL v3 原文，迁入源文件及既有第三方版权记录仍保留。

## 保留的实现

- PlayerPlaybackController、PlayerDebugController、PlayerPanelController、PlayerSeekController 与相关生成代码。
- 进度布局、手势、亮度/音量/拖动/倍速 HUD、缓冲显示、截图候选管理与控件。
- 本地加载代际、串行任务、原生播放器所有权/释放、解码/渲染/缓存/Anime4K 配置。
- assets/shaders 内既有各 GLSL 文件的作者/许可声明。

## 必需适配

Playra 应用级 GStorage、Modular 注入、日志/对话框、路径、平台通道改为 Duoscene 的局部设置与适配。
视频业务上下文通过 PlaybackSource/PlaybackSession 与页面回调传入，不创建 Bangumi/下载/弹幕/个人库假服务。
首个新片载入保持暂停；seek 保留用户暂停。旧实例/加载回调不能重新安装到新页面。
播放器信息与错误日志对 URL 脱敏。其余独立控件主要修改 import、格式与页面组合方式。
采用 file_selector 保持私有登录安全存储的既有 win32 依赖兼容，不降级登录存储插件。

## 播放内核

apps/mobile/third_party/media-kit/ 是 Predidit/media-kit 提交
803c4a27912091db6f839d48d1b984a0d9f588c7 的本地源码快照；两个原生播放包及其 LICENSE 随项目保存。
该 fork 的 Dart build hook 按 native_bundles.json 下载并验证同一组 libmpv 原生构建，不额外混用 media_kit_libs_video。
仅将 media_kit_video 的 wakelock_plus 1.3.3 更新为 1.8.1，以兼容原登录插件的 win32 6.x；
未更换 media-kit 播放分支、原生 libmpv/FFmpeg 构建；视频输出的生命周期补丁如下。
在雷电快速换片测试发现旧 Surface 回调 seek 已释放 Player 后，另补充了 AndroidVideoController
的释放标记、迟到回调与销毁后 seek 防护；仅销毁代际的异常被忽略，其余异常仍抛出。
具体快照差异见 media-kit-patches.md；未更换原生解码/渲染二进制。
原生二进制和 GLSL 的许可证独立于 Dart wrapper 的 MIT 许可证，发布时应保留相应声明。

## 构建工具

scripts/windows/vswhere-shim.cs 同样复用 Playra 的本机兼容修复：仅将官方 vswhere 的 JSON Unicode 转义，
避免 native_toolchain_c 0.19.5 在中文 Windows 下按系统代码页解码造成 JSON 错误；不伪造 VS 路径或版本。
Flutter SDK 独立安装在 D:/fluttersdk/versions/3.47.6，提交与官方 3.47.6 tag 相同；原 3.38.6 仍保留。
