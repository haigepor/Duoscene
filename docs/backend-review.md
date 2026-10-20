# 第一片后端审阅

范围：app、配置、数据库接入、commands、auth/rooms、六个迁移、REST 契约与测试。
初次审阅依据代码、Fastify inject和编译；后续新增MySQL 8.4.11真实数据库/并发证据，7项全部通过。

| 轴 | 状态 | 结论与边界 |
| --- | --- | --- |
| Correctness | PASS（代码/单测） | 密码、token、席位和房主退出策略有可执行测试；SQL结果仍需真实库验收 |
| API contract | PASS（已实现子集） | 请求/成功结果直接引用语言中立Schema，拒绝额外字段；OpenAPI含错误/鉴权/分页 |
| Data integrity | PASS（当前切片） | 六个DDL实际执行，FK失败事务回滚/邀请用量/两席位约束通过真实测试 |
| Transactions/concurrency | PASS（当前切片） | 同/不同邀请码争位、重复加入、并发refresh及重放撤销均通过真实MySQL套件 |
| Security | PASS（当前代码） | 无公开注册/默认密码；异步scrypt、有界并行、token哈希、访问控制、限流、安全响应；未部署 |
| Performance | PARTIAL | 连接/队列/哈希并行有上限；尚未压测，连接池排队和MySQL锁等待延迟需实测 |
| Reliability | PARTIAL | 迁移中断保留APPLYING/FAILED、readiness校验版本；没有验证备份恢复或网络故障 |
| Observability | PASS（最小范围） | requestId、状态码日志；屏蔽原始URL/凭据/SQL；未来需安全事件与同步指标 |
| Tests/config | PARTIAL | 默认20项和真实MySQL7项通过，类型/构建/审计通过；Flutter仍无运行证据 |

## 已处理的问题

- 开发骨架把 `/api/v1/rooms` 当未知路由的旧测试，随业务端点接入改为真正未知路径；
  保留404安全响应断言，另加未配置数据库的503断言。
- refresh重放分支返回事务结果后再抛401，避免rollback把应有的会话撤销撤回。
- 迁移不使用虚假的DDL全局事务回滚；每个文件一个语句，单连接持有迁移锁。
- 对重复/超额输入采取明确拒绝；响应Schema只输出公开用户字段。

## 交付限制

第一片数据库suite现已通过，测试临时账户/房间已清理，未创建真实用户或默认演示账号。
容器重建后两库的六个APPLIED迁移仍在；后续可进入移动端/WS切片。
