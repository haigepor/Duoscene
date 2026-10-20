# 第一片本地操作

## 依赖与检查

```sh
npm ci
npm run typecheck
npm test
npm run build
```

根 package-lock.json 是唯一 npm 锁文件；项目默认 ignore-scripts=true，
当前依赖无需额外执行安装脚本。不要把生产凭据或账户密码放进命令行参数。
TypeScript 7 使用平台编译器，当前 Windows 已类型检查/构建成功。

## 已配置的本机环境

Docker Desktop 4.95.0、Engine 29.8.2、Compose v5.6.0，复用现有WSL 2.7.11。
MySQL 8.4.11运行于 `duoscene-dev-mysql-1`，仅绑定 `127.0.0.1:3307`；
原生3306服务保持原样。Docker数据盘位于D:\DockerData，命名卷duoscene-dev_mysql_data。
`.env`已有独立随机密码和固定镜像摘要，不把密码放进命令行或文档。

## 新环境准备 MySQL

复制 `.env.example` 为 `.env`，填写独立随机 MYSQL_PASSWORD、MYSQL_ROOT_PASSWORD；
设置 DATABASE_MODE=mysql。开发配置的数据库名/用户固定 duoscene，与 `.env` 保持一致。

```sh
docker compose --env-file .env -f infra/compose/compose.dev.yaml config --quiet
docker compose --env-file .env -f infra/compose/compose.dev.yaml up -d mysql
npm run db:migrate
```

首次空卷会通过 `mysql-init/001-test-database.sql` 自动创建隔离测试库并授权。
现有卷不会重复执行初始化脚本；本机已完成应用库和测试库迁移，不覆盖现有.env或删除卷重建。
应用不自动迁移；生产需先备份，再用专门迁移账户执行 DDL，应用账户只授予所需 DML。

## 管理员私有账户

```sh
npm run account:create --workspace=@duoscene/api -- alice "Alice"
npm run account:create --workspace=@duoscene/api -- bob "Bob"
npm run account:disable --workspace=@duoscene/api -- alice
npm run sessions:prune --workspace=@duoscene/api
```

创建命令需要交互 TTY，密码隐藏输入，12–128 字符；没有默认密码，不通过 argv 传密码。
请只创建所需的两名真实用户。注销撤销当前会话，禁用撤销全部会话；关闭房间不删除成员身份。
过期会话清理建议每天由运维手动或日后部署任务执行，本轮没有创建系统定时任务。

## 真实数据库测试

本机已有隔离库 `duoscene_test_local`，集成测试7项通过，无跳过。
若使用旧卷或其他 `duoscene_test_*` 名称，需预建库并授予测试连接账户 DDL/DML 权限；
不要授予应用公开接口建库权限。需要手动初始化时，可进入容器交互控制台执行：

```sql
CREATE DATABASE duoscene_test_local CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
GRANT ALL PRIVILEGES ON duoscene_test_local.* TO 'duoscene'@'%';
```

以上权限只用于隔离开发环境，不能照搬生产。`.env` 中 MYSQL_DATABASE 仍指向应用库；
独立 DUOSCENE_TEST_DATABASE 指向测试库，测试入口会覆盖连接的库名。

```sh
npm run test:mysql
```

套件验证迁移重入、同邀请码/不同邀请码争抢席位、邀请过期/撤销/事务回滚、
refresh 轮换/重放/并发、真实 HTTP、禁用与注销。
仅清理其新建的 roomId/userId，不 DROP DATABASE，不清空已有用户表。
测试表与迁移记录保留以便重跑；请勿指向任何已有真实业务数据的库。

## 后续运行

```sh
npm run dev:api
```

监听默认 127.0.0.1:3000。移动端运行方法见 apps/mobile/README.md，已完成真实 HTTP 和 Android 模拟器联调。
生产 HTTPS/WSS、代理可信地址与部署 secret 由后续切片接入；测试服务器结束后关闭。

日常使用先打开Docker Desktop，再运行Compose up；安装器已配置用户PATH，旧终端找不到docker时重新打开终端。
停止数据库使用Compose stop或不带-v的down。MySQL数据保存在命名卷，已验证容器重建后迁移记录保留。
详细搭建、下载来源、镜像摘要和文件备份见database-environment-setup.md。
