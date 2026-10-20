# voice

同房间 WebRTC 信令授权与短期 TURN 凭据。只能通过 rooms 的公开查询判断成员；不拥有电影播放时间线。

当前仅定义模块职责，没有业务路由或占位成功响应。
落地时按需要拆分 routes/service/repository；SQL 只由本模块 repository 访问。
跨模块仅调用公开应用接口，不越界读写内存或表。
