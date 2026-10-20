-- 仅用于本地开发：应用库/账号由官方 MySQL entrypoint 创建，此处单独创建隔离测试库。
CREATE DATABASE IF NOT EXISTS duoscene_test_local CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
GRANT ALL PRIVILEGES ON duoscene_test_local.* TO 'duoscene'@'%';
