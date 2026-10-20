# HTTPS/WSS 入口预留

后续生产 Caddy 仅公开 TCP 80/443，反向代理到内网 API:3000；
MySQL 不公开，API 不通过另一个公网端口旁路暴露。

域名、证书邮箱与实际 VPS 尚未提供，因此不放入看似可部署的占位配置。
访问日志须屏蔽票据、签名 URL、Authorization 和 Cookie。
TURN 的 UDP/中继端口独立开放，不通过普通 HTTPS 反向代理承载。
