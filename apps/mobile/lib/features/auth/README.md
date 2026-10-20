# auth

已实现私有登录、会话恢复、并发 401 单次轮换和退出。token_store.dart 通过系统安全存储保存 refresh token；access token 仅在内存。

session.dart 接受可替换的 HTTP 客户端与存储，测试覆盖轮换竞态和安全存储失败。
依赖方向为 app -> features -> core；不持有房间或播放器状态。
