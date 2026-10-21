# 固定测试账号与本机真实登录验证

日期：2026-10-21。源码基线：027337fa36fc452c5e8a871665b9b60f9f5df6a5。

2026-10-22 更新：账号仍为显式本机测试数据，认证规则未放宽；当前已改用同一 Wi-Fi 的 LAN 服务，不再依赖 USB tcp:3000 转发，数据库仍仅监听本机。下文保留初次 USB 配置的历史记录；当前启动方法见 [LAN 说明](lan-development-20261022.zh.md)，最终测试见 [提交说明](git-delivery-20261022.zh.md)。

## 使用结果

- 测试账号：`test123`。
- 测试密码：`test123`。
- 显示名称：测试账号。
- 当前手机上的原云端 APK 已成功登录；强制关闭 App 后重新启动，真实刷新接口返回 200，回到已登录首页。
- 本机 API 和专用 MySQL 仍在运行，USB 的 tcp:3000 反向转发保留，便于继续测试。

此账号只存在本机专用测试数据库，不是写入 APK 的离线登录口令，也不是生产环境默认账号。
手机离开当前电脑或 USB 转发中断后，需要重新连接本机后端，才能进行新的登录和房间网络操作。

## 分析与实现边界

原 `hashPassword()`、注册/恢复 JSON Schema 和注册页面要求至少 12 位密码，指定的 7 位密码无法通过正常注册或管理员创建命令。
登录接口与移动端登录页允许非空密码，并通过数据库中的 scrypt 哈希验证；所以不需要修改 APK 或放宽整个系统的密码策略。

本次只在隔离数据目录内预置这一条显式测试数据：采用与正式验证器一致的 scrypt 参数、随机盐和哈希格式。
服务器仍执行原有数据库查找、密码比对、会话令牌、安全存储、刷新和注销流程；没有新增特殊用户名判断、虚假登录或客户端绕过。
后续注册和恢复仍执行 12–128 位规则；测试账号若通过正常恢复流程修改密码，也应使用符合规则的新密码。

## 环境与持久性

| 项目 | 配置 |
| --- | --- |
| 专用 MySQL | 8.4.13，官方 Windows ZIP；MD5 与官方页面一致，mysqld.exe 的 Oracle Authenticode 签名有效 |
| 数据库监听 | 127.0.0.1:33307 |
| 专用数据库 | duoscene_test_device |
| 数据目录 | .local/test-account/data/ |
| 业务 API | http://127.0.0.1:3000，仅监听本机回环 |
| 运行工具 | 项目 .local/tools/ 的 Node 24.22.0 与便携 MySQL |
| 私有配置 | .local/test-account/private.json；随机数据库凭据，不随 Git 提交 |
| 初始化 | 九项 SQL 迁移全部 APPLIED；首启时设置随机 root 密码和仅限专用库的应用账户 |

发现既有 MySQL80 服务，但本次没有启动、修改或读取其原始数据；操作完成后该服务仍是 Stopped。
专用数据库和 API 都作为隐藏的本机进程运行，没有注册 Windows 服务、创建计划任务或开放防火墙端口。
重复运行启动脚本复用已有数据和同一账户 ID，不重置密码、不重复建号、不撤销手机已有会话。

电脑重启或服务关闭后，从仓库根目录运行：

```powershell
.\.local\test-account\start.ps1
```

只连接一台已授权 ADB 设备时会自动建立转发；多个设备时用 `-Device <设备ID>` 指定。
脚本会启动本次专用 MySQL/API；若端口被其他进程占用或数据库目录不匹配，会停止操作。
它依赖本机已经下载的 .local 工具和私有配置，不是已发布到其他机器的一键安装器。

## 验证证据

- PASS：`manage.mjs seed` 实际运行九项迁移、创建持久账户，重复执行不产生重复记录。
- PASS：真实 MySQL 的 readiness 200；正确密码登录 200；错误密码 401。
- PASS：登录返回的令牌可访问 `/api/v1/auth/me` 和 `/api/v1/rooms`；返回用户名为 test123。
- PASS：刷新令牌成功；注销后原会话访问受保护接口返回 401。
- PASS：注册接口仍拒绝 test123 这样的短密码，返回 422，没有降低全局密码门槛。
- PASS：Honor Android 9 真机输入指定账号密码，实际 API `/auth/login` 返回 200，页面进入首页；个人中心显示“测试账号”。
- PASS：force-stop 后重启，API `/auth/refresh` 返回 200，新 UI hierarchy 仍包含“创建房间”和“我的”，没有返回登录页。
- PASS：MySQL 和 API 都只监听 127.0.0.1；现有 MySQL80 服务仍停止；原 APK 没有修改或重新安装。

API 验证命令：

```powershell
.\.local\tools\node-v24.22.0-win-x64\node.exe .local/test-account/manage.mjs verify
```

本机证据：`.local/test-account/api.stdout.log`、`phone-home.png`、`phone-profile.png`、
`phone-restored.png`、`profile.xml`、`restored.xml`。日志只记录方法、路由模板和状态码，不输出密码或会话令牌。
本次没有验证第二个账号、双人播放、语音或公网连接，不能用单账号登录成功代替这些验收。

## 文件与回退

- `.local/test-account/manage.mjs`：生成私有配置、隔离校验、幂等预置、真实鉴权验证和运行 API；仅作用于固定本机测试库。
- `.local/test-account/start.ps1`：使用现有便携工具启动本次私有进程并建立 USB 转发，不操作既有 MySQL80 服务。
- `.local/test-account/private.json/mysql.ini/data/`：本机凭据、配置与持久数据；均被 .gitignore 的 .local/ 规则忽略。
- 本文与旧 Android 报告的后续验证链接：记录操作方法和证据，没有修改应用业务源码。

回退时先关闭本次 API 与数据库，再移除本次 ADB tcp:3000 reverse。保留 `.local/test-account/` 可恢复测试数据；
不要删除或重置原 MySQL80 数据。源码没有密码策略变更需要回滚。当前文档改动保留本地，未自动提交推送。

官方依据：[MySQL 8.4 下载](https://dev.mysql.com/downloads/mysql/8.4.html)、
[Windows ZIP 手动配置](https://dev.mysql.com/doc/refman/8.4/en/windows-install-archive.html)、
[Node.js scrypt](https://nodejs.org/docs/latest-v24.x/api/crypto.html#cryptoscryptpassword-salt-keylen-options-callback)。
