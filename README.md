# Duoscene

两个人共享一间私密观影室：Flutter 手机端同步观影、文字聊天和双人语音。
视频由两台手机分别从视频源/CDN 拉取；API 只负责账户、房间、状态和信令。

**当前阶段：私有账户/房间后端及 Flutter 登录、建房、邀请加入及 Playra 播放内核、功能与页面已集成，并通过官方/雷电模拟器 MP4/HLS 验收。**
Docker Desktop、WSL2 和 MySQL 开发环境已就绪；数据库迁移已执行。
移动端已通过真实后端 HTTP 联调；Android 构建/设备证据见下方验证记录。未部署生产或创建远程资源。

```text
apps/mobile/       Flutter 登录/房间/Playra 播放器、会话与 HTTP 客户端、Android/iOS 工程与测试
apps/api/          Fastify、私有账户/会话、房间/邀请、迁移与管理员命令
packages/contracts/ REST JSON Schema/OpenAPI、WS 协议预留、共享 fixtures
infra/             开发 MySQL Compose、Caddy/coturn 部署边界
docs/              架构、需求摘要、后续实施切片、版本来源与验证记录
scripts/           无依赖的工程完整性检查
```

完整目录与依赖方向见 [architecture.md](docs/architecture.md)，
后续工作见 [implementation-plan.md](docs/implementation-plan.md)。
Playra 播放内核、功能与页面的集成说明见 [playra-player-integration.md](docs/playra-player-integration.md)。

## 开发与检查

环境要求 Node.js 24 LTS（支持范围 `>=24.14.0 <25`），npm 11。
已有锁文件，新环境先运行 `npm ci`；项目 `.npmrc` 默认禁用依赖安装脚本。
以下检查不绑定服务端口：

```sh
npm run check:structure
npm run test:unit
npm run typecheck
npm test
npm run build
```

## 后续开发命令

当前 MySQL 位于 `127.0.0.1:3307`，避开本机已有3306服务；凭据在被忽略的 `.env`。
Docker Desktop启动后，可用以下命令启动开发数据库；管理员账户需按实际需要手动创建：

```sh
docker compose --env-file .env -f infra/compose/compose.dev.yaml up -d mysql
npm run db:migrate
npm run account:create --workspace=@duoscene/api -- alice "Alice"
npm run account:create --workspace=@duoscene/api -- bob "Bob"
```

新环境可复制 `.env.example` 为 `.env`；本机已有随机凭据，不覆盖现有 `.env`。开发 MySQL 参见
[infra/compose](infra/compose/README.md)。准备好后手动启动 API：

```sh
npm run dev:api
```

- `GET /health/live`：进程存活。
- `GET /health/ready`：数据库连通且六个预期迁移 APPLIED 才成功，否则503。
- `/api/v1/auth/*`、`/api/v1/rooms/*` 已有实现；WS、片源解析和语音尚未实现；单机播放器已接入。
- `DATABASE_MODE=disabled` 仅供骨架开发，生产模式会拒绝该配置。

Flutter 的环境加载、API 地址、USB 手机连接与测试说明见 [apps/mobile](apps/mobile/README.md)。
本机使用 Flutter 3.47.6 / Dart 3.13.5 / Android SDK 36 / 独立 JDK 21，环境脚本为 scripts/mobile-env.ps1。
移动端切片范围与回退见 [mobile-slice.md](docs/mobile-slice.md)，实际证据见 [mobile-verification.md](docs/mobile-verification.md)。

接口见 [api.md](docs/api.md)，表与事务见 [database.md](docs/database.md)。
真实数据库测试必须使用显式的 `DUOSCENE_TEST_DATABASE=duoscene_test_*` 隔离库：

```sh
npm run test:mysql
```

该套件会创建/迁移测试表和测试账号，并仅清理自身资源，当前7项全部通过，无跳过。
默认测试另有20项通过。完整操作见 [第一片运行说明](docs/local-development.md)，
环境版本、镜像摘要和恢复说明见 [搭建记录](docs/database-environment-setup.md)。

## 已确认约束

- App：Flutter/Dart；播放器固定为 Playra 当前 media-kit 分支，语音使用 flutter_webrtc。
- 服务：单 API 进程、Fastify、标准 WebSocket（未来 @fastify/websocket）。
- 存储：MySQL 8.4 LTS、mysql2 连接池、参数化 SQL 与显式事务。
- 语音：WebRTC P2P + coturn；WS 不传电影或语音媒体。
- 运维：单 Linux VPS + Docker Compose + HTTPS/WSS；首版无需 Redis。
- 私有两账户、关闭公开注册、最多两名持久房间成员。

版本核验与官方资料见 [versions.md](docs/versions.md)，实际验证状态见
[verification.md](docs/verification.md)。播放同步、语音和正式平台签名尚未实现，尚非生产就绪交付。

播放器安装包、雷电 OpenGL 兼容设置、实际截图和平台限制见 [player-verification.md](docs/player-verification.md)。
