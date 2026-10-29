# 上游更新与本地优化合并（2026-10-29）

## 范围与结果

远端 `origin/main` 已抓取到 `06a52492dbf0caaa2f24d070bdf0c8ab2d976dfb`，相对原基线 `435fea310b21dfe7c5279ea88167a6a247ec0461` 增加 14 个提交，涉及 97 个文件。整合在 `codex/merge-upstream-20261029` 分支进行，不推送远端。

原来的 45 个未提交文件已逐字节备份到 `.local/upstream-integration-20261029/baseline/`，索引、差异和哈希保存在同目录的 `baseline.json`、`index.patch`、`tracked-worktree.patch`。本地优化检查点为 `5390ba4`；它保留了本轮开始时的全部工作，便于与上游分别追溯。

## 上游的架构变化

| 变化 | 对调用链的影响 | 合并策略 |
| --- | --- | --- |
| 播放通知拆分、低内存设备减少实时模糊 | 时间进度由轻量通知驱动，页面使用结构状态通知；导航增加低内存设备策略 | 保留本地 192MiB Skia 预算与图片解码限制，合并进度通知、暂停状态更新及侧栏形态；Web 在读取 `Platform` 前短路 |
| 详情与线路统一集数 | `MediaDetail.unifiedFilm` 依据全部可用线路的最大集数；解析支持 `cachedDetail` 和跨线路落点 | 保留平板详情/选集布局，接入统一片目与线路；快速入口也在详情到达时更新集数，并把详情传给解析器复用 |
| 短剧入口与连播 | 首页/详情直接进入 `ShortFeed`；按剧缓存线路与详情，维护 pendingPlay、来源 generation、连播和分页 | 使用上游完整信息流业务树，外层保留本地平板 9:16 边界，不恢复旧的“逐集即逐页”实现 |
| 个人播放到同看房间的交接 | 传递 provider、片目、实际线路、剧集和进度，两端各自解析；拒绝静默回退到不同剪辑 | 保留实际 `sourceIdentity` 与线路的交接；个人浏览继续免登录，真实房间操作仍要求账户 |
| 服务端持久化 | 播放命令在候选时间线上执行，落盘成功后才发布/确认；自然进度定期检查点，恢复进入新纪元并暂停 | API、WebSocket 契约和对应测试完整接收上游，未改业务数据库或执行生产迁移 |
| 页面刷新与触点反馈 | 共享回顶信号、下拉刷新、紧凑标签、按压底色 | 与平板稳定槽位、内容限宽和海报密度合并；个人页在挂载阶段注册回顶监听并在销毁时解绑 |

业务状态仍由现有 LibraryState、目录 Provider、PlaybackSession 与房间状态机负责。布局模块只改变展示约束，不新建第二套播放器或目录缓存。

## 冲突与额外修复

Git 本轮报告 8 个内容冲突：导航、图片地址、分类、详情、个人、长视频、短剧以及图片策略测试。逐个合并两侧意图，未使用整文件“全部采用本地/远端”作为交付结果。

远端最新合并提交还带有 3 个已提交的冲突残留，Git 不会把它们列为本轮冲突：

- `features/playback/playback_session.dart`：轮询同时混入两个版本。统一由 `refreshState` 更新 position/buffer/state 轻通道，保留 presentation 通知边界；错误仅在实际播放位置继续前进时撤销。
- `features/catalog/providers/whisklet_provider.dart`：详情读取残留两套线路变量。保留按 code 去重、过滤空线路、不可变列表与跨线路最大集数。
- `test/catalog_data_test.dart`：两种 Provider 测试夹具被冲突标记拼到一起。分别保留骨架与慢首页夹具，继续验证两个行为。

其他交叉问题：

1. 上游删除了 `ShortPlaybackControls`，已有通知回归和重建基准仍引用旧控件。测试改用真实 `ShortScrubLine`，继续验证 5 秒进度、时长变化、页面不重建和空闲不通知；没有重新引入旧控件或删掉断言。
2. 图片策略保留本地对新 CDN 的自动 HTTPS 规范化，合并上游精确豆瓣 Referer 与可信代理直连规则。仅原始 `http://snzypic.com:80` 沿用上游的精确明文图片例外；其他标准 HTTP 地址升级 HTTPS，非标准 HTTP 端口仍拒绝。不因 HTTPS 失败全局降级，也不忽略证书错误。
3. 代理解包后重新验证内层地址，拒绝凭据、片段及控制字符，避免绕过外层规则。已用失败回归证明原合并版本会接纳内层凭据/片段。
4. 个人页的回顶监听不能只放在 `late final` 初始化表达式中等待首次读取；改为 `initState` 绑定。手机与平板都验证实际滚动后能回顶。
5. 长视频手机保留上游通铺媒体，平板保留内容边距；稳定布局槽位支持真实竖屏比例。曾出现 4 项黄金图差异，修正媒体宽度及零圆角裁剪后与上游基准一致。本轮继承上游的黄金图更新，没有重新生成黄金图来接受差异。
6. 首页快速入口原先只更新 LibraryState 中的片目，当前播放器仍使用旧 widget 片目，可能把多集剧显示成单集。增加已解析片目状态，在解析失败时也保留已经取得的统一集数和线路；回归先复现缺失“共 8 集”，修复后验证详情复用。
7. 上游详情的沉浸系统条仅适合顶部大图。平板分栏顶部为浅色正文背景，直接套用会得到白底白图标；根据窗口切换到主题系统条，保持同一 AnnotatedRegion/页面 State，并验证两种宽度的图标亮度。

## 验证

| 检查 | 结果 |
| --- | --- |
| Flutter 全量 | PASS，522 项，包含免登录、图片重试、平板、短剧锚点/连播、跨线路、房间交接与视觉回归 |
| 窗口/字体矩阵 | PASS，135 个组合，无框架渲染错误；包含 390/600/853/1280/480dp 宽度及 1/1.5/2 倍字体 |
| Flutter analyze | PASS，No issues found |
| API typecheck / build | PASS |
| API 单元/本机 WS 测试 | PASS，31 项；包含落盘失败、检查点、恢复、清理和关闭竞争 |
| 公开协议测试 | PASS，6 项；Provider/旧 URL 兼容与额外私密字段拒绝 |
| 结构、JSON、引用、UTF-8/LF | PASS；旧文件仅恢复为 Git HEAD 已有的 LF 字节，内容与 Git 差异不变 |
| 冲突标记与差异范围 | 全库检查；后端/契约/上游黄金图保持与此次远端目标一致 |
| Android Profile 正常入口 | PASS，`lib/main.dart` 正常包已构建并安装，已比对设备与本地 APK SHA-256；访客入口与在线片库 |
| 真机视频/键盘/全屏/PIP | 用户确认暂时无法解锁，按要求延期；本轮不引用前一轮成功结果冒充合并后验收 |

本轮新增确定性回归位于 `apps/mobile/test/upstream_merge_regression_test.dart`。对初始化原生播放器失败的 widget 测试，使用无原生错误的受控 presentation 专门验证进度控件；真实播放器行为仍由独立 Android 集成入口负责。

真机本轮尝试遇到息屏/系统 Keyguard，`mIsShowing=true`、`mInputRestricted=true`，窗口焦点停留在系统锁屏层；LiveTest 等待帧导致超时或被主动结束。原始日志已保留，不能判定为代码通过。执行器已增加锁屏前置检查、供电常亮的保存/恢复、首帧前的稳定根节点及阶段等待超时；无需也不读取用户密码。

机器可读记录及 APK 指纹见 [结果 JSON](performance/20261029-upstream-merge-results.json)。原始日志、失败黄金图和本轮矩阵位于 `.local/upstream-integration-20261029/`。历史性能报告仍属于合并前版本，本轮没有据此宣称内存或加载速度进一步提升。

## 文件、回滚与边界

| 文件区域 | 用途与影响 | 回退来源 |
| --- | --- | --- |
| `design/{bottom_navigation,adaptive_watch_layout}.dart` | 侧栏/GPU 策略、竖屏比例、手机与平板媒体边距 | 本地检查点 `5390ba4` |
| `features/catalog/{artwork_request,category_discovery,detail_page,profile_page}.dart` | 图片策略、密度、线路/骨架、访客与回顶整合 | 本地检查点；上游版本可单独对照 |
| `features/experience/{experience_player,short_feed}.dart` | 快速入口/同看交接与稳定平板布局整合 | 本地检查点；上游版本可单独对照 |
| `features/playback/playback_session.dart`、`catalog/providers/whisklet_provider.dart` | 修复远端已提交的冲突残留并合并状态/缓存契约 | 原基线与远端父提交 |
| `test/{catalog_data,provider_artwork,playback_notifications,upstream_merge_regression}_test.dart` 与重建基准 | 保留两侧覆盖并证明交叉修复 | 本地检查点；新增文件可单独移除 |
| 原生布局测试、执行器和 README | 阻止锁屏造成无意义长时间挂起，恢复设备设置 | 本地检查点 |
| `apps/api`、`packages/contracts`、其他上游页面/测试/黄金图 | 完整接收上游功能与回归 | 通过合并提交追溯，避免直接覆盖已工作的客户端 |

没有修改 SDK/依赖版本、全局控制面或 Playra 工作区；没有清除应用数据、登录账户、发送消息、创建真实房间或操作业务数据库。没有运行独立 MySQL/双真机联调，相关数据库回归不能用本机模拟测试替代。

回滚优先对照合并提交与两个父版本。原始 `main` 与 45 文件快照仍可恢复合并前状态；不得直接丢弃检查点中的原有优化。APK、夹具和原图留在忽略目录，不进入合并提交。

- DONE：抓取/分析、原始工作保护、文本与语义冲突处理、客户端/服务端/契约回归、矩阵、静态检查与合并记录。
- NEXT：按用户要求延期合并后真机完整运行，设备手动解锁后复测。
- NEXT（可选）：独立 MySQL 与双设备同看、真实系统分屏、长时间/4K 播放及合并后专门性能对照。
