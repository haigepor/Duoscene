# Duoscene

两个人，一间私密观影室。基于 Flutter 的手机端将同步播放、文字聊天和 WebRTC 语音放在同一个房间里，让双方一起选片、暂停、讨论和继续观看。

[项目特色](#项目特色) · [快速开始](#快速开始) · [第一次一起看](#第一次一起看) · [常见问题](#常见问题) · [开发与检查](#开发与检查)

**项目仍在开发中，尚非生产就绪。** 当前主要验证平台为 Android；iOS 工程已提供，编译、签名及真机行为仍需在 macOS 验证。两台设备分别从视频源/CDN 拉取视频，API 负责账户、房间、播放状态、聊天与语音信令，不代理电影或语音媒体。

## 项目特色

| 特色 | 当前能力 |
| --- | --- |
| 双人私密房间 | 关闭公开注册，通过管理员创建账号；房间最多两名持久成员，支持一次性邀请。 |
| 同步播放 | 双方共享播放、暂停、进度和倍速，并处理缓冲、断线与重新连接。 |
| 边看边聊 | 房间内文字聊天持久保存；语音按需开启，支持静音、好友语音音量与影片音量分别调节。 |
| Flutter 观影界面 | 已接入首个播放源，提供搜索、分类筛选、详情、收藏、观看记录与短剧播放控制。 |
| Playra 播放核心 | 基于 Playra 的 media-kit 分支，支持 MP4/HLS 与本地文件播放；双人同看需使用双方都能访问的视频地址。 |
| 可自部署的后端 | 单 API 进程、Fastify、标准 WebSocket 与 MySQL；语音使用 WebRTC，跨网连接可配 coturn。 |

本地文件与私有媒体请求头目前不支持在双人房间中共享。跨网、长时运行及真人语音听感仍需专项验收，详见[实时功能验证](docs/realtime-verification.md)与[最新交付说明](docs/git-delivery-20261022.zh.md)。

## 快速开始

首次使用需要依次准备数据库、API 和手机端。当前没有公开 Release 安装包；Android 调试包的 Actions 获取方式见[移动端说明](apps/mobile/README.md#github-actions-安卓测试包)，安装 APK 后仍需自行运行后端。

### 1. 准备环境并安装依赖

| 环境 | 要求 |
| --- | --- |
| Node.js / npm | Node.js `>=24.14.0 <25`，npm `>=11 <12` |
| 数据库 | MySQL 8.4 LTS；下文使用 Docker Compose 开发环境 |
| 容器工具 | Docker Desktop 或支持 Compose 的 Docker 环境 |
| 手机开发 | Flutter 3.47.6 / Dart 3.13.5、Android SDK 36、NDK 28.2.13676358、JDK 21 |
| Android 设备 | Android 9 / API 28 及以上；现有 arm64 调试包需要 arm64-v8a 设备 |

克隆后在仓库根目录安装后端工作区依赖：

```sh
git clone https://github.com/haigepor/Duoscene.git
cd Duoscene
npm ci
```

已有锁文件与工作区配置，`.npmrc` 默认禁用依赖安装脚本。移动端工具安装与路径配置见[移动端开发指南](apps/mobile/README.md#本机开发)。

### 2. 配置本地环境

新环境将 `.env.example` 复制为 `.env`；已有配置时保留原文件，不要覆盖。在 PowerShell 中首次配置：

```powershell
Copy-Item -LiteralPath .env.example -Destination .env
```

启动前编辑 `.env`，至少检查以下项目：

| 配置 | 本机开发设置 |
| --- | --- |
| `DATABASE_MODE` | 改为 `mysql`；模板的 `disabled` 无法用于真实登录与房间功能。 |
| `MYSQL_HOST` | `127.0.0.1`，数据库不向外部网络开放。 |
| `MYSQL_PORT` | 模板默认为 `3306`；如已占用，可统一改为 `3307`，Compose 和 API 共用该值。 |
| `MYSQL_DATABASE` / `MYSQL_USER` | 开发 Compose 使用 `duoscene` / `duoscene`，首次启动时保持一致。 |
| `MYSQL_PASSWORD` | 设置独立随机密码，供 API 连接数据库；模板空值不能启动数据库。 |
| `MYSQL_ROOT_PASSWORD` | 设置另一份独立随机密码，不与应用数据库密码共用。 |
| `API_HOST` / `API_PORT` | USB 调试保持 `127.0.0.1` / `3000`。 |

`.env` 不提交到 Git。修改已初始化数据库的密码需要走数据库账户管理流程，仅修改环境文件不会更新卷内密码。详情见[Compose 说明](infra/compose/README.md)。

### 3. 启动数据库并创建账号

启动 Docker 后，在仓库根目录依次运行：

```sh
docker compose --env-file .env -f infra/compose/compose.dev.yaml config --quiet
docker compose --env-file .env -f infra/compose/compose.dev.yaml up -d mysql
docker compose --env-file .env -f infra/compose/compose.dev.yaml ps
```

等待 MySQL 健康检查通过后，创建业务表和两位使用者的账号：

```sh
npm run db:migrate
npm run account:create --workspace=@duoscene/api -- alice "Alice"
npm run account:create --workspace=@duoscene/api -- bob "Bob"
```

创建账号命令会在交互式终端隐藏输入密码，长度为 12–128 个字符。`alice` 和 `bob` 只是示例用户名，项目没有默认账号；不要把密码放进命令行参数、Dart 代码或测试夹具。

Compose 入口只启动 MySQL，不会自动启动 API、Caddy 或 coturn，也不会自动创建真实用户。停止数据库时不要附加 `down -v`，该选项会删除数据卷。

### 4. 启动并确认 API 就绪

在仓库根目录启动 API，并保留该终端：

```sh
npm run dev:api
```

默认地址为 `http://127.0.0.1:3000`。在另一个 PowerShell 终端检查：

```powershell
Invoke-RestMethod http://127.0.0.1:3000/health/live
Invoke-RestMethod http://127.0.0.1:3000/health/ready
```

`/health/live` 只表示进程存活；`/health/ready` 需要数据库连通且预期迁移已应用，否则返回 `503`。先确认 ready 成功，再连接手机。

### 5. 运行 Android 手机端

推荐先走 USB / ADB 反向端口转发，保持 API 和 MySQL 仅监听电脑回环地址。在仓库根目录打开新的 PowerShell 终端：

```powershell
. .\scripts\mobile-env.ps1
flutter doctor -v
adb devices
cd apps/mobile
flutter pub get --enforce-lockfile
```

连接手机并授权 USB 调试，将下方 `<adb-device-id>` 替换为 `adb devices` 列出的设备 ID，再运行：

```powershell
adb -s <adb-device-id> reverse tcp:3000 tcp:3000
flutter run -d <adb-device-id> --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

两台手机都需要各自的端口转发与应用启动。`API_BASE_URL` 只填 origin，不带 `/api/v1`、路径、查询或凭据；修改地址后需重新 `flutter run`，`flutter attach` 不会更换编译时配置。SDK 不在默认环境变量位置时，使用环境脚本的显式路径参数，见[移动端说明](apps/mobile/README.md)。

同一 Wi-Fi 调试、Profile 构建与地址变化处理见[局域网指南](docs/lan-development-20261022.zh.md)。其中启动脚本依赖原开发机已有的 `.local/test-account` 服务，不是新电脑的一键安装程序。正式发布需使用 HTTPS/WSS；本机调试地址和调试签名不能作为生产部署配置。

## 第一次一起看

后端 ready 成功且双方手机连接到同一 API 后，分别使用管理员创建的不同账号登录。

1. 打开“观影邀请 → 邀请与房间”，由一方创建房间并生成邀请码。
2. 将完整的一次性邀请码发给另一方，由另一方在“邀请加入”中粘贴加入；房间最多两位成员。
3. 在房间中打开播放器，选择双方都能访问的视频地址；视频分别由两台设备拉取。
4. 在“视频”页更换地址，并使用播放、暂停、拖动和倍速控制；在“交流”页发送文字消息。
5. 如需语音，双方主动点击“开启语音”并允许录音权限。跨网/NAT 场景可能需要配置可访问的 TURN 服务，参见[coturn 说明](infra/coturn/README.md)。

麦克风默认关闭。离开页面、断线或进入后台会释放麦克风，重新连接后需要主动开启。影片音量与好友语音音量可分别调节；语音失败不代表视频源或 API 一定不可用。

## 常见问题

| 问题 | 优先检查 |
| --- | --- |
| 安装 APK 后无法登录 | 手机是否能访问配置的 API；电脑上的 MySQL、API 是否已启动，`/health/ready` 是否成功。 |
| 手机访问 `127.0.0.1` 失败 | 这是手机自己的回环地址；USB 路径需要为该设备执行 `adb reverse`。LAN 路径需重新构建匹配地址与网络策略的 APK。 |
| live 成功、ready 失败 | 检查 `DATABASE_MODE=mysql`、数据库地址/凭据和迁移；disabled 模式只供骨架开发。 |
| 找不到注册或默认密码 | 公开注册关闭，管理员需通过终端创建账号；没有通用默认账号。 |
| 一方视频无法播放或同步 | 确认双方都能访问同一媒体地址；当前不共享本地文件或私有媒体请求头。 |
| 语音无法连接 | 检查录音权限、双方是否主动开启语音，以及 TURN 地址、凭据与网络可达性。 |
| Web 预览无法登录或播放 | Web 入口仅用于样式预览，真实账户、播放与双人同步请使用手机端。 |
| LAN 脚本找不到本机服务 | 先完成新环境部署；不要把原开发机专用脚本当成数据库安装程序。 |

## 开发与检查

后端与契约检查从仓库根目录运行。真实数据库测试单独执行。

```sh
npm run check:structure
npm run test:unit
npm run typecheck
npm test
npm run build
```

移动端从 `apps/mobile/` 运行：

```sh
flutter analyze
flutter test
```

真实 MySQL 测试必须显式配置隔离库 `DUOSCENE_TEST_DATABASE=duoscene_test_*`，不要指向日常业务数据库：

```sh
npm run test:mysql
```

完整流程见[本地开发](docs/local-development.md)、[数据库环境](docs/database-environment-setup.md)与[移动端验证](docs/mobile-verification.md)。Web 样式预览入口见[移动端 README](apps/mobile/README.md#web-样式预览)。

## 项目结构与资料

应用、协议与部署配置分开维护；API 处理房间状态与信令，媒体由客户端直接获取。

```text
apps/mobile/       Flutter 应用、Playra 播放器、聊天与语音、Android/iOS 工程
apps/api/          Fastify API、私有账户、房间、同步、迁移与管理员命令
packages/contracts/ REST JSON Schema/OpenAPI、WebSocket 协议与共享 fixtures
infra/             开发 MySQL Compose、Caddy/coturn 部署说明
docs/              架构、运行指南、版本来源与验证记录
scripts/           工程检查、调试与构建辅助脚本
```

- [架构](docs/architecture.md)、[API](docs/api.md)、[数据库](docs/database.md)：理解模块与接口。
- [版本来源](docs/versions.md)、[验证范围](docs/verification.md)：核对依赖与平台边界。
- [最新交付与已知限制](docs/git-delivery-20261022.zh.md)：查看本轮构建与设备验证。
- [页面样式](docs/style-restoration-20261022.zh.md)、[图片/筛选/短剧控制](docs/provider-rendering-refinement-20261022.zh.md)、[播放源分析](docs/whisklet-provider-analysis-20261022.zh.md)：了解当前前端实现。
- [播放器性能研究](docs/playra-performance-study-20261022.zh.md)、[后续实施计划](docs/implementation-plan.md)：区分已有证据与待完成工作。

## 来源与使用边界

播放器核心与控制来自 Playra，其上游来源包含 Kazumi；集成方式见[播放器集成说明](docs/playra-player-integration.md)。相关代码、media-kit 快照与许可证以[Playra 来源声明](third_party/playra-player/NOTICE.md)及对应第三方目录为准。

项目用于私密双人观影，播放源的可用性和访问权限由源站决定。当前部署目标是单 API 进程与 MySQL，不包含完整生产运维交付；正式签名、两设备跨网、长时性能和实际语音质量仍需验收。
