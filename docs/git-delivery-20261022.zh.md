# 本轮中文提交说明与测试汇总

## 交付范围

用户授权整理此前全部修改，完成测试后用中文提交信息推送到 `haigepor/Duoscene` 的现有 `main` 分支。不创建新分支、不强制推送、不上传安装包或私有设备数据，不修改只读参考项目 Playra。

主体按依赖顺序整理为三个提交；云端验证发现的问题另行修复提交，不重写已推送历史：

1. **播放源协议与数据契约**：Dart codec/client/provider、分类/详情/线路/分页模型、图片请求策略、独立加密向量、对应回归、17 接口调研及接入契约；后台不承担源站解析。
2. **原页面接线与短剧体验**：原首页/搜索/分类/详情/收藏/历史接入真实数据，真实远端筛选、过期响应隔离、封面有界重试、短剧搜索图标/底部信息/专用控制；保留原视觉基准。
3. **LAN 与性能验收**：物理网卡选择、限域防火墙、精确私网 HTTP 开发许可、Debug/Profile 构建、APK 结构压紧、默认关闭的帧采集、原风格/性能报告与本说明。
4. **CI 视觉测试平台修正**：首轮 Ubuntu 运行精确 Windows 图片基准失败，改为 Windows 固定 Flutter 版本运行 36 项原基准测试，Ubuntu 运行其余 343 项功能测试；两道门禁通过才构建 Android。原 36 张基准及 6 张短剧变体均不重生成，不设置像素容差，不使用 `skip` 或 `continue-on-error`。

源码测试、设计基准和文档随对应功能入库；`.local/`、`output/`、构建缓存、数据库随机口令、鉴权 token、设备偏好备份和本机 IDE 私有映射不入库。

## 本次重新执行的测试

| 检查 | 结果与边界 |
| --- | --- |
| `npm run check:structure` | PASS；严格 UTF-8、LF、JSON、相对引用与文件结构。初次误扫已被 Git 忽略的 `output/` 元数据，现与构建产物排除策略对齐，未放宽源码检查。 |
| `npm run typecheck` / `npm run build` | PASS；TypeScript 测试类型与 API 编译。 |
| `npm test` | PASS；契约 3 项、API 20 项，无失败或跳过。 |
| MySQL 实库套件 | PASS；7 项（含父测试及 6 个子测试），覆盖迁移、抢座事务、邀请回滚、刷新重放/竞争与 HTTP 注销/禁用。使用新临时 MySQL 进程 `127.0.0.1:33308` 与随机隔离库，完成后停服、移除该临时库。 |
| Flutter 对真实 Fastify/MySQL | PASS；额外 1 项，登录、建房、邀请加入、会话恢复与注销。使用上述临时库和随机端口，不使用手机登录态。 |
| `flutter pub get --enforce-lockfile` | PASS；按锁文件解析，不批量升级依赖。 |
| `flutter analyze --no-pub` | PASS；零问题。 |
| `flutter test --no-pub --concurrency=2` | PASS；379 项，含协议、数据、交互、错误分支与视觉回归。 |
| 设计基准 | PASS；原 36 张 PNG 哈希保留；30 张原页面与 6 张批准的短剧独立变体通过匹配。 |
| LAN 与启动脚本 | PASS；地址边界、物理网卡选择、多网卡歧义拒绝、显式覆盖与 PowerShell 语法检查。 |
| 当前 Wi-Fi 真实 API | PASS；ready、test123 登录、身份、受保护房间读取与本次验证会话注销。API `0.0.0.0:3000`，手机专用 MySQL 仍为 `127.0.0.1:33307`，无 ADB 3000 转发。 |
| 安装包与设备 | PASS；已验收的普通 ARM64 Profile 包 104,820,026 B，ZIP CRC/AOT/ABI/签名均通过，设备安装 SHA-256 与产物一致；默认帧采集关闭。 |
| 账号片库数据 | PASS；1 收藏、5 历史与性能切片前证明完全一致，未再次卸载或清数据。 |
| npm 安全审计 | PASS；本次 `npm audit --json` 返回 0 项漏洞；不代表外部源站或全部 Dart/native 依赖永久无风险。 |

MySQL 预检第一次尝试使用现有实例管理员连接遭 `ER_ACCESS_DENIED_ERROR`，未执行数据库测试或改权限；随后改用全新临时实例完成实库测试，没有试探或重设已有管理员口令。初次失败及后续成功日志均保留在忽略目录。

本轮没有重新运行会覆盖安装并可能重置数据的原生 `integration_test`。封面、真实筛选、首集播放与原生截图沿用紧接本次提交前已记录的真机证据；这些检查与本次新跑的自动化测试分开列示，不把 379 项测试冒充全部原生或双设备测试。

### 首轮云端失败与修复依据

首次推送的 [Actions 39659325801](https://github.com/haigepor/Duoscene/actions/runs/39659325801) 中，API、依赖锁、Flutter analyze 均通过；Ubuntu 的 36 项精确视觉比较失败，例如 light-01 差异 5.69%、light-02 差异 1.69%，因此 Android 构建未执行。日志中没有将其掩盖成构建成功。

[Flutter 官方 LocalFileComparator 说明](https://api.flutter.dev/flutter/flutter_test/LocalFileComparator-class.html) 明确默认逐像素比较，带自定义字体的 Windows 基准与另一操作系统渲染通常不同。此次修复将该已有 Windows 基准的严格比较放到 `windows-2025`，继续固定 Flutter 3.47.6 的同一提交；测试使用明确标签分流，Linux 不能代替 Windows 视觉门禁。失败图片会单独上传供定位。最终云端结果仍以最新提交的 Actions 记录为准。

## 安装包与体积结果

普通 LAN Profile：`output/android/duoscene-lan-arm64-profile.apk`，SHA-256 `6f335a4a00412fb6276d53ed06c00879466537c89164a0ed2113c0014d155017`。这是使用调试证书的 AOT 性能测试包，不是生产 Release；只适用于当前可信 Wi-Fi 地址。APK 不随 Git 提交。

同模式 Debug 修复 ZIP 空洞减少 29.51 MiB，没有删除 WebRTC、解码库、字体或页面资产。99.96 MiB Profile 与 76.95 MiB 未签名占位地址 Release 体积探针分别记录，不将模式差异全部归因于业务优化。

## 已知限制与后续工作

- **性能方案未全部完成**：Profile raster p95 35.054 ms 仍超 60 Hz 单阶段预算；GPU 绘制定位、局部通知、首屏优先、目录/播放请求复用、统一取消和 prepared 身份校验属于 NEXT。
- **播放验收未全覆盖**：首集 2:52 已播放并推进，不等于所有线路、连续滑动换集、弱网与长时播放全部通过。上游仍可能返回截断参数；不能绕过完整性检查制造成功。
- **网络与安全**：上游协议仍为特定 HTTP 源且无独立 MAC；LAN HTTP 仅供开发。正式发布需要 HTTPS 服务、正式签名及内容授权核验。
- **设备范围**：本轮仅一台 Honor Android 9；第二台 Wi-Fi 设备、两端同步/语音和跨网性能仍需专项验收。
- **云端范围**：本地检查通过不等于 GitHub Runner 已通过。现有 Android 工作流在推送命中路径时自动运行；实际提交 SHA、推送和云端结果以最终回复及对应 Actions 页面为准。云端默认 Debug/localhost 包不是本机 LAN Profile 包，且 Runner 调试签名可能不同，不盲目覆盖手机安装。

## 文件与回滚

详细文件职责分别见 [协议报告](whisklet-provider-analysis-20261022.zh.md)、[样式报告](style-restoration-20261022.zh.md)、[渲染报告](provider-rendering-refinement-20261022.zh.md)、[LAN 说明](lan-development-20261022.zh.md)、[性能报告](playra-performance-study-20261022.zh.md)。

新增构建检查修正仅涉及 `scripts/check-structure.mjs` 排除已忽略的 `output/`，不跳过受版本管理的源码、测试、JSON 或文档。README 汇总当前入口并区分历史记录与最新验收。

本机逐片回滚快照在 `.local/rendering-refinement/before/`、`.local/rendering-refinement/lan-before/` 与 `.local/performance-study/before/`，不上传。推送后可按各个中文提交审阅或在先保存工作区的前提下逐片反向提交，禁止全仓 reset、强推或用卸载 App 代替同签名覆盖安装。
