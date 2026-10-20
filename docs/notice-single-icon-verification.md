# 错误气泡图标精简

- DONE：移除右侧 `info` 图标，左侧警告图标点击打开完整详情；正文不响应点击，右侧只保留关闭按钮。
- DONE：左侧详情入口至少 48×48dp，保持低饱和气泡、原有动画与自动收起规则。
- PASS：`error_notice_test.dart` 与 `app_test.dart` 共 9 项测试；验证图标集合、正文点击无操作、警告图标展示参考编号、关闭不打开详情和登录/房间回归。
- PASS：`flutter analyze --no-pub` 无问题，UTF-8、BOM 和修改范围检查通过。
- PASS：使用本地 API 和不存在的测试身份，在雷电实际触发登录失败；气泡仅有警告与关闭图标，点击警告后展示含参考编号的详情。测试后重启页面，清除测试输入。
- PASS：普通入口 APK 构建，已安装到 `127.0.0.1:5557` 与 `emulator-5558`，均正常冷启动。

截图：`.local/screenshots/notice-single-icon.png`、`.local/screenshots/notice-single-icon-details.png`。

安装包：`.local/artifacts/duoscene-notice-single-icon-debug.apk`。

SHA-256：`b39c0a7fa48a469de39a08cf65035929c13e1dc5ea9b02778a2d856deb39e375`。

本轮只修改 `apps/mobile/lib/core/widgets.dart`（图标与详情入口）及 `apps/mobile/test/error_notice_test.dart`（交互回归）。哈希见 `docs/notice-single-icon-change-manifest.json`；无 Git，使用改前备份 `.local/backup/2026-10-20-notice-single-icon/` 校验和回退。回退仅复制上述两个文件到原路径并重新构建，不覆盖其他轮次改动。本轮没有修改后端或播放器，也未重跑全部页面画廊。
