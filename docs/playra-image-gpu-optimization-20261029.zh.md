# 图片可靠性、解码与大屏绘制优化（2026-10-29）

本轮起点为 `435fea310b21dfe7c5279ea88167a6a247ec0461`。构建指纹与逐轮数字见 [结果 JSON](performance/20261029-image-gpu-results.json)。

## 图片为什么会变成白卡

截图中的“彩虹镇的甜甜魔法屋”和“你好八斤”来自标准 HTTP 图片地址。旧 `ArtworkRequest` 仅允许少量精确域名升级到 HTTPS，其余 HTTP 地址被过滤成空值，图片请求根本没有发出。对原路径改用 HTTPS 后，两张图片均返回 HTTP 200，JPEG 原始尺寸均为 579×772；正常应用入口的 ADB 截图也已确认两张封面恢复。

修复前的只读探针读取 63 条记录：57 条有效，6 条被地址规则拒绝，6 条 HTTPS 候选全部有效。这 6 条包含重复片目，不能当作 6 个独立故障。修复后的新一轮 63 条记录全部返回 200 且能解析图片尺寸。在线目录会变化，这两个批次不是网络延迟的受控 A/B。

## 自动处理规则与加载状态

- 标准 HTTP 80 端口自动转换到 HTTPS 443；`//host/path` 自动补 HTTPS，后续普通 CDN 主机不再需要手工加入升级名单。
- 保留完整路径和查询参数，避免破坏签名；已有 HTTPS 地址保持有效。拒绝用户信息、片段、控制字符与无法推断 TLS 入口的非标准 HTTP 端口。
- 豆瓣公开请求头仍只用于精确的 `img1/img2.doubanio.com:443`，不会扩散到相似域名。
- 首帧未到时显示静态“加载封面”占位，不为每张卡片创建持续动画或淡入图层；首帧到达立即显示。
- 瞬时错误在 400ms 后最多自动重试一次；永久 4xx（408、429 除外）直接显示“点按重试”。URL/片目变化或组件销毁会取消旧重试。
- 没有图源的卡片显示“暂无封面”，和真正的加载失败区分。

自动规范化不能修复上游删除、403、防盗链规则变化、无 HTTPS 服务、无效证书或离线；本轮没有启用全局明文回退或跳过证书校验。普通 `NetworkImage` 的传输实现沿用原代码；不能把专用豆瓣加载器的超时与大小限制描述成全局能力。

加载速度的口径：原先这两张封面在地址阶段被拒绝，无法形成“加载完成”时间；修复后最终主机探针请求分别约 211ms、249ms，真机也显示成功。整个最终样本的请求 p50/p95 约 298ms/1414ms。这些是开发机网络响应与传输耗时，不包含手机解码/绘制，不能宣称为真机首帧提速。静态占位与一次恢复改善的是等待反馈和临时失败恢复；本轮没有建立真机逐图首帧的受控速度对照。

## 对齐 Playra 的范围

只读参考 `D:/project/Playra` 的 `network_img_layer.dart` 与 `image_extension.dart`：图片按布局宽度×DPR 请求单轴解码、保持原始比例、静态占位。本项目保留原来的 480px 上限与显式 `cacheWidth` 优先级，无界布局仍回退到 480px；本地设计资源保持既有解码参数，不更新黄金图。

大屏 Skia 资源缓存上限是本项目的独立实测扩展，Playra 未配置这一项。当前 Android Manifest 明确使用 Skia。Flutter 3.47.6 引擎按物理视口面积×48 计算默认资源缓存预算；2560×3840 整屏对应约 450MiB。最终采用 Android 上限 192MiB，小屏不提高默认预算，窗口变小时跟随缩小；不支持通道时保留引擎默认行为。通道说明见 [Flutter 官方文档](https://api.flutter.dev/flutter/services/SystemChannels/skia-constant.html)。Graphics 总量还包含其他图形资源，不能全部归为这一缓存。

## 真机测试方法

设备为 TB711FU / Android 16 / ARM64，2560×3840、480dpi。采用 Profile 构建；每轮强制停止后启动，不卸载、不清应用数据。40 秒采集 Flutter build/raster FrameTiming，按相同时间点执行六次上下滚动、四次分类切换及三个底栏切换；约 43.5 秒读取 PSS、Graphics、Native Heap，并记录电量、温度、热状态与刷新率快照。

在线目录会更新，因此提供两层数据：早期在线实验供诊断；最终固定 84 条元数据的对照用于图片/GPU归因。固定场景仍运行真实 AppShell、WhiskletProvider 与协议解析，元数据响应固定 30ms，图片仍请求原有真实 HTTPS CDN，不用合成图片。两侧共享访客入口、地址修复、占位/重试与原页面绘制边界；差异仅为默认解码宽度及 Skia 缓存预算。私有测试入口通过中文响应与分类非空合同测试；每轮另校验已解码缓存大于 16MiB，避免错误页被当作性能收益。

固定场景 Activity 时间只用于完整记录，不代表正常应用的冷启动或源站加载时间。raster 是 Flutter 光栅线程耗时，不是独立硬件 GPU 时间；动态刷新率下，帧数和阈值超限次数不能换算成 FPS 或掉帧率。PSS/Graphics 是场景结束快照，不是全程峰值。

## 固定目录真机对比（优化前五轮、优化后三轮中位数）

| 指标 | 优化前 | 优化后 | 变化 |
| --- | ---: | ---: | ---: |
| 总 PSS | 617.35 MiB | 581.10 MiB | -5.87% |
| Graphics | 408.67 MiB | 369.93 MiB | -9.48% |
| 解码图片缓存 | 60.16 MiB | 53.33 MiB | -11.37% |
| build p95 | 1.40 ms | 1.35 ms | -3.23% |
| raster p95 | 9.39 ms | 9.38 ms | -0.19% |
| raster p99 | 21.54 ms | 19.15 ms | -11.08% |

PSS 逐轮范围：582.92–631.43 → 574.93–585.45 MiB；raster p95 范围：9.10–9.77 → 9.04–9.76 ms。逐轮原始摘要与动作实际时间见结果 JSON。

本场景保留 192MiB 方案：总 PSS 中位数降低约 5.9%，Graphics 降低约 9.5%，解码缓存降低约 11.4%，raster p95 基本持平。PSS 范围有少量重叠，样本来自一台设备，不把这个比例推广为所有手机或所有页面的保证，也不把 0.018ms 的差值称为绘制提速。


## 正常入口最终复测

最终安装包来自正常 `lib/main.dart`，默认访客、真实在线目录，不含固定片单替换。完整跑了四轮相同动作，通道日志确认 `bytes=201326592 applied=true`（192MiB）。PSS 中位数 568.19MiB，范围 550.67–668.14MiB；raster p95 中位数 9.30ms，范围 9.14–9.95ms；解码缓存四轮均约 52.58MiB。

首次在线轮次的 Graphics/PSS 明显更高，仍完整保留，没有剔除。在线页面内容与固定快照不同，因此不把它与固定基线拼成新的降幅；缓存预算成功回执也不代表 Graphics 总量被限制在 192MiB。正常首页已实际显示远程封面，分类/底栏切换完成，设备最终保留正常优化包。

## 撤回与排除的实验

1. 移除整页 RepaintBoundary：三轮 PSS 中位数从 631.77MiB 到 639.79MiB，raster p95 中位数从 9.050ms 到 9.847ms，未证明收益，已恢复原实现。
2. 首次固定目录包因测试 MockClient 默认 Latin1 编码无法返回中文 JSON，实际进入片库错误页，该轮已解码缓存仅约 1.9MiB。此轮明确排除，保留私有失败日志；改为 UTF-8 并通过合同检查后才重新测量。
3. 早期在线 baseline/images：解码缓存中位数约 54.67→48.00MiB，但 PSS 没有证明下降。它们与后续在线 reliable 场景的目录发生变化，不能拼接成总内存收益。
4. 128MiB 大屏预算：三轮 PSS 中位数 551.68MiB，但 raster p95 中位数 10.373ms，高于首批三轮基线的 9.472ms；没有直接采用该参数，改测 192MiB 并补充两轮基线，完整保留该试验数据。

## 免登录入口与回归范围

默认进入真实片库的本机访客模式，收藏/播放记录使用独立 `local-guest` 命名空间，不读取、轮换或清除原账户凭据。浏览、搜索与个人播放沿用现有实现；双人房间/邀请码入口在访客模式明确提示暂不可用。后端鉴权没有修改。构建增加 `--dart-define=REQUIRE_LOGIN=true` 并配置 API 可恢复原入口。

自动化验证：全量 Flutter 415 项通过，包含原有视觉/鉴权回归；静态分析无问题。新增覆盖布局/DPR/显式解码参数、自动协议处理与签名查询、临时失败重试/永久失败、组件替换/销毁、访客存储与令牌隔离，以及大屏缓存/小屏默认值/平台边界/通道缺失。

仓库结构检查仍被未修改的 `apps/mobile/docs/playra-layout-reference.md` 现有 CRLF 换行阻止（要求 LF）；该文件 Git 差异为空，本轮未扩大范围修改。修改文件单独执行 UTF-8、LF、无 BOM/替换字符检查与 `git diff --check`。

## 修改文件、影响与回滚

| 文件（相对仓库根） | 目的与影响 |
| --- | --- |
| `apps/mobile/lib/features/catalog/artwork_request.dart` | 自动规范化图片地址；精确保留已有特殊请求头边界 |
| `apps/mobile/lib/features/catalog/posters.dart` | 布局解码、静态占位、有界重试与手动恢复；不改卡片布局 |
| `apps/mobile/lib/core/rendering_budget.dart` | Android 大屏 Skia 缓存预算与视口生命周期 |
| `apps/mobile/lib/app/duoscene_app.dart` | 默认访客入口、外观恢复及预算生命周期 |
| `apps/mobile/lib/features/catalog/app_shell.dart`、`library_state.dart` | 实际访客目录与独立本机存储 |
| `apps/mobile/lib/features/catalog/home_page.dart`、`profile_page.dart` | 访客身份、房间边界与退出入口 |
| `apps/mobile/lib/features/experience/invite_pages.dart`、`settings_pages.dart` | 邀请与账户设置的访客边界 |
| `apps/mobile/test/{artwork_decode,artwork_loading,guest_entry,rendering_budget}_test.dart`、`provider_artwork_test.dart`、`app_test.dart` | 新行为与原认证路径回归 |
| `apps/mobile/test/benchmarks/artwork_live_probe.dart`、同目录 `README.md` | 显式执行的真实图片只读探针，完整地址仅写私有文件 |
| `apps/mobile/README.md`、本报告及结果 JSON | 入口说明与测试证据 |

回滚位置为本轮起点提交 `435fea310b21dfe7c5279ea88167a6a247ec0461`；仅还原本轮列出的文件即可，不需要清设备数据。新文件尚未提交或推送。私有元数据/URL、临时脚本、截图及 APK 保存在忽略目录 `.local/performance-20261029` 与 `output/android`，不进入仓库。
