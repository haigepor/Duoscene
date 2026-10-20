# chat

房间文字消息、clientMessageId 去重与有限历史。通过 rooms 公开权限接口鉴权；不读取 realtime 私有 Map。

当前仅定义模块职责，没有业务路由或占位成功响应。
落地时按需要拆分 routes/service/repository；SQL 只由本模块 repository 访问。
跨模块仅调用公开应用接口，不越界读写内存或表。
