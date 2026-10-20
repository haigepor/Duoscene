# 本地数据库环境搭建记录

范围：按用户明确授权检查/配置 Docker Desktop、WSL2 和 MySQL 8.4，运行迁移及集成测试。
复杂度 L，涉及 Windows 用户环境、Docker 运行时与项目数据库验证。
本轮不改全局 AGENTS、Skills、Codex 配置、插件、hooks，不安装其他产品组件。

## 初始检查（2026-10-19）

- Windows 11 家庭版 64 位，build 26200；当前进程非管理员。
- WSL 2.7.11.0 已安装，默认 Ubuntu 为 WSL2；uname 验证内核运行正常。
- HypervisorPresent=true；不能根据启用 Hypervisor 后的 CPU 查询值误判 BIOS 虚拟化关闭。
- 未发现 Docker Desktop、docker CLI 或 MySQL 服务；3306 未发现监听。
- C 盘约剩 15GB，D 盘充足；Docker 数据盘计划使用 D:\DockerData。
- 初始无 .env、无 Git 仓库，项目业务代码与文档保持原样，除测试暴露的必要修复。

## 修改边界与恢复

允许：当前用户 Docker Desktop 安装/配置、新 Docker 专用数据目录、项目 .env、
infra/compose、必要的测试辅助脚本、测试暴露的后端修复和验证文档。
安装包/诊断放入被忽略的 .local/，密码仅放被忽略的 .env，不输出到对话。
Docker 使用 WSL2，保留既有 Ubuntu，不删除分发版或其他项目资源。

回退：停止本项目 Compose 服务时保留数据卷；按 Docker 官方卸载入口卸载本轮安装。
没有用户明确的数据销毁授权时，不删除命名卷/WSL分发版/数据盘，不运行 system prune。
若修改已有文件，先在 .local/backup/ 保存副本；新增数据库仅使用 duoscene 与独立 duoscene_test_local。

## 验收

Docker 客户端/引擎与 Compose 可用；MySQL 容器健康、绑定127.0.0.1、卷持久化；
应用库迁移六个版本APPLIED；真实MySQL集成套件与默认回归测试通过；记录实际版本与失败修复。

## 官方来源

- https://docs.docker.com/desktop/setup/install/windows-install/
- https://docs.docker.com/desktop/release-notes/
- https://learn.microsoft.com/en-us/windows/wsl/basic-commands
- https://docs.cloud.google.com/artifact-registry/docs/pull-cached-dockerhub-images

## 下载与网络处理

Docker Desktop 4.95.0（官方build 242831）安装包取自desktop.docker.com，
先取得官方SHA-256，下载结束后校验；安装时使用当前用户、WSL2、D:\DockerData数据盘。
WSL/Ubuntu已满足要求，不修改既有分发版或全局WSL资源限制。

Docker Hub直连超时，系统记录的本地代理未运行；Google管理的mirror.gcr.io可返回
mysql:8.4的OCI manifest。依据Google官方文档，在新建的用户级
`~/.docker/daemon.json`配置仅此官方缓存，不配置未知加速站、不关闭TLS验证。
该文件此前不存在；回退时可移除此项恢复Docker默认镜像源。

## 已完成的运行时配置

- Docker Desktop 4.95.0.242831，当前用户安装，官方Authenticode签名有效。
- 安装包SHA-256：73431db38491f770543880366228a23c993f84d1e8e045f56d83b8a98940cf76。
- Docker Engine 29.8.2，Linux/amd64；Docker Compose v5.6.0。
- WSL默认版本2，Docker专用分发版docker-desktop为Running/2；未重装Ubuntu。
- D:\DockerData已实际创建docker_data.vhdx/ext4.vhdx；未修改全局.wslconfig。
- 安装程序已添加当前用户Docker CLI PATH；已有终端若未刷新PATH，可重新打开终端。
- 后续检查发现已有原生mysqld监听3306，未停止或修改它；本项目.env改用3307。
- .env使用独立随机应用/root密码，值未输出；应用库duoscene，测试库duoscene_test_local。
- 首次空卷初始化时，mysql-init/001-test-database.sql创建隔离测试库并授权开发账号。

已保存项目文件备份：`.local/backup/2026-10-19-database-setup/`。
Docker Desktop卸载前需另行备份数据库；停止项目服务时不使用down -v，不销毁卷。

## DONE · MySQL与验收结果

- MySQL版本实际查询为8.4.11；镜像为Docker Official Image mysql:8.4，经Google官方缓存拉取。
- .env固定镜像：mysql:8.4@sha256:24989179f58856db763f418010c1169fecc944e3ec1ea7e921572d83eb070f70。
- 容器duoscene-dev-mysql-1健康运行，仅发布127.0.0.1:3307；容器内仍为3306。
- 字符集utf8mb4、排序utf8mb4_0900_ai_ci、全局时区+00:00，实测确认。
- 应用库duoscene和隔离库duoscene_test_local均完成六个APPLIED迁移。
- `npm run test:mysql`：7/7通过，0跳过，包含并发席位、邀请回滚、refresh重放/并发、真实HTTP。
- `npm test`：3个契约+17个后端默认测试，共20项通过；类型检查、构建通过。
- 使用真实数据库的Fastify inject readiness为200；没有常驻API监听进程。
- 强制重建本项目MySQL容器，ID由02fd246c83d1变为eff1f086cdad，保留同名mysql_data卷；
  重建后两库六个APPLIED版本均保留、容器重新健康。
- 临时测试用户与房间均清理，应用库与测试库users/rooms均为0；未创建真实用户/默认演示账号。
- 本轮没有修改apps/api业务源码，也没有更改既有原生MySQL、Ubuntu配置或生产资源。

## 文件变更与后续使用

- .env（忽略文件）：独立随机密码、3307端口、固定镜像；不提交、不展示密码。
- .gitignore、scripts/check-structure.mjs：排除.local安装包、备份与诊断产物。
- infra/compose/compose.dev.yaml：新增只读初始化脚本挂载。
- infra/compose/mysql-init/001-test-database.sql：仅创建开发测试库并授权。
- README及docs内相关状态：把真实数据库BLOCKED更新为实际验证结果，保留历史记录。
- 用户级~/.docker/daemon.json（此前不存在）：Google官方缓存配置；由安装程序更新用户PATH。

日常先启动Docker Desktop，然后在项目根运行：

```sh
docker compose --env-file .env -f infra/compose/compose.dev.yaml up -d mysql
npm run test:mysql
```

本机已有.env和数据卷，不重新生成密码或覆盖已有配置。新建的真实账户需要另行通过
`npm run account:create --workspace=@duoscene/api -- <username> <display-name>`隐藏输入密码创建。
本次目标已完成；移动端平台验证、生产部署、真实音视频联测仍属于后续工作。
