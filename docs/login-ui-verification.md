# 登录页精修与验证

## 范围与依据

本轮为 M 级登录页 UI 调整。只修改 `login_page.dart`、入口调用 `duoscene_app.dart` 和对应 `app_test.dart`；不修改服务端认证、凭据存储或登录后的邀请/房间流程。

参考已读取的 Playra 本地实现：

- `D:/project/Playra/lib/presentation/modern/settings/modern_settings_scope.dart`：12dp 圆角、细描边、主色聚焦边框和内边距。
- `D:/project/Playra/lib/presentation/modern/components/upstream/pages/input_form_field.dart`：框外标签、前置账户图标。
- `D:/project/Playra/lib/presentation/modern/components/upstream/pages/input.dart`：密码图标与显隐操作。

使用现有 Flutter TextFormField 实现相同交互模式，沿用 Duoscene 的森林背景、颜色和尺寸 token。

## 已实施

- DONE：移除登录按钮下方的受邀账户说明、开发预览入口和登录前保存邀请入口；同时移除只用于该入口的临时邀请回调和状态。
- DONE：账户/密码标签固定在框外；18dp 左侧图标；12dp 圆角、细边框、mint 聚焦边框；密码显隐保留完整点击区。
- DONE：页面最大宽度 400dp，内容两侧 24dp。品牌与标题缩小，顶部留白随键盘可用高度收紧，内容可滚动。
- DONE：保持自动填充、真实账户校验、登录失败提示、忙碌状态防重复提交、密码显隐和键盘完成提交。

## 验证记录

- PASS：9 个测试文件共 40 项测试，含新的单一登录入口、密码切换保留输入及键盘完成提交；另覆盖错误凭据恢复、退出、房间创建/邀请/加入与播放器回归。
- PASS：320dp / 160% 文字缩放页面检查。
- PASS：最终 `flutter analyze --no-pub` 无问题；UTF-8、BOM 与文件范围检查通过。
- PASS：雷电 390×780dp 新登录页截图已生成并人工核对：`.local/screenshots/login-polished.png`。
- PASS：完整雷电回归，18 页 + 24 状态 + 4 个滚动/导航/播放器场景，共 46 张截图，全部通过。
- PASS：普通 `lib/main.dart` 入口 APK 构建成功，已在 `127.0.0.1:5557`、`emulator-5558` 安装并冷启动，均返回 `Status: ok`。

安装包：`.local/artifacts/duoscene-login-polished-debug.apk`，本地 API 为 `http://127.0.0.1:3000`。

SHA-256：`7286105addef7b067deb0ee1718a8974b97edb2c53229f2487968066f612e116`。

本轮为登录 UI 和交互回归；登录成功/失败、邀请操作通过可控 HTTP 测试验证，本轮未重新进行双设备真实媒体/语音联调。没有待处理的 UI 验证项。

| 修改文件 | 用途与影响 |
| --- | --- |
| `apps/mobile/lib/features/auth/login_page.dart` | 登录页样式与辅助入口精简，仅影响登录和登录预览。 |
| `apps/mobile/lib/app/duoscene_app.dart` | 移除已删除入口专用的暂存邀请回调，登录后仍通过邀请与房间入口加入。 |
| `apps/mobile/test/app_test.dart` | 验证登录入口精简、密码显隐不丢失输入、键盘提交可进入首页。 |

## 清单与回退

修改的 3 个源文件、SHA-256 和备份路径见 `docs/login-ui-change-manifest.json`。仓库尚未初始化 Git，按文件级备份与哈希校验范围。

改前文件位于 `.local/backup/2026-10-20-login/apps/mobile/`，改前登录截图为备份中的 `login-before.png`。回退时仅复制清单中对应文件到原路径，再重新构建；不要覆盖其他轮次的改动。
