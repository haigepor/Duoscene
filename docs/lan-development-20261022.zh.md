# 同一 Wi-Fi 调试与登录

## 已验证的配置

- 电脑：`192.168.0.4:3000`，手机：`192.168.0.3`，两者连接同一局域网。
- 测试账号：`test123`，密码：`test123`。账号已存在于本机独立测试库；没有修改正式注册或认证规则。
- API 监听 `0.0.0.0:3000`；MySQL 仍仅监听 `127.0.0.1:33307`。
- 移除 `adb reverse tcp:3000` 后，真机使用 LAN APK 登录成功并进入原有首页，收藏和观看记录保留。

## 每次启动

在此电脑以管理员身份运行 `scripts/start-lan.cmd`。不需要连接 USB、安装 ADB 或设置端口反向代理。脚本自动选择有网关的物理私网网卡；存在多张候选网卡时会拒绝猜测，可使用 PowerShell 7.4+ 显式指定：

```powershell
pwsh -File .\scripts\start-lan.ps1 -Address 192.168.0.4
```

脚本使用本机已有的 `.local/test-account` 独立测试服务和便携 Node；它不是新电脑的数据库安装程序。仅验证本机服务所属进程后复用或重启，不会结束其他占用端口的程序，不会重新初始化数据库。

防火墙规则 `Duoscene-LAN-API-3000` 仅放行该 Node 程序、所选网卡、本机指定 IPv4、同子网 TCP 3000。不会关闭 Windows 防火墙，也不会把整个 Public 网络修改成 Private。

## 安装包与地址变化

安装 `output/android/duoscene-lan-arm64-debug.apk`。旧包内置 `127.0.0.1`，那是手机自身，不是电脑，因此只改服务监听地址仍然无法登录。LAN 包同时设置了 API 地址、调试态私网检查及 Android 对该地址的明文 HTTP 许可。

电脑 IP 变化后，用管理员 PowerShell 7.4+ 重新构建并覆盖安装：

```powershell
pwsh -File .\scripts\build-lan-apk.ps1
```

构建地址保存在忽略的 `.local/lan/defines.json`，交付包配置与 SHA-256 保存在 `output/android/lan-build-info.json`。建议在路由器中为电脑保留 DHCP 地址。APK 适用于 arm64 Android 设备；不同 ABI 需要单独构建。

性能测试推荐使用 AOT Profile，而不是据 Debug/JIT 判断最终流畅度：

```powershell
pwsh -File .\scripts\build-lan-apk.ps1 -Mode Profile
```

产物为 `output/android/duoscene-lan-arm64-profile.apk`，元数据为 `lan-profile-build-info.json`。Profile 与 Debug 一样，仅在显式 `ALLOW_LAN_HTTP` 下允许本次精确私网地址；Release 仍不允许 HTTP 认证服务。Profile 是性能测量模式，不是商店正式包。

需要取帧基线时再加 `-CapturePerformance`，会生成独立 `-perf.apk`（不覆盖普通包）。启用后只记录前 40 秒帧耗时与解码缓存量，保存到 App 外部文件目录的 `duoscene-performance.json`；不记录账号、凭据或片目。正常包默认不采集，Release 不注册回调。每次打包只清理相应 package 任务输出，避免增量 ZIP 空洞；编译缓存保留。

同一电脑、同一 Wi-Fi 上的其他手机安装相同 LAN 包即可登录；本轮只有一台连接的 Android 真机，第二台设备尚未实测。若仍不通，检查访客 Wi-Fi/AP 隔离、VPN、网段和地址是否变化。

## 安全与回滚

这是可信 Wi-Fi 上的调试配置，HTTP 不适合公网、真实敏感账号或正式发布。Release 仍要求 HTTPS，没有全局放开明文、证书校验或图片请求域名。

移除防火墙规则可运行 `Remove-NetFirewallRule -Name Duoscene-LAN-API-3000`。USB 调试可用本机启动脚本的 `-Usb -BindAddress 127.0.0.1`，并安装原 localhost 调试包；服务、App 地址和 Android 网络策略必须保持一致。旧包的覆盖安装需使用相同调试签名，不要卸载以免丢失本地片库。

改动前启动脚本、App 地址校验和 Gradle 配置备份位于 `.local/rendering-refinement/lan-before/`；先前样式包保留在 `output/android/duoscene-style-restored-arm64-debug.apk`。
