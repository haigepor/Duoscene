# 第一片 REST 契约

机器可读入口：`packages/contracts/openapi/openapi.json`。
请求/成功数据的单一 Schema 来源：同目录 `api-v1.schema.json`；Fastify 直接加载该文件。
Flutter 尚未接入模型，之后必须消费同一 fixtures 再做跨语言验证。

业务前缀 `/api/v1`；健康探针单独位于 `/health/*`。
成功 `{data,requestId}`，失败 `{error:{code,message},requestId}`。
响应禁用缓存；不把 SQL、密码、token、邀请码或签名 URL 写入日志。

| 方法/路径 | 鉴权与权限 | 输入/成功结果 |
| --- | --- | --- |
| POST /auth/login | 无 Bearer；10 次/分钟/IP | username/password/deviceLabel -> accessToken/refreshToken/tokenType/expiresIn/user |
| POST /auth/refresh | refreshToken；10 次/分钟/IP | refreshToken -> 新凭据，旧凭据失效 |
| POST /auth/logout | Bearer | 撤销当前会话 -> {ok:true} |
| GET /auth/me | Bearer | {id,username,displayName} |
| POST /rooms | Bearer | {name} -> 房间含房主席位，201 |
| GET /rooms | Bearer | after UUID、limit 1–50（默认20）-> {items,nextCursor} |
| GET /rooms/:roomId | 持久成员 | 房间及 members；未加入者返回404 |
| POST /rooms/:roomId/invites | 房主，房间 OPEN | 无 body -> {id,token,expiresAt,maxUses:1}，201 |
| DELETE /rooms/:roomId/invites/:inviteId | 房主 | 撤销邀请 -> {ok:true} |
| POST /rooms/join | Bearer + 邀请 token | {token} -> 房间及 members |
| POST /rooms/:roomId/leave | 非房主 | 释放自身持久席位 -> {ok:true} |
| DELETE /rooms/:roomId/members/:userId | 房主，OPEN | 移除非房主成员 -> {ok:true} |
| POST /rooms/:roomId/close | 房主 | CLOSED，撤销邀请，保留成员与房主身份 -> {ok:true} |

房间列表按 UUID 二进制字典序稳定分页，不声称按创建时间排序。
同一加入请求 ACK/HTTP 响应丢失时，已有成员重试同一 token 返回当前房间，不再次消费邀请。
即使邀请后来过期/已使用，已加入成员的重试也不会重复消费；关闭房间始终拒绝加入。
其他 POST 如建房/登录不自动幂等，客户端不得盲目无限重试。

## 登录示例（仅夹具）

```json
{"username":"fixture_user","password":"fixture-only-password","deviceLabel":"test-phone"}
```

Bearer 是随机不透明 token，不是 JWT。access 最大 15 分钟，会话固定 30 天；
每次请求查库，注销/禁用/重放撤销后新请求立即失效。
refresh 必须由客户端单飞串行；严格策略下并发刷新视为重放，整条会话撤销，重新登录。
刷新响应丢失后再次发送旧 token 同样撤销，不暗中缓存明文新 token 进行重发。
App 需安全存储 token；当前不提供浏览器 cookie/CORS 登录流程。

邀请码 256-bit 随机，默认 15 分钟、一次使用；只在签发响应出现明文，数据库存 SHA-256。
邀请通过请求体提交，不放 URL。房间最多两名持久成员，在线状态尚未实现。

## 错误约定

| HTTP | code | 含义 |
| --- | --- | --- |
| 401 | UNAUTHORIZED / TOKEN_REPLAY | 无效/过期凭据、禁用账户或刷新重放 |
| 403 | OWNER_REQUIRED | 需要房主权限 |
| 404 | NOT_FOUND / ROOM_NOT_FOUND / INVITE_NOT_FOUND | 未知资源或非成员不可读 |
| 409 | ROOM_FULL / ROOM_CLOSED / INVITE_UNAVAILABLE / OWNER_MUST_CLOSE / RESOURCE_CONFLICT | 状态、席位、邀请或数据库并发冲突 |
| 422 | VALIDATION_ERROR / INVALID_USERNAME / INVALID_PASSWORD | 输入不合法；多余字段拒绝而非静默剥离 |
| 429 | RATE_LIMITED / AUTH_BUSY | IP 频率或哈希并行预算超限 |
| 503 | DATABASE_NOT_CONFIGURED / DATABASE_UNAVAILABLE | 数据库关闭、失联或表未就绪 |
| 500 | INTERNAL_ERROR | 未预期错误；不返回内部详情 |

损坏 JSON 等 HTTP 语法问题返回400 INVALID_REQUEST；过大请求返回413 INVALID_REQUEST。
默认业务路由限流120次/分钟/IP，登录与refresh收紧为10次，内存有界缓存适用于单进程。
scrypt 并行上限2，防止哈希占满内存；所有 scrypt 使用异步工作线程。
反向代理与 HTTPS 尚待部署切片，当前仅允许本地开发环境测试 HTTP。

媒体、播放列表、WS票据、同步命令、TURN凭据、聊天/历史尚未开放，不能调用占位接口。
