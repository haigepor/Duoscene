# 认证页面开放式布局还原

## 结果与边界

按确认的第二版三页设计稿，还原登录、注册和找回密码的开放式表单、左对齐标题、紧凑品牌栏、轻量注册/返回入口、玻璃插图与底部胶片。共用当前 Flutter 原生组件、DSPalette、DS 字体/间距/圆角、PageFrame 和现有页面过渡；没有引入新的 UI 框架或主题。

保持既有品牌组件与电影票插图，主要控件高度 48dp、输入与按钮圆角 12dp；页面内容最大宽度 400dp，横向留白 24dp。三个首字段位于相同纵向基线。宽屏居中，小屏、键盘和大字体下自然滚动；装饰图不参与点击或朗读。

登录/注册/恢复 API、账户格式、12–128 字符新密码约束、43 字符恢复码规则、成功后清空密码、复制恢复码与“我已安全保存恢复码”返回门槛均保持原流程。注册页两个密码输入框现在分别控制显隐，查看一个不会暴露另一个。

## 文件与影响

| 文件 | 用途与影响 |
| --- | --- |
| `apps/mobile/lib/features/auth/auth_widgets.dart` | 三页共用开放表单、标题/插图、输入装饰、说明与文本入口；不持有业务状态 |
| `apps/mobile/lib/features/auth/login_page.dart` | 品牌栏、登录表单、轻量注册入口、底部胶片；原输入控制器和登录行为保留 |
| `apps/mobile/lib/features/auth/account_access_page.dart` | 注册/找回标题与四字段表单、恢复码说明；保留恢复码成功确认流程 |
| `apps/mobile/assets/design/media/auth-account-glass.webp` | 独立透明账户玻璃卡插图 |
| `apps/mobile/assets/design/media/auth-key-glass.webp` | 使用用户要求修正后的双圆环钥匙 |
| `apps/mobile/assets/design/media/auth-filmstrip-glass.webp` | 用户最终选定的首版胶片，不使用后续虚化试稿 |
| `apps/mobile/test/account_access_test.dart` | 原注册/恢复门槛回归，新增独立密码显隐回归，并明确验证初次提交错误 |
| `apps/mobile/test/app_test.dart` | 跟随设计稿登录按钮文案调整既有应用流程测试 |
| `apps/mobile/test/auth_layout_test.dart` | 三页深浅两主题、320dp、200% 字体、键盘下控件可达性 |

## 素材与性能

三张新素材保留透明 alpha，以 WebP 编码，合计约 667 KiB。原始生成图和选用映射在 `.local/designs/auth-ui-20261021/assets.json`，没有在代码中使用生成图外部路径。

复用 DSIllustration 按显示宽度与像素比选择解码尺寸，并使用 RepaintBoundary。标题插图在本次 2x 模拟器中按 256px 宽解码，胶片上限 768px；没有额外全屏 BackdropFilter 或实时模糊。胶片在键盘弹出、低可用高度或大字号下隐藏，不遮挡表单。保留系统减少动画设置与现有导航过渡。

## 验证

- 静态分析无问题，完整 88 项测试通过。
- 独立密码显隐回归先复现旧实现失败：查看密码会同时显示确认密码；最终实现通过。
- 注册/恢复成功后，未确认保存恢复码时返回按钮仍禁用；输入与 API 参数回归通过。
- 三页深浅主题、320dp 宽、200% 字体及键盘 280dp 遮挡下无溢出，提交按钮可滚动到达。
- Android 模拟器实际逐页截图已核对浅色/深色布局，路径 `.local/screenshots/auth-{login,register,recover}-{light,dark}.png`。
- 普通 `lib/main.dart` 调试入口成功热更新，三张新素材均实际加载，没有缺失素材异常。
- 使用原有本地测试账户通过真实登录页面进入首页，确认新表单与现有服务连接正常；随后返回登录页并重新填好测试凭据，密码保持隐藏，供用户直接登录测试。未创建新账户或重设密码。

验证边界：小屏/大字体由 Widget 测试覆盖，实际页面截图来自 Android 模拟器；尚未进行真机键盘与长时间性能验证。上一轮性能报告中首次二级页偶发长帧仍是独立未解决项，本次不宣称全部首帧卡顿已消除。

## 回退

本轮原文件备份和范围清单：`.local/backup/auth-open-layout-20261021/`。只恢复清单内四个原文件，并删除本轮新增的认证辅助组件、布局测试、三张插图和本文即可回退。此前页面重构、切页性能改动、用户原有未提交改动和认证后端均不需回退。
