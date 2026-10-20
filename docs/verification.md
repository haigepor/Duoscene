# 验证记录

## 最新：Flutter 账户与房间（2026-10-19）

Flutter/Android/JDK 已配置，普通 Android APK 构建通过。
flutter analyze、12 项单元/widget、真实 Flutter HTTP + MySQL 流程，以及 API 24 模拟器页面/安全存储集成通过。
后端 20 项与 MySQL 7 项回归通过；iOS/物理手机、播放器与双人同步不在已通过结论内。
完整边界、环境改动、产物及回退见 mobile-verification.md。
最终结构/JSON引用/UTF-8/LF 检查通过，126 个文本文件；Dart 格式检查 18 个文件无变化，原生 XML/plist 13 个解析通过。
用户最新要求的 Playra 播放器迁移范围已分析，见 playra-player-integration.md；本次未迁入播放器源码。

## 历史：本地环境与真实数据库验收（2026-10-19）

Docker Desktop 4.95.0/Engine29.8.2/Compose5.6.0已安装，复用WSL2.7.11。
MySQL8.4.11运行于Docker，仅绑定127.0.0.1:3307；原有3306进程未改动。

| 检查 | 实际结果 |
| --- | --- |
| 安装包SHA-256与Authenticode | PASS，官方摘要匹配、Docker Inc签名Valid |
| WSL2/引擎/Compose/镜像 | PASS，Linux/amd64，镜像摘要固定，数据盘D:\DockerData |
| Compose config / 容器健康 | PASS，mysql容器healthy，只有本机3307端口 |
| `npm run db:migrate` | PASS，应用库六个迁移APPLIED |
| `npm run test:mysql` | PASS，7/7，0跳过；隔离库迁移及真实并发/事务/HTTP断言通过 |
| 容器重建后的持久化 | PASS，两库六个迁移均保留，命名卷未删除 |
| 真实数据库readiness | PASS，Fastify inject返回200 |
| `npm test` | PASS，20/20，0跳过 |
| `npm run typecheck` / `npm run build` | PASS |
| 结构/JSON引用检查 | PASS，101个项目文本文件，忽略.local安装与备份产物 |
| 严格UTF-8/无BOM/LF | PASS，102个文本文件（含本机.env），未显示凭据 |
| 凭据与修改范围检查 | PASS，真实密码未出现在其他项目文件，后端业务源码与备份一致 |

两库测试后users/rooms均为0，没有创建真实账户或默认演示账号。
搭建过程、版本、端口选择、修改文件及恢复位置见database-environment-setup.md。
当前任务结果为PASS；Flutter/音视频/生产部署没有包含在本次验收中。

---

## 历史：继续推进第一片后端（数据库环境就绪前）

日期：2026-10-19。已安装项目依赖并生成 package-lock.json，安装脚本禁用。
未启动监听服务、部署、创建远程资源或执行数据库迁移；Flutter 保持原骨架。

| 检查 | 结果 | 证据边界 |
| --- | --- | --- |
| 新增密码/席位测试初次运行 | RED，两个 ERR_MODULE_NOT_FOUND | 先写测试，之后实现 security.ts/policy.ts，再通过5项测试 |
| `npm test` | PASS：3个契约 + 17个后端测试，共20项；无跳过 | HTTP注入使用服务替身，不能证明MySQL并发正确 |
| `npm run typecheck` | PASS | 含src/test；曾遇Windows提交内存不足，串行并限制编译器并行后成功 |
| `npm run build` | PASS | 实际生成 dist，未启动server |
| `npm audit --json` | PASS，0个已知漏洞 | 不代表依赖绝对安全；安装脚本禁用，版本与完整性锁定 |
| `npm run test:mysql` | BLOCKED：前置检查失败 | `.env`/隔离库缺失，未连接MySQL；不是业务断言已通过 |
| `npm run check:structure` | PASS，99个文本文件 | UTF-8/无BOM/LF、JSON与相对路径、JSON引用；不等价于完整OpenAPI规范校验 |

真实MySQL入口失败的原始断言：
`Set DUOSCENE_TEST_DATABASE to an isolated duoscene_test_* database`。
没有跳过数据库测试并计入通过数量。DDL、两邀请码争位、事务回滚、并发refresh和真实HTTP套件待运行。

一次 npm 调用出现 `FATAL ERROR: Committing semi space failed. Allocation failed - JavaScript heap out of memory`。
当时Windows可提交虚拟内存约2GB；没有停止其他进程或修改系统设置。
后续检查串行执行，编译时局部设置 GOMEMLIMIT=256MiB、GOMAXPROCS=2，成功完成类型检查和构建。

安全/事务审阅见 backend-review.md；本轮范围与回退约束见 slice-1-scope.md。
结果为 PARTIAL：后端实现与无数据库检查通过，真实数据库/移动平台验收仍 BLOCKED。

---

## 初始骨架交付记录（历史）

日期：2026-10-19。初始目录 `D:\project\Duoscene` 为空，`git status` 返回
`fatal: not a git repository (or any of the parent directories): .git`。
本轮未初始化 Git、提交或创建远程资源。

## 已检查的环境

- Node.js v24.14.0、npm 11.9.0、Dart 3.9.0、Git 可用。
- Flutter、Docker、独立 TypeScript 编译器未在 PATH 中找到。
- 没有 npm node_modules、package-lock.json、Flutter pubspec.lock 或原生工程。

## 交付前检查

| 命令/检查 | 结果 | 适用边界 |
| --- | --- | --- |
| `npm run check:structure` | PASS，63 个文本文件 | 目录、JSON 解析、TS 相对路径、严格 UTF-8/无 BOM/LF；不是完整 Schema 验证 |
| `npm run test:unit` | PASS，4 个测试 | 配置默认值/错误端口/生产 DB 要求/密码必填、系统时钟跳变下单调间隔 |
| `dart format --output=none --set-exit-if-changed apps/mobile/lib apps/mobile/test` | PASS，3 个文件，0 修改 | 语法/格式，不是 Flutter 分析或构建 |
| `node --check` | PASS，API factory/server 与检查脚本 | 语法解析，不是 TypeScript 类型检查 |

最终范围复核：与 architecture.md 的树逐项比对，仅新增本轮声明的文件。
结果为 PARTIAL：静态骨架和无依赖测试通过，框架/平台运行证据仍受下列环境约束。

## 未运行的验证

- `npm run typecheck` / `npm run build`：依赖未安装，tsc 不可用。
- `npm test`：Fastify/mysql2/Ajv 未安装；包含待执行的 inject 与契约测试。
- MySQL 连接/迁移/Compose：未启动服务，Docker 不可用；没有业务 DDL。
- Flutter analyze/widget/Android/iOS 构建和真机：Flutter SDK/平台工具未就绪。
- 播放、语音、TURN、跨国网络与持续联测：业务尚未实现。

安全静态审阅：不提供默认密码/账户；空 MySQL 密码失败；生产拒绝 disabled 数据库；
日志过滤原始 URL 和凭证；无匿名 WS/视频代理/远程资源；开发数据库仅绑定回环。
控制面（全局 AGENTS/Skills/配置/插件/hooks）未改动，无需新会话加载检查。
