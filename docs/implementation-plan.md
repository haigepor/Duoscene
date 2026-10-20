# 实施计划

本轮按用户最新要求先搭建结构与骨架；附件中的完整数据库/协议设计仍需后续完成。
第一片后端及本地 Docker/WSL/MySQL 环境已验证；不创建 OpenSpec，不部署生产。
当前移动端切片仅为开发联调启动本地 API，测试服务器结束后关闭。
已运行/未运行的命令以 verification.md 为准。

## DONE · 0：本轮骨架

输入：已确认主栈与空工作目录。输出：API factory/server、Flutter 入口、模块边界、
最小 health/error 契约、MySQL 开发 Compose、无依赖检查与测试入口。
文件清单和回退依据见 architecture.md。

## DONE · 1：后端账户/房间与真实 MySQL 验收

- 输入：本轮骨架、审阅后的用户/会话/房间/邀请数据设计。
- 文件：根 package-lock.json；api 的 migrations、auth、rooms、plugins；mobile auth/rooms；contracts。
- 输出：MySQL 实际迁移、一次管理员初始化（无默认密码）、账户轮换事务、两席位邀请加入。
- 命令：`npm install`、`npm run typecheck`、`npm test`、`npm run build`；Docker MySQL 集成测试。
- 验收：并发争最后席位不超员；邀请码消费和成员插入同事务；禁用/注销立即拒绝新请求。
- 依赖：Docker、可用 MySQL；执行器需考虑 DDL 隐式提交，迁移失败不能谎称事务已全部回滚。
- DONE：依赖锁、六个 DDL、迁移器、管理员命令、私有会话/邀请/成员后端和 OpenAPI。
- DONE：20 个默认测试、类型检查、构建、依赖审计。
- DONE：Docker Desktop/WSL2/MySQL 8.4.11已配置；真实数据库7项通过，迁移和容器重建后的数据保留通过。
- DONE：Flutter auth/rooms 页面已实现并完成 HTTP 真实后端联调；平台证据见 mobile-verification.md。

## DONE · 1.1：移动端账户与房间

- Flutter、Android SDK、JDK 的本机路径已配置；原生工程由官方生成器创建。
- 登录、会话恢复/轮换/注销、房间分页列表/创建、邀请码加入、成员详情、邀请生成/复制/撤销。
- flutter analyze、12 项单元/widget 测试、真实 Flutter HTTP + MySQL 流程通过。
- Android 构建/模拟器与 iOS 平台限制以 mobile-verification.md 为准，不能把 HTTP 测试视为原生验证。

## DONE · 1.2：Playra 播放内核、功能与页面

- 固定并迁入 Playra 当前 media-kit 分支、26 个控制/控件/服务源文件、GLSL 和许可证记录。
- 接通房间详情、网络/本地媒体、MP4/HLS、请求头、基本控制、手势/全屏/锁定、比例/音轨/字幕、截图、后台和画中画入口。
- Flutter 19 项测试、完整分析、官方 Android 9 模拟器与雷电 Android 14 原生媒体测试通过。
- 雷电使用 GPU/OpenGL；补丁修复固定分支的 Surface 销毁竞争。平台证据和未覆盖范围见 player-verification.md。
- 双人同步未混入单机播放器验收，按下一片独立推进。

## NEXT · 2：双客户端同步协议

- 输入：成员鉴权、审阅过的完整消息表/Schema/状态机。
- 文件：api realtime/rooms、contracts/websocket 与 fixtures、mobile/core。
- 输出：@fastify/websocket、一次性票据、设备接管、串行房间队列、epoch/revision/generation、校时。
- 命令：`npm run test:contracts`、`npm test`；新增可注入时钟的双客户端协议测试后记录其脚本。
- 验收：同 revision 同时 seek 一次成功一次冲突；重复 commandId 一次生效；旧 ready/连接拒绝。
- 重启以新 epoch 暂停恢复；slow Provider 返回重新校验 generation；心跳不等待媒体解析。

## NEXT · 3：同步播放器与共同等待

- 单机 Playra 播放器已迁入，片源解析排除。继续在现有 PlaybackSession.applyTarget 和 UI 回调边界接入权威快照。
- 输入：标准测试视频、同步契约、Flutter SDK、Android/iOS 开发工具。
- 文件：mobile playback、rooms、app、core；api realtime/checkpoints；contracts。
- 输出：media_kit 适配、ready/缓冲协同、漂移纠正、前后台和检查点恢复。
- 命令：在 mobile 执行 `flutter analyze`、`flutter test`；再运行专门的双机 integration_test。
- 验收：缓冲后手动暂停不自动恢复；过时加载回调无效；断线不回放旧控制意图。
- 真机测量同步误差，纠偏围绕用户倍速；不承诺逐帧同步或异常退出零进度丢失。

## NEXT · 4：WebRTC 语音与 TURN

- 输入：flutter_webrtc、coturn 环境、双平台真机和播放器音频基线。
- 文件：mobile voice/app 平台适配、api voice、infra/coturn、contracts。
- 输出：确定性协商角色、negotiationId、连接代际过滤、短期 TURN 凭据、音轨清理。
- 命令：Flutter unit/integration 测试及双机 force-relay 实验；具体入口在实现后固化。
- 验收：同时 offer、旧 ICE、麦克风拒权、独立音量、蓝牙/来电/锁屏与播放器音频共存。
- 不把模拟 PeerConnection 或插件平台列表作为真机兼容性证据。

## NEXT · 5：真实 Provider、聊天与观看历史

- 输入：脱敏接口文档与真实地区约束；测试夹具和真实接口分别命名。
- 文件：api media/chat/history、mobile 对应功能、contracts、数据库迁移。
- 输出：搜索/详情/集数/解析/刷新、时间线校验、有限聊天、历史更新。
- 命令：已有 npm/Flutter 测试入口，并增加真实 MySQL 事务测试。
- 验收：不同用户独立 URL 对应同剪辑；刷新失败有限重试；错片不接旧时间线；聊天重试去重。
- 出站 Provider 白名单、重定向/DNS 的 SSRF 边界设计完成后才允许用户直链。

## NEXT · 6：生产部署与持续联测

- 输入：域名/VPS、双方网络、平台签名、全部前序切片验收。
- 文件：infra 生产 Compose/Caddy/coturn、备份恢复脚本、deployment 文档。
- 输出：固定镜像 patch/digest、HTTPS/WSS、内网 MySQL、secret 注入、日志轮转、升级/恢复。
- 命令：生产配置静态验证、备份恢复演练及真实设备 60–120 分钟持续播放/语音。
- 验收：跨国网络 RTT/丢包、TURN 成功率、漂移/重连/资源增长可追踪；实际恢复备份。
- 单 VPS 先按 2vCPU/4GB 预算，未经压测；必要时单独扩 TURN，首版不引入集群。
