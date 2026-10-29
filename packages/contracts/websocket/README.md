# WebSocket 协议 v1（本地实现）

实现入口 `apps/api/src/modules/realtime/`，移动端 `features/realtime/`。单 Fastify 进程；两个持久房间席位；不提供匿名 echo。服务端 tick 使用单调时间基点。

控制消息 Schema 导出自 `timeline.ts` 的 `commandSchemas`，每个动作独立且 additionalProperties=false：

- roomEpoch：进程恢复运行态时的新 UUID。
- revision：同 epoch 内权威播放状态版本。
- playbackGeneration：换片/seek 后隔离旧 ready 和异步加载结果。
- connectionId/连接代际：隔离同账号旧设备连接。
- commandId：同 epoch 有界去重，先去重再判断 expectedRevision。

## 握手与连接

Bearer POST `/api/v1/rooms/:roomId/realtime-ticket` → `{data:{ticket,expiresIn:30},requestId}`。票据仅内存保存、30 秒、单次消费；升级前重新核验原 session 与成员。WS `/realtime?ticket=...` 不记录原始 URL。相同账号新连接替换旧连接（4001）；断线不释放持久席位。10 秒 ping/pong 并重验权限；慢消费者或消息洪泛断开。客户端上限退避 8 秒重连并重新申请票据。

首次发送 `snapshot`、`history`、`welcome`。welcome 包含 protocolVersion=1、connectionId/userId/iceServers/relayOnly，TURN REST 凭据 4 小时有效。聊天室只支持当前授权房间；没有跨房间 target。建立连接后按 sessionId 校验会话撤销、30 天期限与账户状态，正常 REST access 轮换不会中断房间；退出或禁用账号会在下一条消息或 10 秒心跳内关闭连接。

## 播放状态

snapshot：`{type,epoch,revision,generation,media,rate,playing,wanted,positionMs,serverTime,ready,room,peers}`。

`media` 支持两种互斥形态：

- 既有地址形态：`{uri,identity,title,hls}`，仅接受无 userInfo/fragment 的 HTTP(S) 地址，不共享本地文件或私有 header。
- 片目形态：`{provider:'whisklet',filmId,episode,lineCode?,identity,title}`。filmId 为 `whisklet:<正整数>`，最长 80；episode 为 1–100000；lineCode 最长 80，不含空白或控制字符。双方分别解析自己的短期 URL 和媒体请求头，这些传输资料不进入房间快照。明确指定线路时，不接受静默回退到另一线路。

两端独立拉流，服务端不代理视频。`peers=[{userId,displayName,connectionId,voice}]`；`ready` 按 userId 标记。room 为既有 REST 房间公开形态。片目形态要求双方使用支持该形态的客户端；既有 URL 命令保持兼容。

控制公共字段：`{type,commandId,epoch,expectedRevision}`；media 命令携带 media，并可选 positionMs，未提供时从 0 开始；seek 必须提供 positionMs；rate 必须提供 rate；play/pause 无附加字段。positionMs 0–86400000，rate .25–8，媒体 URL 最长 4096。换片与起点通过一条 media 命令原子提交，初始为暂停并重置双方 ready。`ack={type:'ack',commandId}`；错误返回 commandId、code 和最新已提交 snapshot，不静默覆盖新状态。同 epoch 最近 512 条用户命令去重，先去重再比 revision。

ready：`{type:'ready',epoch,generation,ready:boolean}`。换片或 seek 增加 generation 且重置双方 ready，旧 generation 的 ready 忽略。服务端仅在 media 存在、在线 2 人、双方 ready、wanted=true 时播放。缓冲暂停保留 wanted；手动 pause 清除 wanted；断线清除 wanted，重连不自动播放。OWNER_ONLY 模式仅允许房主控制。

每个房间串行处理事件，每秒广播快照校正漂移；客户端保留最新快照，按本地接收后的经过时间投影目标，漂移超过 1200ms 或新 generation 强制定位。初次定位等待媒体具备有效时长，成功应用后才声明 ready。

播放命令先在候选时间线上计算，再保存 MySQL；保存成功后才替换权威态、广播和 ack。保存失败时保留原权威态及去重记录，同一 commandId 可重试。播放过程中每 5 秒保存进度检查点，ready 变化、断线和服务关闭也保存当前位置；检查点失败保持 dirty 并重试，未保存的房间不清理。正常断线保存冻结位置；异常进程终止最多恢复至最近一次成功检查点，数据库持续故障期间不能承诺进度无损。恢复使用新 epoch，默认暂停且重新准备。

个人邀请先初始化房间媒体和起点，再生成邀请码；重试遇到已有媒体时保留服务端状态。个人播放仅暂停，房间仍拥有独立播放会话。

## 私聊

发送：`{type:'chat',clientMessageId,text}`；clientMessageId 为 1–80 ASCII 安全字符，text 为 1–2000 字符。广播 `{type:'chat',message:{id,userId,clientMessageId,text,displayName,createdAt}}`。房间/用户/clientMessageId 唯一键保证重试不重复；服务端返回已持久化原条，不能以重试替换原文。

初次与分页：`{type:'history',before:<数字id字符串>}` → `{type:'history',messages,initial}`，每页最多 50，客户端最多保留 300 条。界面已发送代表持久化确认，不冒充已读。断线未确认条变为失败，用户重试保留 clientMessageId。

## 语音

`{type:'voice',enabled:boolean}` 声明进入/退出；默认关闭，不主动获取麦克风。`{type:'signal',target:<connectionId>,callId,kind:'offer'|'answer'|'ice',data}` 仅转给同房且双方开启语音的当前连接。offer 由房主创建避免 glare；客户端按 callId/connectionId 隔离迟到 ICE，等待 remoteDescription 后添加。SDP/ICE 只短暂转发，不落库。麦克风静音切换本地 track.enabled，仍接收对方；关闭语音/断线/后台/退出停止并释放音频轨与 PeerConnection。

音频使用 WebRTC DTLS-SRTP 与 Opus，WS 不传音频帧。本地 coturn 配置仅接受回环中继，两个模拟器通过 ADB reverse TURN/TCP 接入；公网部署需独立 TURN 配置和 WSS，不使用该开发配置。
