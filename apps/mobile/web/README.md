# Web 样式预览

这里是 Duoscene 的浏览器预览入口，用于查看 Android / iOS 页面样式。
页面直接使用 `../lib/features` 的 Flutter 组件，以及 `../lib/design`、
`../lib/app/theme.dart` 的主题和样式。没有单独维护的 HTML 页面或 CSS 副本。

## 启动

在项目根目录 `D:\project\Duoscene` 执行：

```powershell
.\scripts\start-web-preview.ps1
```

打开 <http://127.0.0.1:7357>，直接显示与 Android / iOS 共用的应用界面，
通过底部导航和页面内入口访问各页面；主题从「我的 → 外观」切换。
不显示额外的预览工具栏。桌面浏览器以最大 430dp 居中显示，窄屏占满可用宽度。
修改共用组件后，在启动终端按 `r` 热重载；必要时按 `R` 重启预览。
端口占用时运行 `.\scripts\start-web-preview.ps1 -Port 7358`。

已有 Flutter 环境时，也可以在 `apps/mobile` 下直接运行：

```sh
flutter run -d web-server -t web/main.dart --web-hostname 127.0.0.1 --web-port 7357 --dart-define=DUOSCENE_STYLE_PREVIEW=true
```

## 文件与边界

- `index.html`：浏览器宿主页，只负责加载 Flutter。
- `main.dart`：直接展示移动端页面及主题，使用独立示例身份。
- `../lib/features/experience/preview_gallery.dart`：共用页面、底部导航及示例数据。
- `../lib/main.dart`：Android / iOS 正式入口，与 Web 入口分开。

预览使用虚构片目和独立的示例身份，不接入真实账户或房间 API；
`DUOSCENE_STYLE_PREVIEW=true` 阻止浏览器初始化原生播放器或选择真实媒体。
已有页面交互仅用于检查样式，本目录不实现 Web 端业务功能。

这是开发预览，使用 `flutter run` 的默认 debug 模式。预览页保留 debug
可见性限制，不作为正式 Web 产品发布，也不能直接双击 `index.html` 运行。
浏览器渲染用于检查布局，Android / iOS 的原生能力仍需分别在设备上验证。
