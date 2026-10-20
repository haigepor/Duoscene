# 移动端基础设施

当前提供 HTTP JSON 客户端、模型解析、共享错误和布局；安全凭证适配归 auth 所有。
WebSocket 与单调时钟校时尚未实现。

- 只能依赖 Dart、Flutter 和明确引入的平台库；不能依赖 features。
- 不在这里放房间状态机或 WebRTC 协商状态。
- 长期凭证不得通过普通偏好存储、URL、日志或 dart-define 打包进入 App。
- API 地址通过 API_BASE_URL 指定；真机 localhost 指向手机自身，联调方法见移动端 README。
