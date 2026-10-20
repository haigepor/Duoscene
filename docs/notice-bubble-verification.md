# 低饱和错误气泡

本轮 M 级修改基于用户提供的登录错误截图，范围为共享错误提示组件、3 个语义颜色 token、登录页气泡承载及回归测试。不修改错误接口、认证或凭据存储。当前目录未初始化 Git，使用文件备份和清单核对修改范围。

## 结果

- DONE：移除鲜红错误底色；使用深灰绿 `#22302F`、细边框 `#43514C`、灰米色提示图标 `#C4B09B`，正文沿用现有 ink / 13dp token。
- DONE：登录错误以顶部悬浮圆角气泡显示，不占表单高度。淡入与轻微位移动效，6 秒后收起，也可手动关闭。减少动画设置下关闭过渡；辅助导航下不自动消失。
- DONE：长参考编号默认折叠；通过“查看错误详情”打开可选择、可滚动的完整文本。
- DONE：其余使用 ErrorNotice 的邀请/房间页面也统一为低饱和气泡外观，保留持续的行内错误，以便用户处理重试。

## 验证

- PASS：10 个测试文件共 43 项测试，含详情展开、自动收起、新消息重置、手动关闭、辅助导航持续显示、320dp / 160% 字体以及表单位置不变。
- PASS：`flutter analyze --no-pub` 无问题。
- PASS：正文与气泡底色对比度约 12.12:1，图标/操作约 6.55:1；UTF-8 与备份边界检查通过。
- PASS：雷电 Android 14 / 390×780dp，18 页、24 状态、4 个滚动/导航/播放器场景，共 46 张截图。已人工核对登录错误气泡实拍：`.local/screenshots/notice-bubble.png`。
- PASS：普通入口 APK 构建成功，已安装到两台雷电测试设备 `127.0.0.1:5557` / `emulator-5558`，冷启动均返回 `Status: ok`。

安装包：`.local/artifacts/duoscene-notice-bubble-debug.apk`，连接本地 API `http://127.0.0.1:3000`。

SHA-256：`c417b8174342650fc78c74e97c846442ae368d4b17031bfebf4239f4c5b8be7d`。

本轮验收完成；未重新进行双设备媒体/语音网络联调，相关后端和播放器协议未修改。

## 修改与回退

| 文件 | 用途 |
| --- | --- |
| `apps/mobile/lib/core/widgets.dart` | 共享气泡、详情、计时与显示生命周期。 |
| `apps/mobile/lib/design/tokens.dart` | 气泡的语义颜色。 |
| `apps/mobile/lib/features/auth/login_page.dart` | 顶部悬浮承载，移除原行内红色提示。 |
| `apps/mobile/test/error_notice_test.dart` | 新增提示交互和布局回归。 |

哈希清单：`docs/notice-bubble-change-manifest.json`。

改前文件与截图：`.local/backup/2026-10-20-notice-bubble/`。回退只复制清单中原已存在的 3 个源文件到原路径，新增测试文件可单独移除，再重新构建；不覆盖其他轮次的改动。
