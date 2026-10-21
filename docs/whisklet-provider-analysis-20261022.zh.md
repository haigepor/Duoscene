# 第一播放源：接口实测与前端接入说明

## 1. 结论与边界

- 目标包：`C:\Users\haige\Desktop\instruct\tv-reverse-com.jjpengcheng.callshow.zjmc-api`，纯 Python SDK，不是需要部署的后台服务。
- 2026-10-21 至 22 日：串行请求了全部 **17 个业务方法**，补测分类第二页、直播、另一条影片详情、平台解析及五条直链的清单/分片。
- 16 个读接口取得符合用途的数据；`vod_heat_add` 收到 HTTP 200 包装回执，但回执的 `code=1` 是 Python SDK 合成，不能证明远端热度已持久化。
- 平台 BBA 解析器返回 `code=200` 和 MP4；MP4 Range 返回 206/64 字节。五条直链的主/子 HLS 与首分片 Range 成功。协议巡检仅取清单与媒体前 64 字节；另进行了短时原生播放测试，不下载完整影片。
- Duoscene 的 SDK、解密、片库、选线选集和播放解析都在 Flutter。`apps/api` 不增加代理、爬取或媒体路由，不接收上游协议密钥。原 SDK 包保持原样。
- 真实账户默认使用第一片源；明确的设计预览继续使用原静态数据，网络失败不会回退成虚构影片成功。

## 2. 网络与协议

统一入口：`POST http://198.16.39.44:27264/nzjm.php/v7/logs`。

明文结构（传输时不是明文 JSON）：

```json
{"method":"video_list","data":{"tid":2,"pg":1,"limit":20},"csrf":1780000000000}
```

`csrf` 必须在请求时生成当前毫秒值，示例数值不能复制为运行配置。加密为 AES-128-CBC / PKCS7；16 字节随机 IV 放在密文前，再作无填充 base64url。密钥由原 SDK profile 的构建时间、协议盐和应用标识做 MD5 派生；这属于兼容协议，不是 Duoscene 账户密码或保密边界。

必需协议头包括 `version`、`version-number`、`pk-id`、`build-time`、`platform`、`platform-version`、`user-agent` 与 `content-type: text/plain`。它们由独立 WhiskletClient 构造，**不复用 Session/账户 API Client**。

响应有三种：

1. 普通 JSON：13 个方法。典型根字段 `code`、`msg`、`data`，列表另有 `page` / `pagecount`。
2. 包装信封：`app_config`、`video_detail`、`secret_parse_api_url`。三段 base64 拼接，随机残差、IV 与 CBC 密文；可能缺失明文头部。
3. 回执：`vod_heat_add`。不按普通 JSON 成功数据解释。

所有包装还原保留 `_meta.reconstructed_header` / `verified=false`。CBC 没有 MAC，不提供响应真实性认证；HTTP 又没有 TLS。正式面向公网发布前，建议上游提供 HTTPS，不能因“有 AES”而宣称链路安全。

## 3. 全部 17 个方法

以下均使用上面的统一 POST；空 token 表示匿名访问，不传 Duoscene token。字段长度与数量为此次样本，不是永久保证。

| 方法 | data 请求参数 | 本次解码 data | 结果与接入用途 |
|---|---|---|---|
| `app_config` | `token:""` | 14 个 `*_config` 对象 | HTTP 200，包装恢复；读配置，不自动采纳广告/更新/任意播放器参数 |
| `advert` | `token:""` | 9 个广告位/开关组，部分为空列表 | 200 / code 1；只提供受限接口，不初始化第三方广告 SDK |
| `nav` | `token:""` | 7 个分类；每项 `type_id,type_name,type_extend` | 200 / 1；作为真实分类导航 |
| `top_notice` | `token:""` | `id,title,intro,create_time,is_top,content,content_empty` | 200 / 1；公告摘要对象 |
| `index_recommend` | `token:""` | `banners` 1 项、`videos` 3 组，每组 `vlist` 6 项 | 200 / 1；聚合去重后展示推荐片目，忽略广告 banner 跳转 |
| `last_version` | `token:""` | `[]` | 200 / 1；此为空结果，不意味着 Duoscene 已是最新版 |
| `notice` | `token:""` | 1 项公告列表 | 200 / 1；原 SDK 没有专门 wrapper，Dart 已补足 |
| `video_list` | `tid,pg,limit` | 影片摘要列表，每项 5 字段；根有分页 | 200 / 1；`limit=10` 仍返回 21 项，电视剧第一页 `pagecount=2049`，第二页确实改变；直播返回 2 项 |
| `search` | `text,pg,token:""` | 摘要列表，并增加 year/area/actor/lang | 200 / 1；样本 20 项、`pagecount=91`，支持前端去抖和真实翻页 |
| `rank_list` | `{}` | 5 项 `id,name` | 200 / 1；返回榜单分类元数据，**不是影片排行榜**，不可硬塞影片列表 UI |
| `notice_detail` | 可空；或 `id` | HTML 字符串，样本 1085 字符 | 200 / 1；不执行 HTML 或其中脚本 |
| `advert_detail` | `id`，优先从 advert 取得 | HTML 字符串，样本 373 字符 | 200 / 1；样本是空 body 页面，不能当作可播放片目 |
| `video_detail` | `id`，不是 `vod_id` | `vod_info`（83 字段）、`vod_history,is_collect,comment_count` | 200，包装恢复；两条样本分别有 1 / 11 条线路 |
| `secret_parse_api_url` | `url,player_code,token:""` | 解析器 param 字符串 | 200，包装恢复；BBA 满长 800 字符，此次共请求 4 次才取到满长；空 URL 曾被 SDK 解成 code 1 / null，**不能算成功** |
| `comment_list` | `vid,token:""` | `[]` | 200 / 1；原 SDK 的 page 形参未发送，不能声称支持评论分页 |
| `dm_list` | `group_key,token:""` | `[]` | 200 / 1；group_key 为 MD5(影片 ID 文本) 的前 20 个十六进制字符 |
| `vod_heat_add` | `id,token:""` | 无普通 data；包装回执 | HTTP 200，SDK 合成成功；此次仅发一次，不做自动写重试，也不宣称已证明远端计数变化 |

`app_config` 的 14 组：`img_config`、`advert_config`、`modules_config`、`find_config`、`share_config`、`contact_config`、`comment_config`、`short_config`、`live_config`、`dm_config`、`history_config`、`report_config`、`video_detail_config`、`player_config`。

分类实测：1 电影、2 电视剧、4 动漫、5 综艺、20 电视直播、21 短剧、22 AI 漫剧。`type_extend` 虽含筛选枚举，但 **本轮未证明 video_list 接受这些筛选参数**，当前不伪造远程筛选能力。

## 4. 影片详情与播放链

摘要的 `vod_id/name/pic/type_id/remarks` 归一化为 Film；详情补全简介、类型、时长及剧集。`vod_total` 本次可以为 0，不能拿它代替实际剧集数。

真正播放数据在：`data.vod_info.vod_url_with_player`。线路含 `name,code,url,parse_api,headers` 等；剧集串为 `集名$令牌#集名$令牌`。规则：

```text
详情 → 选择线路/剧集
  ├─ parse_api 为空 → 令牌就是直链 → 原生播放器
  ├─ 平台 /ajiami/ → secret_parse_api_url(令牌, 实际 player_code)
  │                  → 完整 param → GET 解析器 → code=200/url → 原生播放器
  └─ 外部解析模板 → GET 模板+令牌 → code=200/url → 原生播放器
```

**不能用“令牌以 http 开头”判断直链**：一些官方站视频页面也需要解析。

实测网络链：

| 线路 | 验证结果 |
|---|---|
| BBA 平台解析 | parser HTTP 200 / code 200；目标腾讯 MP4 HTTP 206，64 字节 |
| lzm3u8 | 主/子清单 200，首 TS Range 206/64 字节 |
| jsm3u8 | 清单 200，跨域首分片 206/64 字节 |
| dyttm3u8 | 主/子清单 200，首分片 206/64 字节 |
| 1080zyk | 两条不同影片的主/子清单 200，首分片 206/64 字节 |
| rym3u8 | 主/子清单 200，首分片 206/64 字节 |

另发现该详情存在 `co,NBY,zijianm3u8,rose,qiyi`。本轮没有逐条证明这些解析器可播；其中 `qiyi` 不在原 SDK 满长映射表，客户端会明确提示不支持而不是猜长度。该样本没有外部 Ace 线路，所以**没有验证当前外部解析可用性**。

## 5. 对原 SDK 的修正点

1. `Client.call` 不因业务 code 非 1 抛错：Dart 显式区分网络、HTTP、业务、结构、解析错误。
2. `fetch_param` 硬编码 BBA：Dart 必须使用当前选中的真实 player_code；最多 8 次，间隔 350ms，不无限重试。
3. SDK 声称 data 永远完整与解析字符串截断现象矛盾：Dart 验证形状/长度，缺失数据不伪造成功。
4. `comment_list(page)` 参数实际被丢弃：不承诺不存在的分页。
5. `notice` 没有 wrapper：Dart 为全部 17 方法建立枚举和调用入口。
6. 列表 limit 不可靠：使用根级 `page/pagecount`，按 provider-qualified ID 去重，不能用“返回长度等于请求 limit”判断下一页。
7. 原 Python HLS 地址拼接不完整：本次巡检使用 `urljoin`；生产 Flutter 将清单交给已有 mpv，不另写 HLS 下载器。
8. 原 SDK 修改模块全局 host/port：Dart 单独 client 持有连接和生命周期，不改通讯后端配置。

## 6. 前端结构与后端职责

```text
真实会话 LibraryState
  └─ MediaProvider（第一实现 WhiskletProvider）
      ├─ WhiskletClient：17 方法、专用协议头、超时/取消/响应上限
      ├─ WhiskletCodec：请求加密、后台 isolate 解码、受限前缀恢复
      ├─ 分类/推荐/分页/搜索 → Film / CatalogPage
      └─ 详情/线路/剧集 → MediaDetail → 新鲜 PlaybackSource
                                            └─ 原 Playra/mpv

Session / RoomConnection → 原 Duoscene 通讯 API
                          认证、房间、时间线、聊天、语音信令
```

- 稳定 ID：`whisklet:<vod_id>`；播放身份：`whisklet:<vod_id>:<line>:<episode>`，不含签名链接。
- 收藏和历史按账户存元数据快照；兼容原 v1 本机数据，不保存 episode token、param 或临时 CDN URL。
- 默认优先使用可用直链线路，保留全部线路供用户选择；历史额外保存可选线路代号，恢复时先重取详情与新地址。分类父 ID 为 0 时回退实际分类，不把电视剧误归为“影片”。
- 只采纳必要媒体 header 白名单，丢弃 Cookie / Authorization 与远端 `core_params`；不让上游改变任意 mpv 配置。
- Android 普通构建仅对固定 API IP 放行 HTTP；debug 同名网络资源额外允许原有本机 API，不全局关闭 TLS/明文限制。
- 现有房间依旧可同步双方可访问的公共媒体 URL；**尚未扩展 provider 逻辑 ID 的跨端解析与短效 URL 刷新协议**。第一片源本切片主要闭环为个人播放；不把此限制伪装成已完成同看片源集成。

## 7. 复现与证据

从项目根目录运行：

```powershell
py -3.13 -X utf8 scripts/probe-whisklet.py `
  --sdk-root 'C:\Users\haige\Desktop\instruct\tv-reverse-com.jjpengcheng.callshow.zjmc-api' `
  --output '.local/provider-probe/new-run'
```

此命令包含一次热度写回执请求；重复读取既有证据时加 `--resume`，避免重复发送已完成方法。原始响应、解密 JSON、解析 URL、媒体片段均只保存在忽略目录，不提交含短效链接/客户端地址的抓取文件。

当前证据：`.local/provider-probe/live-20261021/summary.json`，同目录有每个方法的 `.wire.txt` 与 `.json`，以及清单、64 字节媒体取样；`offline.txt` 为 SDK 五模块离线自检全部通过。

OpenSpec：`openspec/changes/integrate-whisklet-provider/`，严格校验通过。Dart 的 171 个包装向量由独立 Python SDK 生成，覆盖所有 16 种残差及多种丢头长度，另用实际采样的三类包装响应与 Python 解码结果对拍。可通过 `py -3.13 -X utf8 scripts/generate-whisklet-vectors.py <SDK目录>` 重新生成（从项目根目录运行）。

## 8. 验证与交付状态

- 最终全量 Flutter：**295 项通过**；`flutter analyze --no-pub` 无问题；3 项共享契约测试通过；结构/JSON/UTF-8/LF 检查通过。
- Android 首次本机构建发现 debug/main 网络资源重名策略不一致造成 manifest merger 冲突；改用同名资源按构建类型覆盖，不全局放宽网络权限。
- 真机首轮发现随机截头可把 msg 错接成字符串 code；新增丢头 15/16 字节回归后，恢复候选必须满足整型 code。后续真机连续 4 次 app_config 解码及播放全部通过。
- **原生集成测试通过**：Honor LLD-AL20 / Android 9，实际 7 分类、18 推荐、真实详情、lzm3u8 拉流、首帧和进度推进。采样：1080×450，时长 2,830,480ms，播放进度 2,503ms，原生截图 97,021 字节。证据在 `.local/provider-probe/native-captures/provider-native-proof.json` 与 PNG；日志 `native-final.log`。
- 正常 APK 已安装并以 test123 登录，真实首页、分类、线路选择与播放器页面均已操作；覆盖更新后鉴权 refresh 200，收藏与历史快照恢复。正常 App 实际播放后本机记录为 8 秒、第 1 集、lzm3u8 线路；截图 `restored-playing-final.png`、数据 `device-library-proof.json`。其他界面取证在 `.local/provider-probe/*-final.xml/png`。未完成的长时、所有线路与双设备验收不能由这一次首帧替代。
- 旧 GitHub Debug 签名与本机签名不同；用户已同意先备份再重装。备份在 `.local/provider-probe/device-backup/`，不导出旧认证密钥。后端 test123 账号及独立 MySQL 实例不变。
- APK：`output/android/duoscene-provider-arm64-debug.apk`，本机 Debug 构建，USB 通讯地址 `http://127.0.0.1:3000`。新增代码尚未提交/推送，本次不是新的 GitHub Actions 构建；之前交付的旧 APK 保留不变。最终字节数、SHA256 和构建基线在同目录 `provider-build-info.json`。
- 最终交付 199,772,046 字节；SHA256 `f9cd26d244ec2e2d8a8641fdb7818e9d3fb3f58f7bc2b352bea0bf18e1c89c87`。APK ZIP/CRC、签名与仅 arm64 原生库检查通过；设备已安装 base.apk 的 SHA256 与交付件一致，当前进程未见 Flutter/FATAL 错误。
- 临时取证服务及 ADB 33308 转发已清理；仅保留原本机通讯 API 的 ADB 3000 转发和 test123 私有运行时。

### 五轴复核

| 轴 | 状态 | 证据或限制 |
|---|---|---|
| 正确性 | PASS（本切片） | 17 方法巡检、截头恢复回归、真实目录与原生播放；未把热度回执当远端写入证明 |
| 可读性 | PASS | codec/client/provider/页面职责分开，生成脚本可复现向量，Dart 格式检查零变更 |
| 架构 | PASS | 后端/共享通讯契约/原 SDK/vendored 播放库无变更；房间逻辑 ID 刷新明确另列 |
| 安全 | FINDING | 未泄漏账户 token，限制参数/header/HTTP 范围；上游 HTTP + 无 MAC 仍有残余风险 |
| 性能与可靠性 | PARTIAL | isolate 解码、超时/取消、响应上限和有限重试已实现；长期可用率、全部解析器和长时资源曲线未测 |

### 实施文件与回滚

- `apps/mobile/lib/features/catalog/providers/`、`media_provider.dart`：协议、17 方法、模型与解析；新增 PointyCastle 4.0.0、crypto 3.0.7，锁文件固定版本。
- `provider_catalog_view.dart`、home/search/detail/posters 与 experience 播放入口：真实片库、图片容错、选线选集；设计预览分支保留。
- `library_state.dart`、collection/home_content：账户隔离的快照、线路和历史续播，兼容旧 v1 数据。
- Android main/debug 同名 network security 资源：普通包仅放行 provider IP，debug 额外放行既有本机服务。
- `scripts/probe-whisklet.py`、`generate-whisklet-vectors.py`、新增 unit/widget/integration 测试与 OpenSpec：实测和回归可复现。
- 未修改 `apps/api`、`packages/contracts`、vendored media-kit 或外部 SDK。原有未提交的两份文档及另一处 `.gitignore` 外部改动保留。
- 回滚位置：基线 `027337fa36fc452c5e8a871665b9b60f9f5df6a5` 仅用于本任务改动的逐文件比较，不执行全仓 reset；新增文件可按该清单移除。旧安装包仍在 `output/android/duoscene-arm64-debug.apk`（旧签名，回装会再次需要重装/登录）。本机数据备份位于上述忽略目录。

## 9. 后续完善优先级

1. 第一优先级：上游 HTTPS；房间同步 provider/item/line/episode 逻辑描述，每个前端独立刷新地址，后端只校验/转发和存通讯状态。
2. 第二优先级：补测全部解析家族、未知 qiyi 与真实外部解析模板，做线路可用率和故障切换；不要通过猜测或无限重试解决协议漂移。
3. 第三优先级：按明确能力接入评论/弹幕展示、受限纯文本公告、缓存 TTL 和离线元数据；上游广告和升级不应自动接管本应用。
4. 内容授权、第三方稳定性、跨网络/两设备同看、长时间漂移与播放失效回归须单独验收，本轮不作永久可播或版权保证。

参考：[PointyCastle 官方包](https://pub.dev/packages/pointycastle)、[Flutter 后台解析](https://docs.flutter.dev/cookbook/networking/background-parsing)、[Android 网络安全配置](https://developer.android.com/privacy-and-security/security-config)。原 SDK 与当次接口响应为私有协议的直接证据。
