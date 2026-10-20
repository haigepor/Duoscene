# 语言中立契约

- `openapi/`：健康检查、私有账户与房间 REST 契约；业务请求/结果来自 api-v1.schema.json，API 直接读取。
- `websocket/`：预留协议版本与同步设计边界，尚未开放 WS 端点。
- `fixtures/`：共享合法/非法消息；测试夹具不代表线上观测。
- `test/`：已可执行的 JSON Schema 验证入口，包含合法/非法登录和加入夹具。

Flutter 不导入 TypeScript 类型。首版对少量类型分别维护 Dart/TypeScript 映射，
新增业务消息时同时补 JSON Schema、两端模型和共享 fixture 测试。
目前健康检查不被 App 消费，尚无双方业务模型和跨语言测试。
不要把文档中的拟定消息字段当成已实现协议。
