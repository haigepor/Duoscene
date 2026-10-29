# 平板布局适配交付（2026-10-29）

依据 [平板审计方案](tablet-layout-audit-20261029.zh.md) 实施。当前 TB711FU 平板已安装正常 `lib/main.dart` 入口的 Profile 包，默认访客模式、真实在线片库，交付包不含固定元数据替换。

## 已实现的行为

| 区域 | 最终行为 |
| --- | --- |
| 导航 | 当前窗口宽度达到 600dp 后使用 80dp 侧栏；变窄时恢复原底栏。沿用四个目的地和玻璃质感，修复底栏/侧栏的语义点击动作 |
| 状态保留 | AppShell 始终使用同一组布局槽位，保留 LibraryState、当前 tab、首页与分类 State；不在宽/窄分支创建两套业务树 |
| 首页 | 平板推荐卡完整保留竖版海报，信息/操作与海报并排；宽内容区可同时展示两张。保留原手机轮播样式、当前项及自动轮播生命周期 |
| 海报 | 统一按局部内容宽度与字号计算列数。本机默认竖屏分类 5 列、横屏 7 列；普通横向海报条 144dp。平板标题/元信息为 14/12dp，系统 TextScaler 仍生效 |
| 图片解码 | 分类卡片的显式解码提示限制为最多 480px，避免横屏三列时请求 1232px；原有 HTTPS 规范化、请求头与失败恢复继续生效 |
| 收藏 | 平板使用 SliverGrid 懒加载；手机保留原 Wrap 布局与视觉。管理、筛选、选择和移除逻辑复用原状态 |
| 详情 | 平板使用 200dp 竖版封面与有界信息栏；推荐封面复用海报尺寸策略，主要操作限制在 720dp。加载/失败时信息栏保持稳定，减少横向跳动 |
| 长视频 | 可用宽度至少 1100dp、高度至少 600dp 且未在输入时，左侧视频/控制、右侧 360dp 交流栏；竖屏仍上下排列 |
| 低高度/大字体 | 优先预留交流与输入区域，缩小或收起过小的视频区域；保留播放器状态，修复 400/500dp 高度、2倍字体下的溢出 |
| 短剧 | 平板观看区域根据可用高度约束为 9:16，空余背景沿用媒体色；窄窗口仍填满原宽度，不新增全屏强模糊 |
| 个人/正文 | 个人页限制到 960dp，空间足够时身份/收藏与设置分栏；大字体回到上下结构。记录/搜索约 840dp、普通设置正文约 720dp |
| 弹层 | 保留原有 Material 3 的 640dp 选集弹层，无需重写其业务流程 |

窗口与内容约束的用法依照 [Flutter 官方适配说明](https://docs.flutter.dev/ui/adaptive-responsive/general)：壳层依据当前窗口，网格和面板依据父约束。上述具体尺寸是本项目的实现策略；没有按设备型号或物理分辨率整体缩放 UI。

## 关键架构

- `design/window_layout.dart`：窗口/海报纯布局规则，以及内容限宽和竖向媒体边界，不依赖会话或片源服务。
- `design/adaptive_app_frame.dart`：底栏/侧栏使用同一导航回调；内容槽位保持稳定，不重建 AppShell 的业务状态。
- `design/adaptive_watch_layout.dart`：使用四个固定 LayoutId 重排顶栏、媒体、控制条和交流区；横竖屏、输入和布局变化不重新创建播放器或聊天控制器。
- `features/catalog/tablet_feature_card.dart`：只接收 Film 和现有点击回调，保持推荐卡为展示组件。

保留了原来的 preparingTab、MotionTabs、后台 TickerMode、目录缓存、访客数据隔离及播放器生命周期。没有更换播放器内核、渲染器、SDK、依赖版本、配色或旧黄金图。

## 测试结果

1. 完整 Flutter 测试 **425 项通过**，包含原手机浅/深色黄金图；未更新黄金图来接受视觉差异。
2. 新增回归覆盖侧栏/底栏语义、当前页与首页/分类 State 保留、海报密度、懒加载收藏、推荐卡比例、详情加载态、播放主栏/交流栏、草稿保留及低高度大字体。
3. 页面 × 五种窗口 × 三档字体的 **135 个组合**无框架渲染错误；分类另外滚动到网格以测量其几何。使用实际 AppShell 验证顶层页面，480dp 窗口仍是模拟。
4. `flutter analyze --no-pub` 无问题，原生测试执行器通过 Node 语法检查。
5. 真机正常入口检查首页、分类网格、详情和个人页；正常入口的详情成功态已加载，两个方向均存在“立即观看”操作。固定目录包的详情请求未纳入夹具，曾显示预期错误态，不将该截图当成真实源站故障。

机器可读样本、几何、构建指纹与证据索引见 [结果 JSON](performance/20261029-tablet-layout-results.json)。

## 真实原生视频

执行入口为 `scripts/test-tablet-layout.mjs`，测试为 `apps/mobile/integration_test/tablet_player_layout_test.dart`。使用已存在的本机合成 MP4，通过 USB 反向端口访问，不访问第三方影视播放地址、不创建真实房间、不写入原账户的观看记录。

本机实测通过：

- media_kit 原生真实首帧，视频源 640×360；不是占位封面或假播放器。
- 横屏视频区域宽 **864dp**，交流区位于右侧；竖屏视频宽约 **821.33dp**，交流区回到下方。
- 暂停并定位到约 12 秒后旋转，VideoController 对象、来源 generation、进度和输入草稿保留。
- 真实系统输入法弹出，原生输入法状态为已显示，输入框在实际键盘遮挡区域上方。
- 全屏进入/退出、系统 PIP 进入/返回，控制器和来源保留。

测试曾因测试绑定缓存 EditableText，第二次请求键盘未发出；清空测试绑定缓存后，真实 IME 检查通过。PIP 过渡中 Surface 可短暂离屏，等待谓词改为安全枚举节点后通过；没有放宽控制器、进度或输入框位置的断言。原始失败日志保留在私有输出目录。

测试结束已清理本轮 USB 反向端口、恢复原旋转锁定，随后重新安装正常 Profile 应用。Native 回归验证的是合成视频与本机能力，不代表所有源站、4K/HDR、系统分屏或长时间播放已经验收。

## 真机性能对照

对照基线为本轮开始时已有的图片、访客与 192MiB Skia 预算版本，而不是原始 Git HEAD。两侧都是同一台 TB711FU、Profile、同一 84 条固定元数据与真实 HTTPS 图片、相同的 40 秒操作窗口，各三轮。导航位置变化后，按实际原生 UI 节点重新取得点击坐标，操作语义与计划时间保持一致。

| 指标（三轮中位数） | 适配前 | 适配后 | 变化 |
| --- | ---: | ---: | ---: |
| 总 PSS | 625.29 MiB | 577.97 MiB | -7.57% |
| Graphics | 410.93 MiB | 371.61 MiB | -9.57% |
| 解码图片缓存 | 53.33 MiB | 39.95 MiB | -25.08% |
| build p95 | 1.316 ms | 1.262 ms | 基本持平 |
| raster p95 | 8.871 ms | 8.792 ms | 基本持平 |

PSS 范围为 621.26–628.99 → 537.55–589.37MiB；raster p95 范围为 8.313–9.152 → 8.206–9.931ms。所有有效轮次均保留，没有因数值较高而剔除。热状态均为 0，保留系统动态刷新策略，逐轮刷新率快照为 60Hz。

这些数值支持本设备浏览场景的内存改善，不能将 0.079ms 的差值称为明确绘制提速。新旧布局可见海报数量和尺寸不同，这是同片单操作下的整体界面对照，不是单一缓存参数的隔离实验。PSS/Graphics 为结束快照，不是峰值，二者不能简单相加；FrameTiming raster 也不是硬件 GPU 时间或 FPS。

固定场景不包含正常源站加载延迟、视频解码或逐图首帧速度。后续的低高度播放和详情加载态位置修正不在该浏览计时流程中；最终正常包包含这些修正。

## 文件、影响与回滚

| 文件（相对仓库根） | 用途与影响 |
| --- | --- |
| `apps/mobile/lib/design/{window_layout,adaptive_app_frame,adaptive_watch_layout}.dart` | 新增共享布局规则及稳定展示槽位 |
| `apps/mobile/lib/design/bottom_navigation.dart`、`components.dart` | 侧栏、点击语义和共享正文限宽 |
| `apps/mobile/lib/features/catalog/{app_shell,home_content,category_discovery,posters,tablet_feature_card}.dart` | 壳层、轮播、海报密度、解码提示和语义 |
| `apps/mobile/lib/features/catalog/{detail_page,collection_pages,profile_page,search_page}.dart` | 详情组合、懒加载收藏、个人及列表宽度 |
| `apps/mobile/lib/features/experience/{experience_player,short_feed}.dart` | 长短视频布局，保留原回调与核心控制器 |
| `apps/mobile/test/tablet_*_test.dart`、`navigation_polish_test.dart` | 新行为与状态回归；原底栏动画测试明确使用手机窗口 |
| `apps/mobile/integration_test/tablet_player_layout_test.dart`、对应 README、`scripts/test-tablet-layout.mjs` | 可重复的真实视频、旋转、键盘、全屏/PIP 验收 |
| 本报告及结果 JSON | 实施与证据记录 |

本轮开始时已有 23 个未提交文件，已完整保存于 `.local/tablet-implementation-20261029/baseline/`，哈希与基线 HEAD 在 `baseline-manifest.json`。回滚本轮时：已有工作区改动的文件使用该快照；本轮从干净状态修改的文件使用基线 HEAD；仅删除本轮新增文件。不要整体还原到 Git HEAD，否则会丢失上一轮未提交的图片/访客/GPU 优化。

本轮没有提交或推送。APK、原图、测试夹具与原始日志位于忽略目录；报告 JSON 不包含完整片源或图片地址。原生测试中的临时请求头只存在于私有 define 文件，执行器结束时清理。

## 验收状态与限制

- DONE：三个布局切片、手机视觉回归、状态测试、字体/窗口矩阵、真机正常入口、真实视频/键盘/全屏/PIP、性能记录。
- DONE：严格 UTF-8/LF、无 BOM/替换字符、差异/范围检查与测试执行器清理检查。
- NEXT（可选）：其他 Android/iPad、真实系统分屏拖动、TalkBack 实际朗读与外接键盘、4K/HDR及60分钟以上播放资源增长。

仓库结构检查既有的 `apps/mobile/docs/playra-layout-reference.md` CRLF 问题不属于本轮修改，仍需单独处理；本轮没有扩大范围改动该文档。
