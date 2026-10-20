# 本地双人实时功能验证

2026-10-20。实现范围见 [realtime-local-slice.md](realtime-local-slice.md)，协议见 [WebSocket v1](../packages/contracts/websocket/README.md)，回滚与文件哈希见 [变更清单](realtime-change-manifest.json)。

## 已通过的验收

| 检查 | 结果 / 证据 |
|---|---|
| Flutter 静态与行为 | analyze 无问题；36 项主回归 + 1 项真实聊天客户端超时回归通过。包含轮播自动前进/非当前页暂停/减少动画、Tab 无点击覆盖色、继续观看高度不超过 76dp、18 页 320dp+160% 字体、既有登录/邀请/播放控制。`.local/realtime-analyze.log`、`.local/realtime-unit-final.log`、`.local/realtime-retry-green.log` |
| 原生全页面 | 18 页 + 24 状态 + 4 个吸顶/导航/播放器检查，46 个场景通过。`.local/realtime-ui-native.log`，`.local/screenshots/ui/` |
| API 单元与契约 | 3 个契约测试 + 19 个 API 测试通过，包括命令幂等、revision/epoch/generation、无额外字段、手动暂停优先、权限与鉴权。`.local/realtime-api-tests.log` |
| 真实 MySQL/WS | 8 项通过：迁移、席位竞争、邀请事务、凭据轮换、真实 WS 双用户控制、聊天 SQL 去重/恢复、断线、移除成员、退出撤销。额外验证 REST access 轮换后同一房间连接继续有效。`.local/realtime-mysql-final.log` |
| 两台 Android 完整链路 | 双方真实表单登录→创建房间→复制一次性邀请→另一台表单加入→2/2 席→进入真实同看页→独立 MP4 首帧→播放/10 秒 seek/1.5 倍速/暂停→真实双向私聊→麦克风/WebRTC→静音/解除静音→重连保持暂停与重新开麦确认→双方 HLS 换片→无异常退出。`.local/realtime-pair-result.json`、`.local/realtime-pair.log` |

两台雷电：DuosceneTest（127.0.0.1:5557）、新建 DuoscenePeer（emulator-5558），Android 14 / x64 / 390×780dp。用户日常 index 0 未启动或修改。Flutter 3.47.6，Dart 3.13.5。Playra 使用 OpenGL `gpu` 兼容路径。临时账号/房间已删除，临时凭据文件已移除。

双端媒体实际请求：MP4 2 次、HLS 清单 4 次、TS 分片 16 次。双方分别从回环夹具拉取；没有把单端或模拟进度当作同步。

## 语音证据与边界

使用 flutter_webrtc 1.6.2+hotfix.4 音频轨、Opus、DTLS-SRTP，强制 relay 策略；本地 coturn 4.6.3 提供 TURN/TCP。服务端仅转发信令，数据库不保存语音、SDP 或 ICE。仅在点击开启语音后申请真实 RECORD_AUDIO 并创建音频轨。

| 客户端 | WebRTC 状态 | outbound RTP 字节 | inbound RTP 字节 |
|---|---|---:|---:|
| 房主 | connected | 776 | 741 |
| 成员 | connected | 173 | 101 |

这些是检测到收发后的统计采样，证明双方音频轨和中继链路真实工作；不把模拟器静音输入/舒适噪声包当作已完成真人听感、回声或降噪质量验收。真机耳机、蓝牙、公共网络/NAT 和实际语音听感尚未测试。离开页面、断线、后台均释放麦克风；恢复连接后需要主动重新开启语音。

## 首页

分类 Tab 使用透明 overlay 和 NoSplash，仅保留指示器与文字颜色过渡。主视觉 6 秒轮换、480ms 过渡，可手势/圆点切换，离开主 Tab、后台或减少动画时停止自动前进。继续观看海报从 54×76 收为 40×52，默认总高约 68dp；大字体按内容扩展。

电影、电视剧、动漫、短剧四个横向片单，共 13 个本地设计片目。新增片目复用既有插画，明确属于设计片库，不伪造在线片源；真实同看使用双方可访问的 HTTP/HLS 视频地址。

## 实际发现并修复的回归

- 片单固定高度在小屏大字体下溢出：按海报与两行缩放文字计算高度，36 项回归通过。
- 远端倍速只作用底层，没有回写 Playra 的显示字段：同步更新 core.playerSpeed，双端 1.5 倍速验证通过。
- 语音退出与 WS 销毁竞争，向关闭的 StreamSink 发消息：先清除连接状态，通知失败仍释放资源；双端退出零异常。
- REST access 刷新使旧 WS token 无效：握手验 access，后续校验会话 ID、撤销、期限和账号状态；先复现失败，再真实 WS 回归通过。
- 消息重试时旧超时器会提前把新一次发送标为失败：重试取消旧计时器，确认/退出清理计时器；新增“重试有完整确认等待时间”的回归，先失败后通过。

初始失败日志保留在 `.local/realtime-pair-rate-failure.log`、`.local/realtime-pair-dispose-failure.log` 和 `.local/realtime-refresh-red.log`，没有隐藏失败或放宽断言。

## 本地启动与重跑

```powershell
# MySQL 使用既有本地配置；新增迁移 0007/0008 为加表，不改旧迁移。
./scripts/start-local-realtime.ps1 -Restart

. ./scripts/mobile-env.ps1
$env:DUOSCENE_GRADLE_OFFLINE='1'
node --env-file=.env --env-file=.local/voice.env scripts/test-realtime-pair.mjs
```

启动脚本生成未入库的 `.local/voice.env`，只重启已有 PID 记录且匹配 Duoscene 的 3000 端口进程；API 与 TURN 仅绑定宿主回环，再对两个测试设备做 ADB reverse。生产环境需要自己的 HTTPS/WSS、TURN 地址和部署配置，不能复用本地 coturn 的回环 peer 规则。

当前实现为单 API 进程房间 actor。没有接入多实例广播、公共媒体 Provider、共享本地文件上传或私有媒体请求头转发。开发预览图库继续保留明确预览标识；真实功能入口是登录后“观影邀请 → 邀请与房间 → 房间 → 打开播放器”，生成邀请后也可直接进入同看房间。

## 修改影响与回滚

- API：新增 realtime actor、timeline、chat SQL repository；auth 增加连接会话校验；app/room routes 协调成员变更；voice 可选配置及一次性票据。
- 数据库：0007_chat_messages、0008_room_playback；只加表。代码回滚后可以保留新增表；如需删除，先导出真实聊天/进度，禁止无备份 DROP。
- Flutter：新增 room_connection/room_playback/room_watch_page/room_voice；PlaybackSession 增加控制代理；房间与邀请入口接通；首页组件、片目、DSTabs、设置/帮助文案调整。影片音量只改 mpv，不与好友语音共用设备总音量。
- 原生/依赖：Android 录音与音频设置权限；flutter_webrtc；Fastify WebSocket、Ajv 与类型依赖；锁文件固定版本。没有修改 Playra vendor。
- 工具与文档：本地 TURN Compose、启动/双端验收脚本、协议 JSON Schema、验证与哈希清单。

基线位于 `D:/project/Duoscene/.local/backup/2026-10-20-realtime/`。回滚前对照清单检查文件当前哈希，避免覆盖后续人工修改。当前目录无 Git，采用逐文件备份比较。

## 普通应用交付

- APK：`D:/project/Duoscene/.local/artifacts/duoscene-realtime-local-debug.apk`（326,116,123 字节），普通 `lib/main.dart` 入口，无测试账号或测试夹具编译参数。
- SHA256：`efff1e13a5e61540fa1a1e487fd5badb65a2fed30307f815a9d10e823ebe184c`。
- `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:3000` 成功，`.local/realtime-build-final.log`。
- 本地开发库已应用 0007/0008；API 127.0.0.1:3000 与认证 TURN/TCP 均已启动。进程记录 `.local/realtime-api-process.json`；仅测试设备映射 3000/3478 回环端口。
- 普通 APK 安装到 DuosceneTest 与 DuoscenePeer，安装结果 Success，保留现有账号登录入口。完整双端测试图见 `.local/screenshots/realtime/owner.png`、`guest.png`。
- 构建仍有既有 Gradle/AGP/Kotlin 后续支持期限提示；本轮构建成功，没有顺带升级构建工具。

| 交付项 | 状态 |
|---|---|
| 首页与 token 交互调整 | DONE |
| 权威同步与持久私聊 | DONE |
| WebRTC 与本地 TURN | DONE |
| 双 Android 与原生回归 | DONE |
| 本地服务、迁移与调试包 | DONE |
| 真机听感和公网部署验收 | NEXT（可选后续，未包含在本轮本地验收） |
