# auth

已实现本地 CLI 创建/禁用私有账户，HTTP 登录、refresh 轮换、当前用户与注销。
公开注册没有路由；不提供默认账号或明文密码。参数与严格重放策略见 docs/api.md。

routes/service/repository 已分离，security 管理 scrypt 和随机 token。
持久会话每次鉴权查库；数据库事务验收依赖真实 MySQL 套件。
跨模块仅调用公开应用接口，不越界读写内存或表。
