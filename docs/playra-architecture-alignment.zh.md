# Playra 架构与 Duoscene 导航对齐

核对日期：2026-10-20。参考 `D:/project/Playra` 当前工作区源码；其中有未提交改动，本次仅做只读分析。

## Playra 的实际组织

| 层次 | 职责 | 当前源码 |
| --- | --- | --- |
| 启动与装配 | 初始化平台、存储、媒体；创建依赖容器与应用根节点 | `lib/main.dart`、`lib/app_module.dart`、`lib/core_module.dart` |
| 根业务对象 | Repository、服务、收藏/历史/下载等跨页 Controller 由根模块持有；页面局部对象按路由管理 | `lib/core_module.dart` |
| 路由 | `flutter_modular` 模块集中注册路径、参数与页面；主 Tab 与二级 push/pop 分开 | `lib/pages/index_module.dart`、各功能 `*_module.dart` |
| 展示 | `presentation/modern` 为新版 UI；`legacy` 保留旧导航；`shared` 管共享壳层。旧叶子页仍在 `pages` | `lib/presentation/README.md` |
| 状态 | 既有业务 Controller 使用 MobX；新版展示状态也使用 ChangeNotifier、ValueNotifier | `lib/pages/collect/collect_controller.dart`、`lib/presentation/modern/home/modern_home_controller.dart` |
| 外部能力 | Repository 管本地数据，Service 管网络、来源、同步、下载；Coordinator 编排调用 | `lib/repositories`、`lib/services`、`lib/services/source/sdk_playback_coordinator.dart` |
| 播放 | PlayerController 协调播放、拖动、面板、截图、弹幕和同步子 Controller；底层复用 media_kit | `lib/pages/player/player_controller.dart` |

这是逐步演进的分层项目。不能仅根据文件夹名把它概括成完全统一的 MVVM，也不能认为新版 Widget 自己拥有所有业务数据。

## 与切页性能直接相关的实现

### 主 Tab

`presentation/shared/tab_shell.dart` 持有选中项、系统返回及根路由覆盖状态；导航外观接收索引、回调与内容。

`presentation/shared/mobile_tab_view.dart` 使用：

- 页面工厂与已访问页面实例缓存；首次访问才构建，不跨越中间 Tab。
- `Stack + FractionalTranslation + AnimationController`，整页按方向横移。
- 280ms、`easeOutCubic`；快速反向点击从当前绘制位置继续。
- `Offstage` 保留页面状态；不可见页禁止点击、焦点、读屏并暂停 Ticker。
- `RouteVisibility` 统一发布被二级页面覆盖的状态。

### 二级路由

`utils/constants.dart` 的统一平台过渡：Android、iOS、macOS 使用 `CupertinoPageTransitionsBuilder`；Windows、Linux 使用 `FadeUpwardsPageTransitionsBuilder`。桌面设置导航另有局部覆写。

`index_module.dart` 的 70ms Tab 淡入是路由模块策略，不能与新版移动壳层的 280ms 整页横移混为一谈；图片预览另用 220ms 淡入。

## 本次在 Duoscene 落实的对应关系

| Duoscene | 与 Playra 对齐的行为 |
| --- | --- |
| `AppShell` | 持有 Tab 选择；重复选择不重建；拥有根路由覆盖状态 |
| `MotionTabs` | 缓存页面实例、整页横移、280ms easeOutCubic、反向接续、状态保留 |
| `MotionTabs.isCovered` | 壳层覆盖时统一停用 Ticker、命中、焦点与读屏 |
| `WatchHome.active`、`ShortFeed.active` | 选中状态与覆盖状态共同决定活动，及时暂停轮播与短剧 |
| `DSPageTransitions` | 按 Playra 的平台映射使用原生过渡，并保留减少动画支持 |

Duoscene 继续通过现有 `children` 接口接入页面：父级变化只刷新过渡中的页，其余缓存页重新显示时更新。这样能够保留当前 `LibraryState` 的最新值和 `active=false` 通知，不把可变业务状态冻结进旧闭包。

**已对齐导航职责与动效行为；整个项目的依赖体系尚未与 Playra 完全一致。** Duoscene 当前仍以 Navigator、ChangeNotifier/Scope 与 feature 目录组织业务，并没有完成 flutter_modular、MobX、Hive 的跨模块迁移。后续功能应依照根对象、页面状态、服务、存储的职责分别接入，不能把本次导航对齐描述为整体架构迁移完成。

## 验证与性能结论边界

- `flutter test test/ui_motion_test.dart test/appearance_page_test.dart`：13 项通过。
- 覆盖隐藏页延迟更新、重新显示取得最新内容、反向切换、减少动画、路由返回保留输入、覆盖时暂停 Ticker 并恢复原页面，以及窄屏和大字号。
- 修复前可稳定复现隐藏页跟随父级重建；新增测试先失败，修复后通过。
- 调试版模拟器的原生帧采样出现过 60–140ms 构建长帧。重复测量受 JIT、首次构建、模拟器负载等影响较大，不能宣称所有首次切换已稳定 60fps。
- 尝试过给路由单纯增加 RepaintBoundary、使用 Zoom 页面快照；没有稳定性能收益或出现额外开销，均未保留。最终以用户指定的 Playra 原生路由为准。
- 临时测量脚本和原始数据位于 `.local/navigation-perf.cjs`、`.local/navigation-*.json`；底部导航采样用临时预览壳层，不登录真实账户。
- 回退基线位于 `.local/backup/navigation-performance-20261020/`，包括本次修改前的 `motion.dart`、`app_shell.dart` 与测试文件。

剩余验证：Android 真机 profile 构建的帧耗时、冷启动与首次图片解码；模拟器 debug 结果不能替代生产性能结论。

## 登录联调与其他页面分析

本节基于源码核对，尚不代表人工登录后的逐页交互验收。已通过本机现有注册接口创建测试账号，独立验证登录、读取身份及退出；Android 登录页已填入凭据，未提交登录。凭据与恢复码仅保存于 Git 忽略的 `.local` 目录，应用源码不加入固定密码或自动登录逻辑。

### 页面职责对照

| 页面 | Duoscene 当前实现与差异 | 沿用 Playra 的重构方向 |
| --- | --- | --- |
| 首页 | `catalog/home_page.dart` 的 Widget 从常量 `films` 筛选分类；轮播在 `home_content.dart` 管定时器，已响应活动页、覆盖及应用前后台状态 | 参考 `modern/home/modern_home_controller.dart`：页面 Controller 管分类、加载和派生内容，片目由 Repository 提供；收藏与历史继续复用共享业务对象 |
| 搜索 | `SearchPage` 已有可注入的 `CatalogRepository`，`SearchState` 用请求代次避免旧结果覆盖；默认 `DesignCatalog` 只检索本地设计数据，输入每次变化均发起搜索，结果由 `ListView(children)` 一次创建 | 参考 `ContentSearchSession` 的会话和取消机制；接真实来源时补充取消、分页和按需创建结果项，避免把网络与列表编排放回 Widget |
| 详情与选集 | `DetailPage` 展示传入的设计 `Film`，收藏直接调用 `LibraryState`；播放通过 `ExperiencePlayer`，`designSource` 仅允许调试注入样片，并非真实影片片源 | 参考 Playra 的来源 Controller、播放 Coordinator：展示资料、选择来源与解析播放分别负责；页面只提交明确的作品、集数和来源，复用现有 `PlaybackSession` |
| 历史与收藏 | `collection_pages.dart` 管筛选、多选、删除；`LibraryState` 同时拥有内存数据和 SharedPreferences 读写，按账号隔离并串行写入；记录通过设计片目 ID 查找 | 参考根模块持有的 `IHistoryRepository`、`ICollectRepository` 及 `ModernLibraryController`：持久化与页面派生状态分开；保留账号隔离、个人/共同记录区别与串行写入；真实片目接入前处理已下架或未知 ID |
| 我的与设置 | `ProfilePage` 从共享 Library 读取账号和收藏；外观已有独立 `ThemePreferencesScope`；播放与音频页修改 `LibraryState` 的音量字段，而 `persist()` 仅保存收藏和历史 | 参考 Playra 共享账号 Controller 与 `SettingsAppearanceHost`：设置只改变表现，不重建会话或返回栈；将音量偏好交给统一设置对象并明确持久化规则，房间语音状态仍由房间管理 |
| 个人播放器 | `PlaybackSession` 已封装 Playra 播放、拖动、面板、截图等 Controller，原生操作走串行队列；`ExperiencePlayer` 仍编排观看意图、恢复进度、音量和退出记录 | 保留播放底层及串行队列；把进度写入与续播协调集中到业务入口，Widget 保留布局和手势；进度变化使用局部监听，避免触发整壳层重建 |
| 房间列表与同看 | `RoomRepository` 已走真实鉴权请求；列表 Widget 自行管理分页；`RoomWatchPage` 组合 Connection、Playback、Voice 和 RoomPlayback，并在退出时按对象所有权释放 | 保留现有数据访问和同步职责；参考 Playra 页面局部 Controller 的生命周期组织列表状态；房间同步与个人播放继续分开，重构必须覆盖退出、断线、后台和重复请求 |

### 建议实施顺序与约束

1. **先拆数据职责，再接真实片目。** 从 `LibraryState` 中划出历史、收藏、偏好存储职责，保留现有接口作为渐进适配点；共享数据按账号生命周期持有，页面局部状态跟随路由销毁。
2. **首页与搜索作为首个页面切片。** 复用 `CatalogRepository` 接入点，添加首页展示 Controller，并把列表改为按需构建；验收快速输入、切类、返回保留位置、旧请求失效和错误重试。
3. **详情与播放器沿用同一播放入口。** 先定义真实作品与来源身份，再处理续播与收藏关联；不能把虚构片目的集数当作真实可播放目录。
4. **历史、我的、设置跟随共享对象接入。** 避免通过整个 `LibraryState.notifyListeners()` 更新无关页面；保持删除确认、账号切换隔离和主题切换时表单状态。
5. **房间在独立切片验证。** 复用现有 Repository、实时连接和语音对象，不把房间命令混入个人历史或首页 Controller。

以上是职责与生命周期对齐方案，不包含本次对 `flutter_modular`、MobX 或存储框架的整体迁移。若要统一依赖注入与路由框架，需要单独制定跨模块迁移范围和回归验收。

源码存在一处文档漂移：`features/history/README.md` 仍写“尚未实现功能”，实际历史与本地持久化已在 `catalog/collection_pages.dart`、`catalog/library_state.dart` 实现；后续以这些运行代码为准。

人工测试建议依次检查：登录后首页 → 搜索/详情并返回 → 收藏 → 历史管理 → 我的/设置 → 房间列表。新账号的收藏、历史和房间允许为空；真实房间多人同步与语音仍需第二个客户端共同验收。
