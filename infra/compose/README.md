# Compose 入口

`compose.dev.yaml` 仅包含开发 MySQL，端口只绑定 VPS/开发机本地回环地址。
不会创建业务表或真实用户账户，也不会启动 API、Caddy、coturn。
首次空卷的mysql-init脚本会创建隔离测试库并为开发账号授权；业务表由db:migrate/集成测试迁移。
`mysql:8.4` 是开发系列标签；部署前必须固定经核验的 patch/digest。

后续具备 Docker 后，从仓库根目录手动执行：

```sh
docker compose --env-file .env -f infra/compose/compose.dev.yaml config --quiet
docker compose --env-file .env -f infra/compose/compose.dev.yaml up -d mysql
```

先填写 `.env` 中独立随机的 MYSQL_PASSWORD 与 MYSQL_ROOT_PASSWORD。
API 本机开发使用 `.env` 的 `MYSQL_HOST=127.0.0.1`；未来容器内使用服务名 `mysql`。
修改密码环境变量不会修改已初始化卷中的 MySQL 密码，需要通过数据库账户管理流程变更。
卷只存数据库文件；执行 down 时不要带 `-v`，除非明确要销毁数据库。

开发健康检查仅判断进程响应；API readiness 另外通过应用账号执行 SELECT 1。
生产配置需补 API 内网、反向代理、secret 文件、备份与恢复测试后单独交付。
本机已使用Docker Desktop运行MySQL 8.4.11，通过真实数据库集成测试。
因原生3306已被占用，本机.env的MYSQL_PORT设为3307；Compose始终只绑定127.0.0.1。
本机.env已固定实际拉取镜像摘要；版本与数据卷保留验证见docs/database-environment-setup.md。
