# 同源数据渲染与短剧播放优化

## 原则与范围

沿用 Duoscene 原首页、分类卡片、搜索、详情、收藏、历史和设计系统。追剧喵仅用于核对同源数据与交互事实，不复制其粉色界面。用户单独批准短剧顶部仅搜索、底部信息优化。后端仍负责账户与通讯；片源协议、筛选、图片与播放地址处理留在前端。

本轮优先完成同 Wi-Fi 登录，见 [局域网调试说明](lan-development-20261022.zh.md)。没有提交、推送或运行新的云端构建。

## 实测根因

### 图片

检查 84 条历史样本，8 条 HTTP 记录对应 7 个独立 URL，被原先 HTTPS-only 数据转换直接丢弃。相同路径的 `m.ykimg.com`、`pic7.iqiyipic.com` 图片实测可通过 HTTPS 获取 JPEG，因此仅对这两个精确主机升级，不放开任意 HTTP。

《小城良方》的 `img2.doubanio.com` 海报：默认 Dart 请求返回 403 HTML，仅改浏览器 User-Agent 返回 418；浏览器 User-Agent 加 `Referer: https://movie.douban.com/` 返回 200 JPEG。现在仅对该精确 HTTPS 主机的标准端口应用这两个公开请求头，不携带账号 Authorization、Cookie、token 或 SDK 头。`.image`、无扩展名和 JPEG MIME 实际 PNG 不是已证明的解码失败根因，不按扩展名盲目丢图。

最终普通 Profile 真机检查又发现《无所不能》使用 `img1.doubanio.com`。该精确 URL 无站点头返回 418/13 B，加相同公开头返回 200 JPEG/19,285 B；补入同样的隔离加载规则，仅扩展到精确 img1 与 img2，不放开任意子域，先有失败回归再修复。

原始探测限流、限时、限体积，证据位于忽略目录 `.local/rendering-refinement/image-probe/`。图片服务器真实下架、限流、过期签名或网络故障仍可能显示原占位图；不伪造封面，不绕过证书校验。

真机进一步复现：同样的 URL/请求头，`HttpClient.headers.set` 返回 200 并完整解码出 270×404；Flutter `NetworkImage` 返回 403。当前 Flutter 源码使用 `headers.add`，会把自定义 UA 追加到默认值。因此对带站点公开头的图片使用独立 `ArtworkImage`（IOClient 的 set 语义），保持 Flutter 图片缓存与缩略解码，限制 12 秒/4 MiB 并释放请求资源；普通图片仍走原网络图片路径。失败封面保持原尺寸，提供手动重试，避免无限自动重试。同时固定“我的”收藏预览的原三列槽位，避免只有一条真实收藏时被 Expanded 拉成巨幅图片。

### 分类与筛选

原分类列表通常只返回 `vod_id/vod_name/vod_pic/type_id/vod_remarks` 五个字段，没有题材、地区、年份和片长。对这些列表再做本地题材/时长筛选，会误删有效片目；只筛当前已加载的一页也不等于全库筛选。

串行实测确认 `video_list` 支持 `class/area/lang/year`，选项来自 `nav.type_extend`。默认电影 3309 页，喜剧 678 页，美国 905 页，2026 年 142 页，英语 1072 页，喜剧+2026 年 18 页。数量是该次服务端快照，不保证以后不变，也不保证源站元数据正确。

真机追剧喵选择喜剧+2026 后前六条为：北狮南虎闯江湖、生命的舞动、冒牌音乐剧、水疗周末、假日达阵：熊队爱情故事、偷天父子兵；SDK 请求返回完全相同的顺序。因此本轮修正先前对筛选能力的过度保守判断：是 Duoscene 客户端白名单没有接入这些参数，不是服务端完全没有筛选。

`by=hits`、`sort=hits/score`、`order=hits/score` 均返回与默认相同的数据，不能冒充已经接入最热/好评。现仅提供源站默认和明确标注的“本页片名”；未提供有真实依据的片长筛选。筛选变更重置到第一页，用请求代次隔离迟到结果和异常；继续加载沿用同一查询。显示“已载 N 部”，不把当前页数目当全库总数。

### 短剧

首部短剧 `600318` 详情主线 `BBA` 共 40 集，直连备用 `lzm3u8` 仅 1 条。原来优先直连，导致页面显示共 1 集、无法按真实分集浏览。现优先分集线路，提供换源，切换线路时按其真实集数限制页码。

短剧嵌套通用播放器的底部 SafeArea 重复消费玻璃底栏 inset，造成底栏上方白色空板；现仅在短剧嵌入处移除内层 bottom padding，信息仍按外层原始 inset 避让导航。标题两行、集数独立显示、题材单行省略、简介两行，避免长题材挤掉集数。顶部只保留搜索。

## 开源播放器选型

| 项目 | 定位、许可证 | 本项目结论 |
| --- | --- | --- |
| [media-kit](https://github.com/media-kit/media-kit) | Flutter 媒体内核与 Video，自定义控件，MIT | 已集成；继续复用，避免重复播放器和生命周期所有权 |
| [video-pool](https://github.com/abdullahtas0/video-pool) | 短视频池、可见性和 MediaKitAdapter，MIT | 可作为后续有界池 POC；源 manifest 0.6.1 与 README 示例版本不同，还会引入 video_player；小体量项目不可直接当成熟度保证 |
| [better_player_plus](https://github.com/SunnatilloShavkatov/better_player_plus) | 原生播放器 UI、HLS/DASH、缓存等，Apache-2.0 | 可独立评估，但替换现有 Playra 控制器、音频会话、截图与同看同步成本较大；不能照旧 README 的依赖版本直接替换 |
| [Chewie](https://github.com/fluttercommunity/chewie) | video_player 的 UI 包装，MIT | 不是短视频调度器，也不能自动修复底层解码错误 |
| [Media3 shortform demo](https://github.com/androidx/media/tree/release/demos/shortform) | Android 原生短视频示例，Apache-2.0 | Android-only 方案的强参考，需要 Flutter 桥接，不是现有 Flutter 的即插即用依赖 |

[Media3 预加载官方文档](https://developer.android.com/media/media3/exoplayer/preloading-media/preloadmanager/concepts) 强调按优先级管理预加载和释放资源，不能把多播放器无限预加载当优化。旧 Honor 设备应先测内存、耗电、首帧与连续切集，再扩大池大小。media-kit 官方也提示 Debug 和 Release 性能差异，不能用一个 Debug APK 的卡顿直接判定解码内核不行。

本轮选择：保留现有 media-kit/PlaybackSession 与音频/后台生命周期，通过短剧专用 Video 表面和播放/暂停、进度、缓冲、失败重试控件替代长视频复杂手势和运输栏；纵向手势只归 PageView。进度拖动带媒体代次检查，防止切集后 seek 落到另一集。没有宣称集成 video-pool、替换 Media3 或实现离线缓存。

## 验证与回滚

重点测试覆盖海报安全策略、真实筛选编码、五字段数据渲染、旧响应隔离、分集线路选择、320/390 宽度与双倍字体避让。保留原 36 张视觉基准，仅短剧相关 02/07/10 页面建立单独批准变体，其余 30 张继续逐像素比对。

新工作开始前快照在 `.local/rendering-refinement/before/`；LAN 变更前快照在 `lan-before/`。原样式安装包保留，不修改其历史报告或基准图片。此文中的接口和项目状态为 2026-10-22 的实测/源码快照，不代替后续兼容性和性能测试。

真机原始下载与完整解码：img2 为 200 JPEG、270×404；m.ykimg 为 200 JPEG、960×1280；独立 ArtworkImage 在原生环境成功出图，原 NetworkImage 同时复现 403。实际“我的”页确认单个收藏保持原三列槽位且海报显示。电影喜剧+2026 真机前六项与同源参考一致。短剧主线显示共 40 集，首集实际 2:52、媒体状态 playing 且进度推进，离开后释放媒体；不宣称所有线路均稳定。

原生 integration_test 安装流程导致测试设备登录/偏好状态被重置，已用既有 XML 快照与最近片库证明恢复 1 条收藏、5 条记录及对应元数据，并重新登录 test123；随后所有性能/交付包安装改为显式 adb install -r，实测保留片库。没有重建后端账号或清空数据库。
