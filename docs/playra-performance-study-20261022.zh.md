# Playra 对照研究：Duoscene 性能、播放链路与包体积

## 结论先行

不是“把 Playra 播放器再搬一次”就能解决卡顿。Duoscene 已迁入同一提交的播放器核心，移植清单中 26 个源文件的原始 SHA-256 与当前 Playra 逐一匹配。当前主要差异在外层业务编排、图片缓存、UI 通知范围、构建模式和包结构，而不是有证据证明解码引擎较差。

本轮保持原有视觉设计；不修改 Playra 工作树，不移除同看/语音/WebRTC、解码格式、字体或正在使用的图片。性能优化按独立 OpenSpec 切片执行，不能将包变小冒充已经消除页面卡顿。

## 1. 固定参考与测量边界

- Playra：`C:/Users/haige/Desktop/Playra`，HEAD `02fcd555fbf2fa049caf9c20377b2c47638a165c`，版本 2.3.8+20308，Flutter 3.47.6。已有脏子模块与 `recipes.json` 保持不动。
- Duoscene：`C:/Users/haige/Desktop/Duoscene`，保留当前 SDK/原样式恢复/图片/筛选/短剧/LAN 的未提交修改，不以 `git reset` 清理。
- 当前连接设备 Honor LLD-AL20，Android 9、ARM64；Playra 历史报告用 Xiaomi/Android 15，其 618 ms 等数据不能拿来当当前设备目标或收益。
- 当前实际交付一直是 Debug/JIT。Flutter 官方要求在物理设备用 Profile 判断最终接近 Release 的性能，不能只看 Debug 的 skipped frames 或 Flutter 宿主 `gfxinfo` 就宣称真实 FPS。见 [官方性能测量](https://docs.flutter.dev/perf/ui-performance)。
- `am start -W` 仅衡量 Activity 显示，不是登录恢复、片库、图片和媒体首帧全部就绪。`FrameTiming` 的 build/raster 超过 16.667 ms 是 60 Hz 单阶段参考超预算，不等于实际丢帧率。回调批量送达时间也不是原始绘制时刻，见 [FrameTiming 回调文档](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)。

## 2. 两个项目的真实执行链

### Playra

```text
main → 平台/Hive/存储/WebView/网络初始化 → InitPage → 默认页面
发现页 → 首频道 + 内容首屏 → 首屏提交 → 后台资料补全/其他频道串行预热
详情 → SDK 目录缓存/同键请求合并 → 线路准备与排名 → 短期 prepared
     → 身份/有效期/选集匹配 → 串行安装媒体 → 实际解码/首帧 → 观看记录
```

这不是零开销框架。它也有启动前等待、多个数据源、较复杂的依赖、Python/WebView 和较大的媒体缓存。应该移植解决具体问题的模块，不应复制整个启动链。

### Duoscene

```text
main（不等待网络）→ DuosceneApp → 恢复主题 + 安全存储/登录
  → AppShell/LibraryState → WatchHome/CatalogData
  → 推荐与 nav → 各分类首分页 → Whisklet 加解密/模型 → 海报解码

详情页 load → provider.detail
点击播放/切集 → provider.resolve → 再次 provider.detail → 解析 → PlaybackSource
  → PlayerPage.prepare/音频服务 → PlaybackSession 串行 load
  → 已移植 Playra controller → media-kit/固定 libmpv → Video 纹理
```

关键事实：每次 `resolve` 都重新取详情，详情页已经有目录时仍然发生第二次详情往返；短剧切集也重复这一段。UI 取消/代次检查防止旧结果回写，但多数已发出的协议请求仍跑到完成或 12 秒超时，不能把“忽略旧结果”当作真正取消了工作。

## 3. 已经借鉴的部分：不要重复重写

| 能力 | Playra | Duoscene 当前实际情况 |
| --- | --- | --- |
| 原生播放器所有权、串行加载、过时代次 | `lib/pages/player/controller/player_playback_controller.dart` | 已移植；上层 `PlaybackSession` 再做加载/控制串行 |
| 解码、HLS、SurfaceTexture、超分辨率、后台预取暂停 | 同上 | 已存在；两边均 `enableAndroidSurfaceProducer:false` 与 Skia 匹配；超分默认值 1 表示关闭，不是默认运行 Anime4K |
| 拖动/倍速/缓冲/截图/播放器设置 | player controllers/widgets | 已移植；短剧已独立控件，不能直接搬长视频全套手势 |
| 缓存已访问 Tab、保留 Element/滚动/输入、可见性停工 | `lib/presentation/shared/mobile_tab_view.dart` | `design/motion.dart` 已借鉴，并增加目标页预布局和 RepaintBoundary |
| 搜索去抖、分页、旧结果隔离 | 搜索会话/内容控制器 | 已存在基本机制；需检查真实查询与 UI 更新范围，不应再叠一个互相竞争的防抖 |
| 单 ARM64 | Android ABI 过滤 | 当前 APK 实物已只有 ARM64，不能再把三架构裁剪算作新收益 |

## 4. 值得集成的模块与落点

### P0：构建和数据关键路径

1. **Playra 的精确打包输出清理。** 借鉴 `docs/verification/android-performance-20261017.zh.md` 的 Zipflinger 排查方式，已实测完成首个减包切片，见第 6 节。只清 `packageDebug/Profile` 输出，不全量 clean，不手动改 ZIP 或重签。
2. **明确 Debug/Profile/Release。** `tool/build-android.ps1` 的显式模式值得复用。Duoscene 新 LAN 入口支持 Profile，HTTP 仅在显式 Debug/Profile 私网测量配置下允许；Release 依旧要求 HTTPS。正式发布签名也不能用“测试证书”混称。
3. **首屏优先与渐进发布。** 参考 `lib/presentation/modern/pages/discover_page.dart:52`：优先首频道与首屏，后续工作延后/限流。当前 `CatalogData` 已修复 nav 阻塞推荐，但其他分类仍串行预热；下一片应让可见分类抢占后台预热预算，并对同键请求合并，不简单改成所有请求并发。
4. **目录缓存和 pending 合并。** 参考 `lib/services/source/sdk_playback_coordinator.dart:103`。将 Whisklet 已取到的详情/线路目录复用到紧接着的播放，失败不缓存、容量/TTL 有界、退出可取消。不能只以影片标题为 key；至少包含 provider/content/线路身份和刷新策略。先测额外一次详情 RTT，再给出实际首帧节省。

### P1：图片、状态与滚动

5. **尺寸感知解码 + 压缩字节缓存。** 参考 `lib/bean/card/network_img_layer.dart:72`、`lib/utils/image_extension.dart:3` 与 `lib/services/network/cached_bytes_image_provider.dart:8`。当前普通海报统一 480 像素解码，短剧 `cacheWidth:null` 仍回落 480；横幅、缩略图、竖屏背景不应共享同一固定策略。需要以布局尺寸×DPR、fit 与原图比例选择解码轴，保留现有外观与清晰度。
6. **图片磁盘缓存与坏图收口。** Playra 原生走 CachedNetworkImageProvider，当前主要只有 Flutter 内存图片缓存；冷启/跨场景会再取图。可整合有界字节缓存，但缓存 key 必须考虑 URL 查询与站点请求头，坏图/非图片 200 必须失效；不能丢失本轮已修复的豆瓣 UA/set 语义，也不能将不同 token 内容混在一个去 query 的 key 下。
7. **局部状态订阅。** Playra 的 MobX/Observer 分区与主页局部 listenable 可参考。当前 `PlaybackSession` 每 200 ms 无条件通知，`PlayerPage` 的大 AnimatedBuilder 会再执行 presentation；短剧叠层和长视频业务组合都有额外重建。应把 position/buffer 与媒体身份/页面数据分流，静态树做 child 缓存，暂停且状态未变不空转。Playra 也有 200 ms 的业务轮询，不能简单把“所有地方改成 1 秒”当正确修复。
8. **GPU 合成要测再动。** 现玻璃底栏 blur sigma 14、视频纹理、大图渐变和路由过渡可能叠加 raster 成本，这是待 profile 证实的候选，不是已确认根因。先比较 build/raster 和层树，再决定隔离重绘/缩小采样区域；不能擅自去掉玻璃效果或换视觉设计。

### P1：播放链路与交互

9. **PreparedPlayback freshness。** 可借鉴 `lib/services/source/prepared_playback.dart:2` 与 `lib/pages/video/prepared_online_playback.dart:5` 的 30 秒上限、到期前 3 秒拒绝、provider/content/line/episode/quality 全身份匹配。仅持有 URL 不代表起播成功；真实首帧后才记录线路成功/更新历史，不把有时效的媒体地址长期持久化。
10. **有限自动换线与真实成功评分。** `SdkPlaybackCoordinator.play` 最多尝试 3 条，并匹配同一集、分类错误、记录最近 8 次样本。可按 Whisklet 契约重新适配，不照搬 Lumina/Mio token、广告状态、1080p 门槛或全线路预扫描。短剧一条直连“全集”和 40 集主线不能按数字随便互跳。
11. **恢复/切集/暂停意图。** 参考 `sdk_playback_resume.dart`、`playback_start_position.dart`。要重点测进入短剧但未播放是否覆盖旧进度、快速换集时旧 seek 落到新集、手动暂停后返回是否擅自播放、换源后的 episode 身份。不能只检查按钮能点。
12. **请求取消与状态机。** 将详情/解析中、媒体装载中、首帧等待、正在播放、失败可重试分开；退出时取消后台解析/预载，旧请求不能安装媒体。播放准备与真正的观看记录提交解耦，按钮等待状态和失败恢复应有明确终点。

## 5. 不可直接搬来的东西

- Playra 的全局 `GStorage`、Modular、Hive、Bangumi/Kazumi、多 SDK、Python/WebView 启动链：协议与产品不同，会增加依赖、包体和首屏等待。
- Playra 全局 `usesCleartextTraffic=true`：不符合本项目认证隔离与精确域名策略，不复制。
- 默认 1500 MiB 媒体缓冲上限：当前移植版也有此配置，**不是启动立即分配 1.5 GiB**。它属于长视频/网络策略，短剧应按真机缓冲、水位、磁盘与内存测量重新设预算，不直接加大或一刀切成极小值。
- `useLegacyPackaging=true` 的 native 压缩：Playra 为只读 nativeLibraryDir 加载其 SDK 引擎而选用。当前未压缩 JNI 可直接 mmap；压缩可减下载 APK，但会改变安装空间/解压/加载方式，不能无回归验证照抄。
- 切换 Impeller 或升级 media-kit 原生 fork：当前 SurfaceTexture/Skia 是明确配套；先保持已验收链路，不能用“新引擎更快”替代旧 Honor 上的兼容性证据。
- 复制完整 UI/导航和字体子集：会破坏原风格；动态中文片名不能按静态 UI 字符集粗暴裁掉字体字形。

Playra 主项目为 GPL-3.0，已有 `third_party/playra-player/NOTICE.md` 与许可证。继续复用应保留来源、补丁与许可证；media-kit wrapper 的 MIT 不代表其中 mpv/FFmpeg、shader 或 Playra 业务代码都变成 MIT。

## 6. APK 实物与首个已完成切片

原 Duoscene ARM64 Debug：199,804,544 B（190.55 MiB）。ZIP 内部有 4 处 >64 KiB 的空洞，最大单处 30,420,588 B，总结构开销 31,130,693 B。它不是又打入了三种 ABI，也不是“片源 SDK 多了 30 MB”。

窄范围 `:app:cleanPackageDebug` 后重建：168,856,513 B（161.03 MiB），减少 **30,948,031 B（29.51 MiB，15.49%）**，大空洞为 0，结构开销降为 182,714 B。720 条目中原生库、图片、字体、DEX 等全部 SHA-256 相同；仅 Dart kernel 重建载荷变化（压缩长度变化 52 B），不宣称整个 ZIP 逐字节相同。

| 原包压缩/存储项 | 字节 | 分析 |
| --- | ---: | --- |
| native 合计 | 88,583,072 | 含 Debug Flutter 38,828,704、mpv 21,727,928、Vulkan validation 15,240,080、WebRTC 12,287,312 等；不可把后两者都当无用业务依赖 |
| Debug Dart snapshot/kernel | 36,394,350 | 解压后 109,023,800；Debug/JIT 非生产体积 |
| DEX | 19,501,824 | Debug 未按 Release 的 R8/资源收缩结果衡量 |
| 图片 | 19,872,087 | 按实物可见，大图是后续候选；需做动态资源引用审计后才能排除或缩图 |
| 字体 | 3,585,321 | 其中有中文展示字体，不盲删字形 |

Playra 现存 Release APK 实物 60,559,627 B（57.75 MiB），单 ARM64、无大空洞。它与 Duoscene Debug 不同模式、不同业务、不同 JNI 压缩策略，不能直接减出“业务代码优化 69%”。正式大小应看实际 Release-like APK/AAB，并区分 APK、安装数据、PSS 和商店下载量，见 [官方体积说明](https://docs.flutter.dev/perf/app-size)。

构建中也复现了两个门槛：`--no-pub` 切到 Release 时旧生成插件注册表仍含 integration_test；交给 Flutter 正常生成后消失。随后 Release lint 要求网络配置显式 `includeSubdomains`，现设为 false，既通过精确域名语义也不扩大明文范围。没有手改生成注册表，也没有关闭 lint/R8。

## 7. 验收路径与后续顺序

先交付压紧结构与可用 LAN Profile 测量入口，再按第 4 节 P0→P1 单片推进。每片必须保留原样式基准、真实接口、收藏历史与账号隔离测试，并以相同设备/模式/操作对照；UI 部分至少记录 build/raster p50/p95/p99/最大与原始样本，播放至少记录解析、安装、首帧和推进，不只记录 ready。

性能采集是显式 `PERF_CAPTURE` 的 40 秒开发测量，不自动启用，不采集账号、凭据或片目内容，Release 不注册回调。原始证据在忽略的 `.local/performance-study/`，不能用一次样本宣称消除全部卡顿。后续完成状态以 OpenSpec tasks 与最终验收小节为准。

## 8. 当前真机基线与证据分类

同一 Honor、同一业务源码、LAN 测试账号，分别安装 Debug/Profile 性能包，保留数据。每轮启动后做 6 次首页上滑与相同 6 次 Tab 点击，记录前 40 秒。两轮为顺序单样本，网络、图片加载、安装后的系统缓存和动作相对 Dart 启动时间不完全相同，不作为统计显著性的长期收益。

| 指标 | Debug/JIT | Profile/AOT |
| --- | ---: | ---: |
| 原始帧样本数 | 201 | 454 |
| UI build p50 / p95 | 12.687 / 218.914 ms | 2.364 / 12.730 ms |
| UI build p99 / 最大 | 846.039 / 2098.464 ms | 46.822 / 83.500 ms |
| raster p50 / p95 | 20.984 / 61.014 ms | 18.444 / 35.054 ms |
| raster p99 / 最大 | 91.564 / 363.561 ms | 64.255 / 341.662 ms |
| build >16.667 ms 样本 | 64 | 10 |
| raster >16.667 ms 样本 | 143 | 267 |
| 测量后解码图片缓存 | 20,317,108 B | 20,317,108 B |
| 测量后进程 PSS | 349,253 KiB | 155,739 KiB |

Debug 的 `am start -W` 返回 **Status: timeout / WaitTime 10805 ms**，无有效 TotalTime，不能写成“启动 10805 ms”；Profile 返回 ok、TotalTime 2829 ms，这仍不是片库/图片全部就绪。两轮电池温度分别 30.0/31.0°C，未声称获取了 Android 9 上的精确 thermal throttling 状态。

**结论：** UI/JIT 成本显著，交付测试应先换 AOT Profile；但 Profile 的 raster p95 35.054 ms、最大 341.662 ms 仍超预算，GPU/绘制端问题没有解决。两个样本数不同，不能用 143→267 说掉帧变多，也不能以 build p95 的改善宣称用户全部交互已流畅。

源码还定位到：首页纵向分类是一个 `CatalogSections` Column，四条横向 ListView 会一起布局；横向卡片本身是惰性的，不等于 84 张全都同时渲染。应优先研究纵向分段惰性构建与首屏图片队列。`DSIllustration` 已有按尺寸分桶和 RepaintBoundary，`Forest` 只是纯色容器；不能把它们错判为每帧解码的全屏大背景。玻璃模糊、纹理、图片上传和路由合成谁占主导，仍需要下一片 GPU trace/受控实验，不擅自降低原视觉质量。

## 9. 正式模式体积探针

已用正常 `lib/main.dart`、单 ARM64、Release AOT/R8/资源收缩构建并运行 `--analyze-size`：**80,692,477 B（76.95 MiB）**，720 条目 Debug 对照已另留；Release 结构大空洞为 0。组成：native 55,471,576 B、图片 19,848,168 B、字体 2,818,355 B、DEX 1,868,896 B、其余与结构 685,482 B。

此探针使用 `https://example.invalid` 占位配置，只为保留正常认证/页面代码分支并分析体积，**未安装、未当交付包，且没有发布签名**（apksigner 明确 DOES NOT VERIFY）。正常 LAN Profile 包另行构建并验收，不能把该 76.95 MiB 文件当可用生产 APK。与旧 190.55 MiB Debug 的差异同时包含构建模式和 ZIP 结构，不能全算业务优化；APK 大小不等于商店下载量、安装占用或 PSS。

初次连续多模式构建还触发了电脑端 Gradle 512 MiB Metaspace 上限；该 daemon 退出后，新 daemon 重试 Profile 构建通过。它是构建宿主的问题，不是手机进程内存数据，也没有照搬 Playra 的 4 GiB 堆设置。

## 10. 播放链与交付边界补充

普通 Profile 真机首集曾出现解析失败，手动重试后主线 2:52 的媒体加载、播放状态和进度推进正常。这说明“加载慢/偶发失败”还有源端参数完整性与解析等待因素，不应归给 UI 或解码。原 SDK `sdk/python/whisklet/client.py:218` 同样以 family 满长判断响应头部截断，并多次重发；Duoscene 目前最多 8 次、每次请求有 12 秒超时，但缺少页面级统一解析预算/取消信号。完整性规则不能为追求快而跳过；下一片应先做有界总预算、同键合并、正确的目录/prepared 复用、同集匹配与错误分类。

当前数值基线取于最后补入 img1 海报规则之前；两种构建模式之间业务源码相同。最终交付只增加该实测图源规则，不将两轮基线冒充最终包所有网络/交互已全面验收。后续详尽的滑动换集、弱网、长时间播放、快速往返和同步房间性能仍需独立测试。

### 本轮代码与影响

- `scripts/build-lan-apk.ps1`：显式 Debug/Profile、精确 package 输出清理、模式正确的插件生成、独立 perf 产物。
- `apps/mobile/lib/main.dart`、`core/performance_capture.dart`、`test/performance_capture_test.dart`：默认关闭的开发帧采集与统计回归；不改页面布局，不记录账号内容。
- `apps/mobile/lib/app/duoscene_app.dart` 与 Android Gradle/网络 XML：明确 Profile LAN 测量能力、精确私网主机与 includeSubdomains=false；Release 认证 HTTPS 策略不变。
- `catalog/artwork_request.dart` 与海报测试：只补入实测 img1 站点规则，保留隔离请求头与安全边界。
- 文档及两份 OpenSpec：把当前证据、未完成项和后续模块记录下来，没有更换原 UI 或再次引入播放器内核。

回滚：本性能切片的源码/设备偏好快照在 `.local/performance-study/before/`，原减包对照 APK 在 `before-size-probe.apk`；本轮前的样式包仍在 `output/android/duoscene-style-restored-arm64-debug.apk`。回滚文件应按切片恢复，不能覆盖别人的未提交改动；不要卸载 App 来切换同签名模式。

## 11. 本次研究与第一切片交付核验

当前结论为 **PARTIAL：研究与构建切片通过，整体验收尚未完成**。内容/播放编排和 GPU 绘制优化尚未落地，不能把本次 Debug→Profile 模式对照当作这些业务改动的收益。OpenSpec 不归档，后续项明确标为 NEXT。

- 完整 Flutter 测试 **379 项通过**；analyze 零问题。保留原 36 张 PNG 哈希，30 张原基准与 6 张独立短剧批准变体均通过；136 个源文件/脚本/报告 UTF-8 无 BOM、无替换字符且 LF 检查通过，`git diff --check` 通过。
- 最终普通 Profile APK：`output/android/duoscene-lan-arm64-profile.apk`，**104,820,026 B（99.96 MiB）**，SHA-256 `6f335a4a00412fb6276d53ed06c00879466537c89164a0ed2113c0014d155017`。ZIP CRC、单 ARM64、AOT libapp.so 检查通过；设备安装 APK 的 SHA-256 完全一致。
- apksigner 验证通过；调试证书 SHA-256 `fa4ec0e036ba5760beaab14bed70e1f6d625462317b8a42d828ac7c3797927fe`。这是可用的 LAN 性能测试包，**不是正式发布签名的 Release**；Profile manifest 仍可调试，不能用于生产安全交付。
- 覆盖安装后原 **1 条收藏、5 条历史及快照片目 ID** 与本性能切片前证明逐字段完全一致；没有再次卸载/清数据。普通包元数据 `performanceCapture=false`，启动超过采集窗口后外部目录无采集文件，未把测试统计带入默认运行。
- API `0.0.0.0:3000`、数据库 `127.0.0.1:33307`，Wi-Fi 地址 `/health/ready` 返回 ready；无 ADB 3000 反向代理。test123 已在真机保持登录；第二台手机未连接，不能写成已完成多设备验收。
- 最终电影页原生截图确认“无所不能”的 img1 封面出图；部分其他片目仍可能受源站/网络影响，本次未把单图成功写成全库封面可用率 100%。首集播放与筛选的证据见渲染报告，连续滑动换集及房间压力回归仍是 NEXT。
- Playra 最终工作树仍只有原有脏子模块与 `recipes.json`，没有修改参考项目。此处记录性能验收时点；后续整理、提交及推送以 [最终提交说明](git-delivery-20261022.zh.md) 与 Git 历史为准。

复核证据：`.local/performance-study/delivery-proof.json`、`source-verification.json`、`flutter-tests-delivery.log`；最终原生截图 `.local/provider-probe/profile-delivery-final-home.png`、`profile-delivery-final-movie.png`。这些本机证据不包含鉴权 token；完整设备偏好备份另行私有保存，不上传。
