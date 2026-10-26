# 同看交接与播放恢复

## 目标与范围

修复 readiness 漏迁移、播放命令先发布后落盘、自然播放进度未保存的问题，并接通个人播放到双人房间的影片、集数、线路和进度。保留既有 URL 播放、两席成员、鉴权和手动暂停规则。

本次不改变部署拓扑、第三方协议、页面视觉、语音协商或同步精度目标。基线为当前工作区，已有未提交修改保留；不修改历史迁移 SQL。

## 行为与契约

1. readiness 与迁移执行共用实际迁移文件清单，缺少任何必需迁移或迁移状态异常均不可就绪。
2. 播放命令在候选时间线上执行，保存成功后才替换权威态和确认；失败不污染已提交状态或命令去重。
3. 播放每 5 秒检查点；缓冲/就绪变化、断线、关闭保存冻结位置。失败保留待保存状态并重试，未落盘房间不得因空闲而被清理。
4. 恢复只接纳已验证的媒体、位置和倍速，新运行纪元始终暂停并等待双方准备。突然终止恢复至最近一次成功检查点，不宣称数据库故障期间无损。
5. Provider 交接只保存 provider、filmId、episode、lineCode、identity、title；不共享 URL、请求头、API token 或解析参数。双方独立解析，指定线路不可静默回退。
6. media 命令可携带 positionMs，一次提交媒体与起点，初始暂停。旧 URL 形态及未提供起点的命令继续可用。
7. 邀请初始化成功后才签发；重试保留已有房间媒体。客户端等待媒体可定位后应用起点，隔离迟到解析和旧 generation 的 ready。

## 文件范围

- `apps/api/src/{plugins,commands,shared,modules/realtime}`：就绪、迁移清单、时间线候选提交与检查点。
- `apps/api/test`：就绪、故障注入、进度恢复及协议回归。
- `apps/mobile/lib/features/{catalog,experience,realtime}`：详情、长视频与短剧邀请入口，片目描述、独立解析和初始进度落地。
- `apps/mobile/test`：交接、解析、代际、真实后端联调。
- `packages/contracts`：联合媒体 Schema、正反夹具及一致性测试。

本轮共 30 个文件。对照修改前工作区副本核验，另有 45 处原有差异保持不变。

| 文件 | 用途与影响 |
| --- | --- |
| `apps/api/src/shared/migrations.ts`、`apps/api/src/commands/migrate.ts`、`apps/api/src/plugins/database.ts` | 统一迁移清单，就绪探针拒绝缺失迁移的库 |
| `apps/api/src/modules/realtime/timeline.ts`、`apps/api/src/modules/realtime/playback.ts`、`apps/api/src/modules/realtime/hub.ts` | 联合媒体描述、候选提交、进度检查点、接纳/清理与关闭保护 |
| `apps/api/test/app.test.ts`、`apps/api/test/realtime-policy.test.ts`、`apps/api/test/playback-persistence.test.ts`、`apps/api/test/realtime-persistence.test.ts`、`apps/api/test/realtime.integration.ts` | 就绪、协议、落盘失败、重连、恢复与并发回归 |
| `apps/mobile/lib/features/catalog/detail_page.dart`、`apps/mobile/lib/features/experience/experience_player.dart`、`apps/mobile/lib/features/experience/short_feed.dart` | 详情、长视频及短剧邀请携带实际线路/集数/进度；保留既有页面与业务修改 |
| `apps/mobile/lib/features/experience/invite_pages.dart` | 先初始化媒体再签发邀请；失败重试复用房间；远端封面复用现有加载控件 |
| `apps/mobile/lib/features/realtime/room_media.dart`、`apps/mobile/lib/features/realtime/room_playback.dart`、`apps/mobile/lib/features/realtime/room_watch_page.dart` | 片目初始化、双方独立解析、延迟 seek、代际隔离及播放源生命周期 |
| `apps/mobile/test/backend_integration_test.dart`、`apps/mobile/test/room_invite_handoff_test.dart`、`apps/mobile/test/room_media_test.dart`、`apps/mobile/test/room_playback_test.dart` | 真实后端交接与客户端失败/竞态回归 |
| `packages/contracts/README.md`、`packages/contracts/websocket/README.md`、`packages/contracts/websocket/commands.schema.json`、`packages/contracts/test/contracts.test.mjs` | 协议说明、联合媒体 Schema 与运行时一致性检查 |
| `packages/contracts/fixtures/media-provider.valid.json`、`packages/contracts/fixtures/media-provider.invalid.json`、`packages/contracts/fixtures/media-url.valid.json` | Provider 交接与旧 URL 正反夹具 |
| `docs/watch-handoff-reliability-20261025.zh.md` | 本轮行为、验证、范围与回退记录 |

## 验证记录

真实数据库使用独立目录、端口和 `duoscene_test_*` 库，不复用正在运行的业务 API 或数据库。验证使用项目内 Node 24.22.0、现有 Flutter 3.47.6 / Dart 3.13.5。

| 检查 | 结果 |
| --- | --- |
| `npm run check:structure` | PASS；结构、JSON、引用及 UTF-8/LF |
| `npm run typecheck`、`npm run build` | PASS |
| `npm run test:contracts` | PASS，6 项；Provider/URL 正反夹具与运行时 Schema 一致性 |
| API `test/*.test.ts` | PASS，31 项；含真实 localhost WS 故障注入、断线/关闭恢复与清理竞争 |
| `mysql.integration.ts`、`account-recovery.integration.ts`、`realtime.integration.ts` | PASS，9 项；真实隔离 MySQL、Fastify 与双方 WS |
| `node scripts/test-mobile-backend.mjs` | PASS，1 项；真实 Dart Session → WS 初始化第 3 集 / 42.5 秒 → 邀请/加入 → 双方一致快照，独立解析取得不同 URL/headers |
| Flutter 聚焦回归 | PASS，21 项；邀请顺序/重试、零时长 seek、代际隔离、同源 seek、失败暂停旧片与旧 URL 兼容 |
| `flutter analyze --no-pub` | PASS，No issues found |
| `flutter test --no-pub --concurrency=2 --reporter expanded` | PASS，464 项，含现有视觉基准与本轮回归 |
| 编译产物启动检查 | PASS；从 dist 加载 API，迁移目录解析、live 200 与未配置数据库 ready 503 正常 |
| 范围、编码、差异 | PASS；30 文件严格 UTF-8/无 BOM/无替换字符/LF，`git diff --check` 通过；范围外 45 处原差异未变 |

修复前已得到失败回归：缺少 0009 仍可就绪、Provider 媒体不被旧契约接受、时长为 0 时提前 seek、空房清理与新连接竞争产生不同 epoch。修复后均通过。独立审查发现并修复了解析慢/失败时旧视频继续播放的问题。

第三方 Provider 使用本地可控夹具；本轮没有对外部片源发网络请求。真实传输、认证、SQL 持久化与房间广播已验证；跨国网络同步精度、双真机原生解码/seek 与语音听感仍需专项验收。

隔离库 8 张业务表最终均为 0 行；测试专用进程与端口 33317 已停止。既有业务端口 3000/33307 保持监听，未运行针对业务库的迁移或测试。

## 回退

修改前源码快照：`.local/architecture-optimization-20261025/before/`，含基线状态、差异和文件清单。按本次文件清单逐项比对恢复，不能直接丢弃用户原有改动。新增文件须确认归属后单独处理；数据库没有新增业务迁移。
