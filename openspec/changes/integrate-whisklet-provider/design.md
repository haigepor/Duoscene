## Context

基线 027337f；Flutter 3.47.6 / Dart 3.13.5，http 1.6.0，固定 Playra/mpv。原片库只有静态 Film 和 search 接口。外部 SDK 是纯 Python 标准库实现，全部 17 方法走 HTTP 加密 POST；2026-10-21 已完成真实请求。原 SDK 不修改、不引入 Android Python 运行时。

## Goals / Non-Goals

**Goals:** 前端默认第一片源；推荐、远程分类/搜索分页、真实详情、线路/剧集解析、播放器与账户隔离的本机记录形成闭环；17 方法提供受约束调用接口；失败明确展示并可重试。

**Non-Goals:** 不增加后端 provider 路由、不代理视频、不上传 Duoscene token、不执行上游广告/升级/HTML/播放器任意配置；不迁移身份、房间或语音契约；不自动下载完整影片；不声称所有内容永久可播。

## Decisions

1. Dart 原生 provider + PointyCastle 4.0.0 / crypto：对照 SDK 请求向量与实测响应，AES-CBC/PKCS7 由成熟库负责。响应解码放后台 isolate；不直接移植手写 AES。
2. Provider 与 CatalogRepository 搜索兼容，新增类型化分页、详情、线路和剧集；ID 为 whisklet:<vod_id>，稳定播放身份包含 provider/影片/线路/集号，不用短效 URL 当身份。设计预览只用 DesignCatalog。
3. 包装响应必须保留“重建头部”事实；按方法验证 data，不能把 SDK 合成 code=1 当服务端已确认成功。配置/详情仅恢复已知结构，不猜测缺失的影片数据。解析字符串按已知线路完整长度校验，最多 8 次，未完整则明确失败，不拿残缺 param 播放。
4. video_list 实测忽略 limit，但返回根级 page/pagecount；按 pagecount 继续翻页，以 provider ID 去重。未实测筛选能力不伪装成远程筛选。搜索去抖和代次隔离，防旧响应覆盖新词。
5. HTTP 超时、响应体上限、结构验证、错误分类；上游密钥是协议兼容常量，不是 Duoscene 安全边界。HTML 仅纯文本展示。上游 header 白名单，不接收账户鉴权或任意 mpv 参数。平台解析器仅允许本 provider 主机的 /ajiami/ 路径；外部解析仅 HTTP(S)，媒体链接校验后交播放器。
6. 收藏/历史存元数据快照与可选线路代号，不存播放 token、解析 param、签名 CDN URL。默认优先可用直链，历史恢复优先原线路并刷新详情；旧 v1 数据兼容；未知/移除片目显示占位而非 firstWhere 崩溃。
7. Android 对固定 API IP 单独允许 HTTP，其余默认禁用明文；debug 额外允许既有本机 API。房间保持原 URL 同步能力，不宣称已经支持过期 URL 自动跨端重解析。

## Risks / Trade-offs

- HTTP / 固定协议密钥不防中间人 → 不发送账户隐私，不全局放开 HTTP，发布前建议上游 HTTPS。
- 响应随机截头且 SDK 宣称“data 永远完整”并不可靠（secret 字符串已实测截断）→ 严格结构/长度检查，失败显式报告。
- 内容、线路及签名有时效，单次成功不是 SLA → 提供换线与重试，播放时刷新详情，不持久化媒体 URL。
- 浏览器 CORS/混合内容与原生不同 → 本切片验收 Android；Web 保留设计预览，不声称支持真实 Web 播放。
- 上游广告/更新并非本项目功能 → 只封装接口，不驱动下载、跳转或 SDK 广告初始化。

## Migration Plan

只新增前端依赖/实现，保留 preview 分支。无 DB 迁移；本机 v1 增加可选 snapshots 键并向后兼容。验证后构建安装测试 APK，不覆盖旧 APK 交付件。回滚仅本任务新增和修改文件至基线，保留原有未提交文档及 test123 私有运行时。不自动提交推送。

## Open Questions

无阻塞产品决策。上游 HTTPS、外部解析长期可用性、跨端过期地址重新解析属于后续能力，不在本切片静默扩大房间协议。

## Sources

- SDK 原始代码及 .local/provider-probe/live-20261021/ 请求证据。
- https://pub.dev/packages/pointycastle （4.0.0）
- https://docs.flutter.dev/cookbook/networking/background-parsing
- https://developer.android.com/privacy-and-security/security-config
