# 邀请弹层与页面细节调整（2026-10-21）

## 已完成

- 邀请弹层：分享保持主按钮，复制与进入房间并排；倒计时与撤销合为状态行；普通字号下整体比原版缩短约 98dp。小屏和大字号自动纵排，触控区域至少 48dp。
- 记录与收藏：共用筛选下划线从 4dp 改为 2dp，顶部间隔从 12dp 改为 4dp，下划线靠近文字。其他线形 Tab 同步收紧文字与指示线距离。
- 首页分类 Tab：按用户选定的 B“电影票签”制作单个滑块；正常字号高度 28dp，原生路径绘制切口、细虚线、浅蓝票面。快速反向点击延续当前位置，保留减少动画设置，无新增实时模糊或位图解码。
- 个人页：隐藏开发预览入口和片库说明；播放与音频页隐藏“打开播放器”入口，播放器内的高级设置保留。
- 隐私与记录：插图从 80dp 缩至 56dp，功能图标从 18dp 缩至 16dp；采用紧凑菜单行，统一字号与间距；清理确认、记录范围和缓存不可用状态保留。
- 推荐与分类：轮播、续看和邀请卡片仅在推荐页显示；四种分类采用顶部下拉筛选与全宽海报网格。题材由现有片目生成，电影按片长、电视剧/动漫按集数、短剧按单集时长筛选；每类分别保存选择，支持空结果重置和选中状态重置。普通字号双列，大字号单列。菜单箭头随开合旋转，点击外部或返回可关闭。
- 账户信息：按用户确认的第二版名片布局还原；账户名可选择/复制，退出按钮紧随内容，恢复码说明与退出确认保留。补齐透明玻璃插图，WebP 约 146KiB，按显示尺寸解码。
- 修复筛选使列表变短时，滚动校正在布局阶段触发顶部重建的问题；同一帧结束后合并更新顶部，正常滚动保持原有逻辑。

## 文件及影响

| 文件 | 用途与影响 |
| --- | --- |
| `apps/mobile/lib/features/experience/invite_pages.dart` | 邀请弹层排版；生成与分享接口流程未改 |
| `apps/mobile/test/invite_sheet_layout_test.dart` | 深浅色、小屏大字号、复制复用、撤销与操作可达性验证 |
| `apps/mobile/lib/features/catalog/collection_pages.dart` | 记录、收藏及个人/共同进度筛选栏 |
| `apps/mobile/lib/design/motion.dart` | 共用线形 Tab 与首页票签绘制；动画时长及减少动画逻辑保留 |
| `apps/mobile/lib/design/scroll_chrome.dart` | 布局阶段滚动校正的更新调度 |
| `apps/mobile/lib/features/experience/episode_sheet.dart` | 选集分组 Tab 顶部间距 |
| `apps/mobile/lib/features/catalog/profile_page.dart` | 隐藏开发与说明内容 |
| `apps/mobile/lib/features/experience/settings_pages.dart` | 隐私页密度、音频页入口、账户页名片及复制操作 |
| `apps/mobile/lib/design/components.dart` | `MenuRow.compact` 可选参数，仅隐私页启用；其余调用默认行为不变 |
| `apps/mobile/lib/features/catalog/home_page.dart` | 推荐专属区与分类浏览分离，保存每类题材选择 |
| `apps/mobile/lib/features/catalog/home_content.dart` | 按真实题材筛选、结果数量、响应式海报网格 |
| `apps/mobile/test/home_content_test.dart` | 分类筛选、跨分类保留状态、推荐区显示边界与布局回归 |
| `apps/mobile/test/settings_polish_test.dart` | 账户复制与退出确认、两主题/字号、隐藏入口回归 |
| `apps/mobile/test/navigation_polish_test.dart` | 票签高度、单滑块与连续反向过渡验证 |
| `apps/mobile/integration_test/realtime_pair_test.dart` | 移除已删除森林主题的旧引用，改为遍历当前有效主题 |
| `apps/mobile/assets/design/media/account-identity-glass.webp` | 1254×1254 RGBA 透明身份插图，149118 字节 |

## 设计稿

- 确认账户稿：`.local/designs/account-ui-20261021/02-account-identity.png`
- 确认分类稿：`.local/designs/catalog-category-20261021/03-category-dropdown.png`；侧边导航方向已按用户要求取消，未进入应用。
- Tab 比较稿：`.local/designs/home-tabs-20261021/01-tab-directions.png`，用户选择 B“电影票签”。
- 提示词分别保存在上述目录的 `prompts.md`；生成方式为内置 imagegen。账户插图源：`C:/Users/zhuyi/.codex/generated_images/01a15965-45bc-73e1-8fb1-46c3e4b9c746/exec-ebf16761-e284-43ae-baeb-0069c0fed211.png`，仅做 WebP 编码转换，保留透明通道。
- 使用内置 imagegen；设计稿中的新海报为视觉示意，应用继续使用已有素材，不把生成文字当作业务数据。
- 参考 Netflix 官方当前移动布局中的顶部内容快捷筛选；具体下拉形式按用户要求设计，未照搬其主题或虚构数据：[Netflix 官方说明](https://help.netflix.com/en/node/575087423404644)。

## 验证与限制

- 邀请布局的 4 种主题/字号组合和既有 UI 验证通过；原邀请 `generate()` 与接收邀请页面未改。
- Android 调试包构建安装成功；邀请弹层生成/复制真实邀请后，双按钮与状态行已截图核对；热更新已恢复。
- 全目录 `flutter analyze` 通过；已将既有集成测试的失效森林引用改为当前主题枚举。
- `flutter test` 全部 95 项通过，包含 18 页面深浅色/200% 字号检查；另验证账户复制/退出取消、题材与时长联合筛选、空结果重置和快速反向导航。
- 原生模拟器已核对邀请弹层、分类下拉及真实筛选、账户名片、隐私页、隐藏音频入口；热更新会话已恢复并持续运行。截图在 `.local/screenshots/`。
- 运行日志曾出现一次已卸载控件的指针事件断言，期间存在模拟器操作与热更新；随后重复 3 次菜单展开/返回及分类切换未复现。尚不能据此认定为产品缺陷或已修复，未增加猜测性框架补丁；真机手势仍需观察。
- 设备端完整双人分享/加入、语音与真机表现未在本次重新验证。
- 首次切页性能的更早测量边界保留于 `docs/first-transition-performance-20261021.zh.md`；本次未将调试运行截图当作零卡顿或 profile 性能证明。

## 回退

本轮修改前逐文件备份在 `.local/backup/invite-sheet-layout-20261021/`；`scope.json` 记录允许文件及追加需求。按文件恢复备份可回退本轮修改，勿用 Git 全局还原覆盖此前工作。
