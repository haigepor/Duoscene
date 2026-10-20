# 第一片实施范围

用户在骨架交付后要求继续推进。本轮允许安装项目 npm 依赖，创建本地锁文件，
实现并验证后端私有账户/房间 API、迁移和协议契约；不安装 Flutter/Docker 等全局工具，
不部署、不创建远程资源、不改移动页面或全局控制面。

初始状态：上一轮的 63 个文件存在，仍无 Git 仓库；没有可用于 diff 的提交基线。
允许路径：根 package.json/package-lock.json/.env.example/.gitignore/.npmrc；
apps/api/**；packages/contracts/**；scripts/check-structure.mjs；README.md；docs/**。
infra 开发配置仅在连接测试所需时调整；mobile/** 保持不变。

成功标准：项目可类型检查/构建；密码、token、鉴权和输入验证有测试；
真实 MySQL 迁移/事务具备可执行集成测试入口；环境缺少数据库时明确标记未验证。
房间上限受持久席位约束、房间行锁和事务共同保护；禁止内存在线状态决定席位。

修改清单按类别见 architecture.md 的“第一片新增路径与影响”；根/API脚本、app接线、
database插件、旧app测试、contracts索引与文档也已更新。所有 SQL 执行前需备份。
无Git/文件快照，不能声称具备一键代码回退；需要依据初始骨架记录人工审阅恢复，新增文件逐项移除。
没有数据库时不运行迁移；不使用 DROP TABLE 自动回退。安装产物 node_modules 可重建，
本轮不执行递归删除。下一轮先建立正式 Git 基线再继续扩大范围。
