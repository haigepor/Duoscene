# media

第三方 Provider 适配和每名用户独立解析地址。不得存储长期签名 URL 或转发视频字节；Provider 尚未接入。

当前仅定义模块职责，没有业务路由或占位成功响应。
落地时按需要拆分 routes/service/repository；SQL 只由本模块 repository 访问。
跨模块仅调用公开应用接口，不越界读写内存或表。
