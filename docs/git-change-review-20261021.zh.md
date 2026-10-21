# Duoscene 全量 Git 改动分析与提交说明

日期：2026-10-21（Asia/Singapore）。分析基线：`ddd642025d9ffc932959d89df88797d90e08105c`。
目标远程仓库：https://github.com/haigepor/Duoscene 。本次任务是梳理现有改动、编写中文说明、分组提交并推送，不新增产品功能。

## 一、项目结构和实际边界

Duoscene 是双人私密观影应用。Flutter 客户端负责账户页面、片库、收藏/历史、房间和播放器；Fastify API 负责账户、会话、房间、邀请和实时协调；视频由客户端直接向片源获取，API 不作为视频转发服务。

| 目录 | 职责 | 本轮改动 |
| --- | --- | --- |
| `apps/mobile/lib/app` | 应用装配、账户生命周期与主题 | 主题对象复用，统一明暗表现 |
| `apps/mobile/lib/core` | HTTP、模型及通用界面能力 | 仅登录超时提示分流 |
| `apps/mobile/lib/design` | 色板、组件、导航、动效与外观偏好 | 统一蓝色、插图、弹层、票签与缓存分页 |
| `apps/mobile/lib/features` | 认证、片库、播放、房间和实时页面 | 本轮主体，保留原有服务/状态对象 |
| `apps/mobile/assets/design` | 图片、SVG、字体与许可证 | 新增 WebP/箭头，替换五张 PNG，删除森林背景 |
| `apps/mobile/test`、`integration_test` | 单元、Widget 和设备验收 | 补充布局、状态、资源及回归测试 |
| `apps/mobile/web`、`tool`、`scripts` | Web 预览、性能测量和本机调试 | 独立预览入口、基准入口与 ADB reverse |
| `apps/api` | Fastify、MySQL、账户、房间和实时服务 | 无源代码改动，只执行已有回归 |
| `packages/contracts`、`infra` | 协议契约及基础设施 | 无改动 |

核心依赖方向仍为 app → features → core。页面继续使用 Navigator、ChangeNotifier、ValueNotifier 与现有 LibraryState；播放器继续沿用固定的 Playra/media-kit 实现。本次不进行路由框架、依赖注入、数据库或媒体底层迁移。

## 二、Git 范围和提交原则

- 开始时位于 `main`，只有一个本地基线提交，暂存区为空，尚未配置 remote。
- 远程 `git ls-remote` 成功返回空引用，检查时目标仓库没有分支或提交。因此推送会同时上传本地基线历史。
- 原始工作区共 103 个变更路径：53 个已跟踪路径变化、50 个未跟踪新增路径。
- 本次另新增本文，最终覆盖 104 个路径。修正两个原本已变更的集成测试文件中的失效定位文案，没有改写其余产品代码。
- 规范化候选树在加入本文前为 9,408 行增加、2,582 行删除；统计包含新增测试和既有中文阶段文档，图片按二进制记录。
- 采用九个顺序依赖的提交：先资源，再共享设计，再业务页面，最后接入导航性能优化与最终验收说明。
- 每个提交提供中文标题、动机、具体行为和边界。共享设计提交涉及调用方迁移，不能只回退色板或枚举而保留消费者。
- 测试通过结果来自最终工作树，不宣称九个中间提交分别重跑了完整测试。跨页面共用测试在最终状态统一验收。
- 不改写已有基线、不强制推送、不创建与本任务无关的分支、标签或远程资源。

## 三、九个提交的详细说明

### 1. feat(assets): 更新观影素材并统一海报与插图渲染

为首页、认证、收藏与设置准备统一的玻璃插图和独立海报素材，避免生成图中的文字与业务控件混在一起。

- 新增首页裁片与账户、票根、对话、外观、音频、隐私等透明 WebP 插图。
- 将五张片库 PNG 替换为 WebP，并同步 Film.image 的扩展名，资源与引用在同一提交交付。
- 新增 DSIllustration/DSIntro，按显示尺寸和像素比限制解码尺寸，装饰图退出读屏语义。
- 海报支持 editorial 展示，统一 homeArtwork/homeMetadata；保留影片标题和操作的原生控件。
- 详情封面解码宽度限制在 480–1080，搜索缩略图限制为 192；更新前进箭头。

保留关键横幅 PNG 与原媒体引擎，不改片库数据结构、鉴权或播放协议。

文件数量：33。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/assets/design/media/account-identity-glass.webp`
- `apps/mobile/assets/design/media/appearance-glass.webp`
- `apps/mobile/assets/design/media/audio-glass.webp`
- `apps/mobile/assets/design/media/auth-account-glass.webp`
- `apps/mobile/assets/design/media/auth-filmstrip-glass.webp`
- `apps/mobile/assets/design/media/auth-key-glass.webp`
- `apps/mobile/assets/design/media/collection-favorites-glass.webp`
- `apps/mobile/assets/design/media/collection-history-glass.webp`
- `apps/mobile/assets/design/media/conversation-glass.webp`
- `apps/mobile/assets/design/media/duo-tickets-glass.webp`
- `apps/mobile/assets/design/media/frame-short-drama.webp`
- `apps/mobile/assets/design/media/home-v2-artwork.webp`
- `apps/mobile/assets/design/media/home-v2-mountains.webp`
- `apps/mobile/assets/design/media/home-v2-river.webp`
- `apps/mobile/assets/design/media/home-v2-stars.webp`
- `apps/mobile/assets/design/media/home-v2-summer.webp`
- `apps/mobile/assets/design/media/home-v2-valley.webp`
- `apps/mobile/assets/design/media/poster-clouds.webp`
- `apps/mobile/assets/design/media/poster-mountains.webp`
- `apps/mobile/assets/design/media/poster-stars.webp`
- `apps/mobile/assets/design/media/poster-summer.webp`
- `apps/mobile/assets/design/media/privacy-glass.webp`
- `apps/mobile/assets/design/icons/arrow-right.svg`
- `apps/mobile/assets/design/icons/chevron-right.svg`
- `apps/mobile/assets/design/media/frame-short-drama.png`
- `apps/mobile/assets/design/media/poster-clouds.png`
- `apps/mobile/assets/design/media/poster-mountains.png`
- `apps/mobile/assets/design/media/poster-stars.png`
- `apps/mobile/assets/design/media/poster-summer.png`
- `apps/mobile/lib/design/illustrations.dart`
- `apps/mobile/lib/features/catalog/catalog.dart`
- `apps/mobile/lib/features/catalog/posters.dart`
- `apps/mobile/lib/features/catalog/search_page.dart`

</details>

### 2. feat(design): 统一蓝色明暗主题、弹层和页面动效

将跨页面表现收敛到统一蓝色语义主题，消除森林专用分支和播放器白色文字向业务弹层的继承问题。

- 移除 woodland/forest 选项及背景，旧 forest:<mode> 偏好迁移为 sky:<mode>，保留明暗选择与账户数据。
- 复用浅色/深色 ThemeData，统一文字、分隔线、输入边框，关闭全局墨水覆盖层。
- 新增 showDSSheet/DSSheetContent，统一弹层高度、键盘滚动、前景色和减少动画行为。
- 外观页改为明暗分段选择，窄屏或大字号纵向展开；共享组件补充居中标题、紧凑菜单和副标题。
- MotionTabs 缓存页面、暂停隐藏页 Ticker/焦点/点击/语义，支持首次目标页预布局和整页侧移。
- 平台路由沿用移动端 Cupertino 与桌面 FadeUpwards；分类票签与线形 Tab 使用连续移动指示器。
- ScrollChrome 合并布局阶段的滚动校正通知，避免布局期间同步要求顶部重建。
- Web 入口由 lib/main_preview.dart 移至 web/main.dart，复用移动页面并限制为独立示例身份。
- 更新明暗/导航测试及原生截图矩阵；同步双人测试的主题选项和登录按钮文案。

导航壳层的首次切换调度在后续性能提交接入；不进行依赖注入框架或媒体底层迁移。

文件数量：20。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/lib/app/duoscene_app.dart`
- `apps/mobile/lib/app/theme.dart`
- `apps/mobile/lib/design/components.dart`
- `apps/mobile/lib/design/palette.dart`
- `apps/mobile/lib/design/theme_preferences.dart`
- `apps/mobile/lib/design/motion.dart`
- `apps/mobile/lib/design/scroll_chrome.dart`
- `apps/mobile/lib/features/experience/appearance_page.dart`
- `apps/mobile/assets/design/media/forest-atmosphere-v2.png`
- `apps/mobile/test/appearance_test.dart`
- `apps/mobile/test/appearance_page_test.dart`
- `apps/mobile/test/ui_motion_test.dart`
- `apps/mobile/integration_test/realtime_pair_test.dart`
- `apps/mobile/integration_test/ui_gallery_test.dart`
- `apps/mobile/tool/ui-native.mjs`
- `apps/mobile/lib/main_preview.dart`
- `apps/mobile/web/main.dart`
- `apps/mobile/web/index.html`
- `apps/mobile/web/README.md`
- `scripts/start-web-preview.ps1`

</details>

### 3. feat(auth): 重构开放式认证表单并完善本机登录联调

让登录、注册和找回密码使用相同的开放式表单节奏，并修正登录失败提示与 Android 本机服务连接方式。

- 抽出 AuthBody/AuthIntro/AuthLink 与输入装饰，统一 400dp 内容宽度、24dp 横向留白及紧凑标题间距。
- 登录保留品牌与外观入口，使用轻量注册入口；胶片装饰在键盘、小高度和大字号下隐藏。
- 注册密码和确认密码分别控制显隐，避免查看一个字段时同时暴露另一个。
- 保留账户/密码/恢复码校验、提交禁用、恢复码只展示一次和安全保存确认门槛。
- 登录超时提示检查网络与服务地址，房间写入超时继续提示先刷新核实结果，均不自动重试。
- 新增 ADB reverse 调试脚本，显式传入回环 API_BASE_URL，支持雷电、官方模拟器与 USB 设备。
- 补充独立显隐、超时单次请求、两种明暗、320dp/200% 字体和键盘可达性回归。

同步中文设计/间距说明与移动端开发文档；不加入固定账户、密码或自动登录逻辑。

文件数量：12。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/lib/features/auth/login_page.dart`
- `apps/mobile/lib/features/auth/account_access_page.dart`
- `apps/mobile/lib/features/auth/auth_widgets.dart`
- `apps/mobile/lib/core/api_client.dart`
- `apps/mobile/test/account_access_test.dart`
- `apps/mobile/test/app_test.dart`
- `apps/mobile/test/auth_layout_test.dart`
- `apps/mobile/test/api_client_test.dart`
- `apps/mobile/README.md`
- `scripts/start-mobile-debug.ps1`
- `docs/auth-open-layout-20261021.zh.md`
- `docs/auth-spacing-20261021.zh.md`

</details>

### 4. feat(catalog): 重构推荐首页并实现分类筛选与分批浏览

将推荐内容和分类发现职责分开，让小片库也能提供真实、可结束的筛选与浏览流程。

- 首页采用独立画面/信息区轮播、可横滑续播卡、真实房间创建/加入入口及分类型推荐。
- 轮播在手势结束后重新计时，响应 TickerMode、应用前后台和减少动画，后台不继续推进。
- 新增 CatalogSelection/CatalogDiscovery，每类独立保留题材、片长或集数、排序、片单顺序和浏览位置。
- 采用单一 CustomScrollView、紧凑片单、横向海报及 SliverGrid；大字号调整列数。
- 按影片 ID 去重，靠近底部最多追加 12 条已有片目，到底明确结束，筛选无结果可重置。
- 续播保留各条记录的集数与进度；测试覆盖缺失记录、轮播恢复、筛选边界与 12→24→36→40 分批结束。

数据仍来自现有静态片库；未接入远程分页、热度、更新时间或真实资源接口。

文件数量：6。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/lib/features/catalog/home_page.dart`
- `apps/mobile/lib/features/catalog/home_content.dart`
- `apps/mobile/lib/features/catalog/category_discovery.dart`
- `apps/mobile/test/home_content_test.dart`
- `apps/mobile/test/category_discovery_test.dart`
- `docs/catalog-discovery-implementation-20261021.zh.md`

</details>

### 5. feat(library): 统一收藏记录、个人中心和设置页面

统一收藏与记录的导航、筛选和管理层级，收紧个人中心和设置的信息密度。

- 记录与收藏共用布局、筛选、空状态和本机隐私说明，筛选切换清理旧选择，删除期间禁用冲突操作。
- 个人/共同观看进度使用 secondary 呈现，避免隐私页再套一层完整导航。
- 记录提供保留集数/进度的继续观看入口；收藏使用独立海报和响应式网格。
- 个人中心收紧头像与收藏卡，设置分组展示，保留底栏区域的末项可达性。
- 账户信息采用名片布局，真实账户名可选中/复制，复制失败给出手动复制提示。
- 隐私、音频、帮助和关于使用统一插图与紧凑菜单，保留清理确认和退出确认。
- 详情封面限制为视口 36% 且不超过 320dp，封面操作使用独立深色圆片保持对比度。

继续沿用 LibraryState 的账号隔离与持久化，不新增云端同步或虚构的缓存清理能力。

文件数量：7。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/lib/features/catalog/collection_pages.dart`
- `apps/mobile/lib/features/catalog/profile_page.dart`
- `apps/mobile/lib/features/catalog/detail_page.dart`
- `apps/mobile/lib/features/experience/settings_pages.dart`
- `apps/mobile/test/favorites_page_test.dart`
- `apps/mobile/test/history_page_test.dart`
- `apps/mobile/test/settings_polish_test.dart`

</details>

### 6. feat(rooms): 统一房间页面并收紧邀请与选集弹层

让创建、加入、成员详情与发出邀请采用一致的页面骨架，并减少邀请弹层的无效刷新。

- 房间列表/表单/详情复用 PageFrame 与票根插图，创建和加入按钮在窄屏或大字号下纵向排列。
- 保留完整 43 位邀请码校验、成员刷新、两席限制与仅房主可邀请的原有约束。
- 邀请弹层将分享设为主要操作，复制和进入房间并排；分钟倒计时与撤销合为状态行。
- 倒计时仅在显示分钟变化和准确到期边界调度，销毁或撤销时清理计时器。
- 选集弹层统一语义色与按钮触控高度，保留共同观看确认和等待流程。
- 更新房间集成测试中的登录/加入入口文案，补充明暗、小屏大字号、复制复用和撤销布局验证。

后端房间接口、鉴权、邀请令牌和真实双人同步协议保持原实现。

文件数量：8。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/lib/features/rooms/room_form_page.dart`
- `apps/mobile/lib/features/rooms/room_list_page.dart`
- `apps/mobile/lib/features/rooms/room_detail_page.dart`
- `apps/mobile/lib/features/experience/invite_pages.dart`
- `apps/mobile/lib/features/experience/episode_sheet.dart`
- `apps/mobile/integration_test/rooms_flow_test.dart`
- `apps/mobile/test/invite_sheet_layout_test.dart`
- `docs/invite-sheet-layout-20261021.zh.md`

</details>

### 7. feat(player): 整合观影片源、同看、音频与聊天操作

把个人观影的片源、同看、音频与清晰度入口收拢到统一控制区，给聊天和输入法留出稳定空间。

- 新增 WatchControls/WatchComposerBar/WatchCover，复用既有 PlayerPresentation 和片源选择能力。
- 未选片源时先引导选择视频，再进入邀请；清晰度仅展示源实际报告的有效视频轨道。
- 观看页按可用高度限制媒体区，键盘弹出时收起封面，保留原生播放器实例及退出记录流程。
- 聊天支持紧凑状态栏和多行输入，消息区保留可用高度，装饰与空状态复用玻璃插图。
- 短剧页统一深色覆盖层与侧边操作，选集响应减少动画，隐藏 Tab 或路由覆盖时停止持有媒体页。
- 无媒体封面限制解码宽度并提供失败占位；真实同看音频弹层复用业务弹层前景色。
- 补充键盘、小屏大字号、无片源、图片失败、个人/共同观看与短剧控制可达性测试。

保留现有媒体引擎、手动暂停意图、播放命令串行化和房间实时对象的所有权。

文件数量：8。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/lib/features/experience/experience_player.dart`
- `apps/mobile/lib/features/experience/chat_panel.dart`
- `apps/mobile/lib/features/experience/short_feed.dart`
- `apps/mobile/lib/features/experience/watch_controls.dart`
- `apps/mobile/lib/features/playback/widgets/player_library_view.dart`
- `apps/mobile/lib/features/realtime/room_watch_page.dart`
- `apps/mobile/test/watch_layout_test.dart`
- `apps/mobile/test/short_feed_layout_test.dart`

</details>

### 8. perf(navigation): 优化首次切页并同步玻璃底栏与页面过渡

减少切换 Tab 时无关页面重建，让首次布局不占用底栏和内容的过渡时长。

- AppShell 使用局部 ValueNotifier 管理选中页与准备页，仅业务数据变化时刷新页面描述。
- 首次点击先离屏布局目标页，下一帧同步提交页面位移和底栏滑块；缓存页直接切换。
- 选择代次拦截过期回调，支持快速反向、点击当前项取消、减少动画立即切换与销毁安全。
- 玻璃底栏使用有界模糊和单个连续移动滑块，绘制选中项与实际选择决策分离。
- 内容延伸至底栏后方，预览壳层遵守相同规则，各页面预留末项空间。
- 新增独立 debug/profile 基准入口，不依赖真实登录，不放宽正式 HTTP/HTTPS 安全校验。
- 回归覆盖首次准备帧、页面/底栏同步、缓存页数据刷新、后台轮播暂停和连续反向。

性能文档保留历史采样条件与未解决的首次长帧；模拟器数据不等同于真机帧率保证，未完成整体架构迁移。

文件数量：7。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/lib/design/bottom_navigation.dart`
- `apps/mobile/lib/features/catalog/app_shell.dart`
- `apps/mobile/lib/features/experience/preview_gallery.dart`
- `apps/mobile/test/navigation_polish_test.dart`
- `apps/mobile/tool/navigation_benchmark.dart`
- `docs/first-transition-performance-20261021.zh.md`
- `docs/playra-architecture-alignment.zh.md`

</details>

### 9. docs(review): 汇总全量改动、提交边界与本次验证结果

为本轮九个提交提供可追溯的中文说明，区分已有阶段报告、本次实际检查和仍未解决的问题。

- 汇总项目职责、103 个原始改动文件的功能边界、九个提交的依赖顺序及逐文件清单。
- 纳入页面统一历史报告与资源存在性/工具栏/二级进度页面回归。
- 记录 Flutter 静态分析、106 项测试、后端 23 项测试、类型检查、构建及普通 Web 构建结果。
- 说明工作区 CRLF 导致结构检查失败，而规范化 Git 候选树通过；不批量重写无关文件。
- 如实记录 Web debug 分类切换的 Semantics node map 异常，不将视觉可操作误报为无错误。
- 记录本次修正的失效主题/登录测试文案，保留未重跑真机、双人同步和语音的验证边界。
- 提供依赖逆序回退方式，临时日志、原始差异和备份留在已忽略的 .local 目录。

不提交账户凭据、构建产物、临时截图或本机调试状态。

文件数量：3。

<details>
<summary>逐文件清单</summary>

- `apps/mobile/test/ui_unification_test.dart`
- `docs/ui-unification-20261021.zh.md`
- `docs/git-change-review-20261021.zh.md`

</details>

## 四、本次执行的验证

| 检查 | 本次结果 | 证据和限制 |
| --- | --- | --- |
| 项目指定 SDK | PASS | 使用 `scripts/mobile-env.ps1` 指定的 Flutter/Dart；首次误用系统旧版 Dart 的检查已作废，随后重新执行 |
| `flutter analyze` | PASS | 全目录无问题；修正两个集成测试的失效文案后再次通过 |
| `flutter test --reporter expanded` | PASS | 106 项全部通过，覆盖认证、会话、房间、媒体控制、分类、续播、收藏、记录、主题、布局和导航 |
| 认证/外观定向回归 | PASS | 修正集成测试定位文案后，`appearance_page_test.dart` 与 `app_test.dart` 共 10 项通过 |
| `npm run typecheck` | PASS | 后端 TypeScript 测试配置类型检查通过 |
| `npm test` | PASS | 契约 3 项、API 20 项，共 23 项全部通过，无跳过 |
| `npm run build` | PASS | 后端构建通过 |
| 普通 Web 预览构建 | PASS | `flutter build web --debug -t web/main.dart --dart-define=DUOSCENE_STYLE_PREVIEW=true` 成功 |
| Wasm 可用性 | 未通过兼容性预检查 | 编译器报告 media-kit 原生 `dart:ffi` 不兼容 Wasm；普通 JavaScript Web 构建仍成功，不宣称 Wasm 支持 |
| 当前工作区 `npm run check:structure` | FAIL | 首个失败为未改动的 `apps/mobile/docs/playra-layout-reference.md: expected LF newlines`；实际还有若干工作区 CRLF 文件 |
| 规范化 Git 候选树结构检查 | PASS | 使用独立 Git index 按 `.gitattributes` 生成树并导出；383 个文本文件的结构、JSON、相对 TypeScript 引用、UTF-8/LF 均通过 |
| `git diff --check` | PASS | 无新增空白错误；Git 给出的 CRLF→LF 提示属于规范化说明 |
| 文本与素材检查 | PASS | 441 个文本文件严格 UTF-8 解码；74 个原始改动文本无 BOM/替换字符；22 张 WebP 均具有正确 RIFF/WEBP 文件头 |
| 本次新增报告 | PASS | 使用 UTF-8 无 BOM、LF 写入并回读；逐文件清单自动由提交计划生成，防止遗漏 |
| 敏感路径与明显密钥模式 | PASS | 当前候选文件未发现被跟踪的凭据路径、私钥、GitHub/OpenAI/AWS 强特征密钥；非完整秘密审计 |
| 大文件 | PASS | 未发现达到 50 MiB 的候选文件，无需为本轮改动引入 Git LFS |
| Web 浏览器冒烟 | FAIL（语义树异常） | 可筛选和切页，但控制台出现 Flutter Semantics 一致性异常，详见下节 |
| Android/iOS 真机与双客户端 | 本次未执行 | 没有重跑真实后端设备注册/恢复、双人同步、语音、iOS 构建/签名或真机性能 |

### Web 运行时异常：已观察，未修复

本次把已构建的 Web 预览仅绑定到 `127.0.0.1:7369`，通过 Playwright 在 390×844 视口执行：

1. 推荐页进入“电影”。
2. 展开筛选并选择“科幻”，结果由 4 部变为 2 部，片目去重和到底状态可见。
3. 进入“我的”→“外观”→“深色”，界面提示更新为“始终使用深色外观”。

实际控制台错误：

`Bad state: Semantics node map was inconsistent after update:`

第一次发生在推荐切换电影的 scheduler callback，后续筛选、导航和主题切换继续出现错误。页面可操作不能抵消该异常，因此 Web 运行时检查明确记为 FAIL。异常在当前 debug 预览及已启用语义的环境中观察到；尚未定位是业务节点重挂载、Flutter Web 引擎行为还是两者交互，也未证明 Android/iOS 同样受影响。

该问题超出本次 Git 分组任务，没有采用关闭语义、吞异常或框架补丁来制造“通过”。错误输出保留在本地验收目录，后续可单独复现定位。

### 本次额外修正

- `realtime_pair_test.dart` 不再点击已删除的“晴空/森林”；改为验证“深色/跟随系统/浅色”。
- `realtime_pair_test.dart`、`rooms_flow_test.dart` 的“登录 Duoscene”定位改为当前“登录”。
- 上述调整属于测试与当前页面同步；没有重跑需要双设备、服务和夹具的原生端到端测试，所以不把它们标为运行通过。

## 五、历史文档与当前代码的差异

本轮待提交文档记录多个阶段，不能将每一份都当作最终实现说明：

- `invite-sheet-layout-20261021.zh.md` 中分类双列/下拉描述是较早阶段，最终代码已有 CatalogDiscovery 的筛选面板和 SliverGrid。
- `catalog-discovery-implementation-20261021.zh.md` 描述分类改为标题旁搜索图标；当前 `home_page.dart` 实际仍通过共用 discoveryHeader 展示完整搜索栏，文档此处存在漂移。
- `README.md` 中“WS 尚未实现”落后于现有 `apps/api/src/app.ts` 对 websocket/realtime hub 的装配；这是既有基线文档问题，本次没有扩展修改。
- 各阶段报告中的 78/85/88/95/98 项测试、原生截图及性能数据都是历史记录。本次确认的是 106 项完整 Flutter 测试和本报告列出的实际检查，不重新背书其余历史设备证据。
- 历史回退目录、设计原图与性能追踪大多位于 Git 忽略的 `.local`；远程克隆不会带上这些本机文件。远程回退应依靠 Git 提交。

## 六、风险、回退与提交后的核对

### 剩余风险

1. Web debug 的 Semantics 异常尚未定位，Web 冒烟未全绿；需要独立问题切片处理。
2. Flutter Widget 测试和普通 Web 构建不能替代 Android/iOS 真机、系统输入法、双人同步、网络异常及长时间播放验证。
3. 首页和分类仍是静态片库，收藏/记录仍为本机账户隔离数据；没有实现云端片库、远程分页或个性化推荐。
4. 首次切页和栅格长帧的历史性能边界仍保留，不能以本轮静态检查宣称真机稳定 60fps。
5. 九个提交是共享设计与页面的依赖栈，存在跨提交依赖；回退应按依赖逆序进行。

### 回退位置

- 远程可复现基线：`ddd642025d9ffc932959d89df88797d90e08105c`。
- 已共享提交优先使用 `git revert`，从第九个提交向第一个提交逆序回退；不要强推共享分支或用全局还原覆盖新工作。
- 本机原始差异、原始 103 路径哈希、两个集成测试修正前备份、提交计划、候选树和检查输出：`.local/git-delivery-20261021/`。
- 除上述两个测试文件和本文外，本次没有重写用户已有源代码。原始路径哈希核对未发现其他内容变化。

### 交付核对

- DONE：项目与全部原始变更路径分析，104 个路径归入九个提交计划，无重复和遗漏。
- DONE：中文提交信息、本文逐文件清单、静态/测试/构建和浏览器检查。
- 提交与推送结果以最终 Git 日志、工作区状态和远程 main 哈希核对为准；本文不提前声称远程已成功写入。
- NEXT（可选）：独立修复 Web Semantics 问题，校准阶段文档与最终代码，并执行真机/双客户端回归。
