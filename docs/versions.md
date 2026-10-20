# 版本与来源

核验日期：2026-10-19（Asia/Singapore）。首轮仅声明依赖；继续推进后已安装 npm 包并生成锁文件。
下列是本次基线，不承诺今后一直为最新版。

| 项目 | 本轮决定 | 证据/边界 |
| --- | --- | --- |
| Node.js | 24 LTS，推荐 24.22.0；允许 >=24.14.0 <25 | 官方 release 页面列 24 LTS；本机 24.14.0 可跑无依赖检查 |
| npm | 11 | 本机 11.9.0，采用 npm workspace，不引入额外包管理器 |
| Fastify | 5.12.7 | 官方文档当前 v5；npm registry 版本与官方仓库元数据已读取 |
| mysql2 | 3.24.6 | 官方 promise pool 文档与 registry 已读取，真实 MySQL 集成已通过 |
| TypeScript | 7.0.2 | 已实际安装，类型检查和构建通过 |
| @types/node | 24.19.2 | registry 的 24.x 版本；与 Node 24 主版本匹配 |
| Ajv | 8.20.0 | registry 元数据；仅作为契约测试开发依赖 |
| @fastify/rate-limit | 11.2.1 | 已安装；官方兼容表 >=10.x 配合 Fastify 5；限流边界测试通过 |
| MySQL | 8.4.11 LTS | 容器内查询确认；本机.env固定实际镜像digest，7项真实集成测试通过 |
| Docker Desktop / Engine / Compose | 4.95.0 / 29.8.2 / v5.6.0 | 当前用户安装，官方安装包SHA-256/签名验证；WSL2引擎实际运行 |
| WSL | 2.7.11.0 | 现有Ubuntu为WSL2，新增docker-desktop为WSL2；未重装或修改全局内存限制 |
| Flutter/Dart | 项目 3.47.6 / Dart 3.13.5 | 独立 SDK 与官方 3.47.6 tag 一致；原 3.38.6 保留，全局用户 PATH 不变；播放器实际证据见 player-verification.md |
| http / flutter_secure_storage | 1.6.0 / 11.2.0 | pub.dev 官方包与插件源码已读取，实际 pub get 生成 pubspec.lock |
| Android / JDK | SDK 36 / Temurin 21.0.12.1+1 | SDK 复用现有安装；独立 JDK 官方资产 SHA-256 校验通过，保留系统 Oracle 25 |
| @fastify/websocket | 暂不加入依赖 | 官方仓库与 registry 查询到 11.3.4；鉴权/WS 切片再核验锁定 |
| media_kit / media_kit_video | 1.1.11 / 1.2.5 固定 fork | Predidit/media-kit 803c4a27912091db6f839d48d1b984a0d9f588c7，本地源码随仓库保存；原生包由 hook 校验，Android 最低 API 28 |
| flutter_webrtc | 后续语音切片 | 尚未引入；与播放器的音频会话兼容性仍需双平台真机验证 |

Flutter 版本清单的直连请求曾返回 NoSuchKey，未凭该失败结果推断当前 stable 版本。
移动端 pubspec.lock 已生成，后续使用 flutter pub get --enforce-lockfile。
根 package-lock.json 已由真实 npm install 生成，后续用 npm ci；.npmrc 禁用安装脚本。

## 官方资料

- [Node.js 支持周期与版本](https://nodejs.org/en/about/previous-releases)
- [Fastify TypeScript](https://fastify.dev/docs/latest/Reference/TypeScript/)
- [Fastify app factory / inject 测试](https://fastify.dev/docs/latest/Guides/Testing/)
- [Fastify WebSocket 官方仓库](https://github.com/fastify/fastify-websocket)
- [mysql2 Promise 与连接池](https://sidorares.github.io/node-mysql2/docs)
- [MySQL LTS 模型](https://dev.mysql.com/doc/refman/8.4/en/mysql-releases.html)
- [Flutter 官方工程生成](https://docs.flutter.dev/reference/create-new-app)
- [MaterialApp](https://api.flutter.dev/flutter/material/MaterialApp-class.html)
- [Flutter SDK archive](https://docs.flutter.dev/install/archive)
- [Fastify rate-limit 官方兼容性](https://github.com/fastify/fastify-rate-limit#compatibility)
- [Node 24 scrypt](https://nodejs.org/docs/latest-v24.x/api/crypto.html#cryptoscryptpassword-salt-keylen-options-callback)
- [OWASP 密码存储参数](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)

包版本来源为各官方项目发布到 npm registry 的 metadata；本轮另外实际完成 npm 安装、
类型编译、默认测试和已知漏洞审计；后续已完成 MySQL 验收和 Flutter HTTP 联调，原生平台证据见 mobile-verification.md。
