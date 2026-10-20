# MySQL 迁移入口

目标 MySQL 8.4 LTS、InnoDB、utf8mb4；数据库名 `duoscene`。
已提供六个单语句迁移：users、auth_sessions、auth_refresh_tokens、rooms、room_members、room_invites。
数据字典、外键策略与锁顺序见 `docs/database.md`。六个迁移已在本机MySQL 8.4.11执行，应用库/隔离测试库均APPLIED。

采用 `0001_<purpose>.sql` 不可变迁移，每文件一个 DDL；执行器已提供：

1. 单执行者锁、版本表、校验和与失败记录。
2. utf8mb4 排序规则、UUID 外键类型一致、UTC DATETIME(3) 和毫秒进度。
3. MySQL DDL 隐式提交意味着不能承诺整个迁移事务回滚。
4. 破坏性变更先备份并实测恢复；回退优先兼容性修复/恢复备份。

从根目录执行 `npm run db:migrate`。必须先填写 `.env`，设置 DATABASE_MODE=mysql，
由管理员预建数据库并授权；应用启动不自动执行迁移。
readiness 要求全部预期版本 APPLIED，失败/中断版本停止待人工审阅。

没有 down 脚本；账户和房间有真实数据后，删表不是安全的默认回退。
集成测试命令 `npm run test:mysql`，仅允许显式指定的 `duoscene_test_*` 隔离库。
