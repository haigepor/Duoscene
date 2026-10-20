# 2026-10-20 界面细节精修

## 目标与范围

本轮为 L 级共享 UI 调整，执行 Research → Design → Implement → Verify → Review。依据用户三张截图，修正分区标题、箭头、轮播衔接和二级页密度；不改账户、邀请、同步、私聊、语音协议或播放器内核。

## 实施结果

- DONE：手绘 10 个 SVG（返回、左右/上下折叠导航、邀请、音量、隐私、帮助、关于、退出中的对应图标），统一 24×24 viewBox、1.65 线宽、圆端点。保留已有许可证文件。
- DONE：SectionHeading / ArrowAction 统一分区标题与操作的中线对齐，首页“全部”和收藏“查看全部”使用 SVG 箭头，触控区域至少 48dp。
- DONE：轮播照片与暗色遮罩在底部逐步透明，显示同一张底层森林背景。标题、操作按钮不参与淡出。继续观看上间距 12dp，卡片保持紧凑。
- DONE：二级页导航标题 16dp、分组标题 14dp、菜单正文 13dp、注释 11dp、菜单图标 18dp、尾箭头 14dp。菜单图文间距 12dp，点击行不小于 48dp。系统文字缩放继续生效。
- DONE：精修播放与音频、隐私与记录、账户、帮助、关于页面；帮助折叠箭头使用旋转过渡并遵循减少动画设置。房间列表、创建/加入、详情和邀请面板同步消除异常大标题与间距。

## 验证

- PASS：`flutter analyze --no-pub`，无问题。
- PASS：9 个测试文件共 39 个测试，包括标题/操作/箭头中线、48dp 点击区、轮播与继续观看间距、轮播生命周期、320dp / 160% 大字体、页面切换、房间表单、邀请与播放器控制回归。
- PASS：雷电 Android 14 / 390×780dp，18 页、24 状态和 4 个滚动/导航/播放器场景，46 张新截图全部生成；已人工核对首页、个人页、隐私、帮助及滚动吸顶截图。
- PASS：普通 `lib/main.dart` 入口 Debug APK 构建成功，使用本地 API `http://127.0.0.1:3000`；已在 `127.0.0.1:5557` 和 `emulator-5558` 安装并冷启动，均返回 `Status: ok`。

APK：`.local/artifacts/duoscene-ui-details-debug.apk`。SHA-256：`57eddabe619bebe974498c4549e420ac7bc723fc5ca4b3113f3d73f7f2af221b`。

## 修改清单与回退

`docs/ui-details-change-manifest.json` 记录本轮 22 个代码/资源文件及 SHA-256。共享 token / 组件影响所有使用 MenuRow、PageFrame、导航 SVG 的界面；轮播透明过渡仅在首页开启，详情页默认保持原行为。

改前文件在 `.local/backup/2026-10-20-ui-details/apps/mobile/`，改前 46 张截图在同目录下 `screenshots-before/`。需要回退时，仅将清单中的文件从备份复制回对应原路径，再构建 APK；不要整体覆盖后续开发文件。

本轮没有修改后端和房间实时协议；双设备网络、语音音质与跨公网 NAT 的结论不由本轮视觉测试推导。

截图：`.local/screenshots/ui/01.png`（首页）、`state-profile-scrolled.png`（菜单）、`15.png`（隐私）、`17.png`（帮助）、`state-home-scrolled.png`（滚动衔接）。改前截图与新截图的文件名一致，便于对比。
