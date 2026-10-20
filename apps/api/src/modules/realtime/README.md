# realtime

标准 WebSocket 接入、短时一次性票据、连接接管、房间命令队列、播放权威状态和快照。未来使用 @fastify/websocket；当前未引入也未开放 WS 路由。

当前仅定义模块职责，没有业务路由或占位成功响应。
落地时按需要拆分 routes/service/repository；SQL 只由本模块 repository 访问。
跨模块仅调用公开应用接口，不越界读写内存或表。
