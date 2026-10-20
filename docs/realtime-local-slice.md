# 本地双人实时功能交付范围

2026-10-20，复杂度 XL，分为首页、实时协议与私聊、播放器协调、WebRTC 语音、双 Android 验收五个独立切片。不创建 OpenSpec（沿用此前已确认的工作方式）。

## 目标与验收

- 首页 Tab 点击无背景覆盖，仅指示器过渡；主视觉自动轮播，可手动滑动；后台/路由覆盖/减少动画时停止自动播放；继续观看收紧，增加电影、电视剧、动漫、短剧分区。
- 两个私有账号使用现有邀请加入同一房间；进入同看页后真实展示连接、成员、准备/缓冲状态。
- 服务端单进程权威播放：epoch/revision/generation，命令串行、幂等、冲突返回快照；手动暂停不被准备/重连自动播放覆盖；切片/seek 隔离迟到 ready；断线暂停，重连重新准备。
- 双方各自从同一 HTTP/HLS 地址拉流；本地文件与私有媒体 header 不上传共享。播放器沿用 Playra 会话和样式 token。
- 私聊按房间鉴权、MySQL 持久化、有界历史、clientMessageId 去重，发送失败可重试原条。
- 语音使用 flutter_webrtc 音频轨，服务端仅转发 SDP/ICE；默认不开麦。权限、静音、音量、断线、退出、后台释放均有明确处理。配置本地 coturn，为模拟器网络提供 TURN/TCP 回环转发。
- 真实 MySQL/WS 集成与两台独立雷电实例验证。声音质量、物理回声与公网 NAT 不由模拟器结果代替。

## 接口与边界

新增 `/api/v1/rooms/:roomId/realtime-ticket`（Bearer 鉴权、单次 30 秒票据）、`/realtime?ticket=...`（一次消费且不记录 URL）、房间内 WS 命令与权威快照、voice 信令。成员关闭/离开/移除后协调层主动断开旧连接。定期重新认证和心跳；同账号新连接取代旧连接。详见 contracts/websocket。

语音凭据使用有期限的 TURN REST HMAC；不将长期凭据写入 Dart 构建或日志。开发 TURN 只绑定宿主回环，ADB reverse 将两个测试实例转到同一个服务。生产环境配置 WSS 与自己的 TURN，禁止复用本地宽松回环配置。

## 允许修改与回滚

API realtime/chat/voice、新迁移、协调 routes/app、必要配置；Flutter realtime/voice/room watch、播放器控制代理、房间入口、首页与 DSTabs；Android 麦克风权限；依赖锁、契约、测试、脚本、交付文档。Playra vendor、既有鉴权语义、原始图稿、用户日常雷电实例不改。

基线：`.local/backup/2026-10-20-realtime/`，当前无 Git。逐文件哈希清单在交付时生成；数据库仅新增表，旧表与旧迁移不改。

## 官方实现依据

- https://github.com/fastify/fastify-websocket ：先注册插件，连接回调同步安装 message handler，鉴权在升级前执行。
- https://api.dart.dev/dart-io/WebSocket/connect.html ：移动端原生 WebSocket 与连接生命周期。
- https://pub.dev/packages/flutter_webrtc （本次核实 1.6.2+hotfix.4）、https://flutter-webrtc.org/docs/flutter-webrtc/api-docs/rtc-peerconnection/ ：音频轨、offer/answer、ICE、统计。
- https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf ：短期 TURN REST 凭据及本地中继配置。
