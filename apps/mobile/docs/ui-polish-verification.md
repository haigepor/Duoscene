# UI 精修验证与交付

日期：2026-10-20。审查与设计见 [ui-polish-v2.md](ui-polish-v2.md)，逐文件差异、SHA256 与回滚源见 [ui-polish-change-manifest.json](ui-polish-change-manifest.json)。

## 已验证

| 验收 | 结果与证据 |
|---|---|
| 静态检查 | `flutter analyze --no-pub` 无问题；`.local/ui-polish-analyze.log` |
| 自动化行为 | 34 项通过；包含 18 页在 320×720dp、160% 字体下的布局检查，Tab 中途反向、状态保留、减少动画、长/短列表吸顶、键盘避让、原消息重试、账号与房间表单；`.local/ui-polish-unit.log` |
| 真实媒体 | MP4 2 次、HLS 4 次、分片 11 次、鉴权拒绝 0 次、截图 2 张；验证 Range/请求头、首帧、暂停、拖动、倍速、字幕、横屏、快速切源、本地文件和 PIP；`.local/ui-polish-player-final.log` |
| Android 全页面 | 46 个截图场景全部通过：18 页 + 24 状态 + 首页/我的吸顶、通用播放器、星海回声播放器；快速切换和真实导航入口同时执行；`.local/ui-polish-native-final.log`，图片位于 `.local/screenshots/ui/` |
| 真实后端链路 | Android 登录、安全存储恢复与凭据轮换、创建房间、生成/复制 43 位一次性邀请、第二成员加入及 UI 显示 2/2 席、退出全部通过；真实 Fastify/MySQL，隔离测试库，临时账号/房间已清理；`.local/ui-polish-backend-native.log` |
| 依赖与编码 | pubspec.yaml 与备份 SHA256 相同；未引入新包；变更 Dart/Markdown/JSON 严格 UTF-8 解码且无 U+FFFD；清单脚本输出 PASS |

执行环境：Windows、Flutter 3.47.6 / Dart 3.13.5、雷电 DuosceneTest（Android 14 / API 34 / x64）、390×780dp。播放器使用该模拟器兼容的 OpenGL `gpu`。仅使用独立测试实例，未调整用户日常模拟器。

## 安装交付

- `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:3000` 成功；日志 `.local/ui-polish-build.log`。
- 普通应用入口 APK：`D:/project/Duoscene/.local/artifacts/duoscene-ui-polish-v2-debug.apk`，300,372,301 字节。
- SHA256：

```text
7fd21b648171460d0ae4b41b5c67011ae25ddfc07004c586015eccecfa4b9f8c
```

- 已安装并启动雷电 DuosceneTest 的 `com.example.duoscene`，安装结果 `Success`；截图 `.local/screenshots/ui-polish-installed.png`。
- 宿主 `127.0.0.1:3000` 已启动现有 API，`/health/ready` 返回 `ready`；ADB reverse 只映射本机 3000 端口。进程记录 `.local/ui-polish-api-process.json`，日志 `.local/ui-polish-api.stdout.log` / `.stderr.log`。
- 构建存在既有 Gradle / AGP / Kotlin 后续支持期限提示，本轮未升级构建工具；当前构建、安装和原生测试通过。

## 回归中实际修复的问题

1. 关于页在 320dp、160% 字体下溢出：复用可伸缩的 PageFrame 顶栏，去掉固定大空白。
2. 有媒体的播放列表缺少近层 Material 导致 ink 断言：Forest 在装饰层之上提供透明 Material；新增选中 ListTile 绘制/点击回归，真实媒体重跑通过。
3. 首页滚动范围不足 72dp 时，滚到底仍半透明：渐变距离取实际剩余滚动范围与 token 阈值的较小值；小列表专项测试通过。
4. 新增的截图测试在更换 home 后保留了旧 Navigator 路由：独立影片场景使用独立 Key 重建 Navigator；不以错误页面的截图冒充影片页验收。

## 变更文件、目的与影响

| 文件组 | 目的 / 影响 |
|---|---|
| `lib/design/tokens.dart`、`lib/app/theme.dart` | 颜色、字号、间距、尺寸、圆角、动效统一源；影响全部页面与 Material 控件 |
| `lib/design/motion.dart`、`scroll_chrome.dart`、`bottom_navigation.dart`、`components.dart` | 主 Tab 状态保留与连续动画、分类指示器、透明吸顶、森林底图和近层 Material；影响公共容器 |
| `lib/features/catalog/{app_shell,home_page,collection_pages,profile_page,detail_page,search_page,posters}.dart` | 片库、详情、记录、收藏、我的页面尺寸和导航反馈 |
| `lib/features/auth/login_page.dart` | 登录视觉层级和按钮尺寸；不改变鉴权协议 |
| `lib/features/experience/{chat_panel,episode_sheet,experience_player,invite_pages,settings_pages,short_feed}.dart` | 产品播放器组合、聊天预览、选集、邀请及设置页；不增加假同步或假语音 |
| `lib/features/playback/player_page.dart`、`widgets/{player_library_view,player_surface,player_settings}.dart` | 通用播放器统一主题、空态与快捷操作；保留核心播放会话和原能力 |
| `test/ui_motion_test.dart`、`integration_test/{player_media_test,ui_gallery_test}.dart`、`tool/ui-native.mjs` | 动效/小屏/列表回归，更新可见控制层断言，补充原生导航与吸顶截图 |
| `assets/design/media/forest-atmosphere-v2.png`、`docs/ui-polish-*` | 内置 image_gen 新背景、逐页审查、提示词、验证、差异清单 |

回滚位置：`D:/project/Duoscene/.local/backup/2026-10-19-ui-polish-v2/`。对照清单恢复对应旧文件、移除本轮新增文件；先比较当前哈希，避免覆盖交付后的用户改动。`tool/ui-native.mjs` 仅将截图数量断言从 42 改为 46 并更新说明，回滚此处即可。原海报、原背景、Playra 源码、播放器 core/vendor、API 和数据库实现未改动。

## 验证边界

- 真实登录、房间和邀请服务与媒体测试各自使用隔离夹具；不将片库海报描述为真实在线片源。
- 双人同步、在线状态、私聊与语音目前仍有明确的预览标识，本轮没有宣称这些服务已接通。
- 300dp 键盘避让有 widget 测试；Android Flutter 截图不包含系统 IME 图层。
- 18 页按原设计体系精修，但不是所有像素逐点相同；没有物理设备 60/120fps 性能证明。动效连续性通过行为测试与原生快速切换验证。
- 无 AGENTS、Skills、Codex 配置或其他控制面修改，控制面新会话验证不适用。
