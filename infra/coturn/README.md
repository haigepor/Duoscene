# coturn 入口预留

后续签发短期 TURN 凭据，shared secret 由服务器运行时注入，不写入 App 或仓库。
默认规划 UDP/TCP 3478、TLS TCP 5349、中继 UDP 49160–49200；
最终端口范围与 external-ip 需按服务器 NAT/防火墙实测确定。

当前不启动 coturn、不签发凭据、不存放伪造证书或 secret。
实施时必须启用认证、拒绝中继到私网/回环/链路本地地址、限制配额，
分别验证 P2P、强制 relay、TCP/TLS 回退和语音双向连通。
