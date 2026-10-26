# 语言中立契约

- `openapi/`：健康检查、私有账户与房间 REST 契约；业务请求/结果来自 api-v1.schema.json，API 直接读取。
- `websocket/`：已实现的房间协议、控制命令 Schema、Provider 选片与起点交接。
- `fixtures/`：共享合法/非法消息；测试夹具不代表线上观测。
- `test/`：JSON Schema 验证入口，覆盖登录、加入、URL/Provider 选片与边界，并核对 WS Schema 与服务端验证器一致。

Flutter 不导入 TypeScript 类型。首版对少量类型分别维护 Dart/TypeScript 映射，
新增业务消息时同时补 JSON Schema、两端模型和共享 fixture 测试。
REST Schema 由 API 直接加载；WS 命令 Schema 与运行时定义由测试核对。Dart 模型和媒体描述仍手工维护，客户端测试覆盖交接、独立解析与迟到响应隔离。
