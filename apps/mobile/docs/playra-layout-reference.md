# Playra 新版 Android 布局与 token 写法分析

2026-10-19，只读核对 `D:/project/Playra` 当前源码和该项目已有 Android 验证截图。本次没有重新运行 Playra，没有修改其源代码。这里的 token 指 UI 样式参数，不是登录凭证。

## 结论

Playra 没有统一命名为 `tokens.dart` 的设计 token 文件。它通过局部 ThemeData、ColorScheme、TextTheme、组件主题和作用域组合表达 token；页面仍有不少局部字号和间距常量。因此可参考其尺寸语义和适配方法，但不能描述成“全项目样式已完全由单一 token 文件控制”。`components/upstream` 是组件示例，不能当成产品 Android 页面依据。

## 已核对的位置

| 文件（相对 Playra） | 实际职责 |
| --- | --- |
| `lib/presentation/modern/home/home_theme.dart` | 深浅色语义色、首页 Material/ShadTheme 局部桥接，保留用户字体；按钮、输入、导航等主题 |
| `lib/presentation/modern/settings/modern_settings_scope.dart` | 新版设置与二级页紧凑字号、图标、Slider/Switch、40dp 视觉按钮及 padded 点击区 |
| `lib/presentation/modern/secondary/secondary_theme.dart` | 二级页作用域、48dp 原生 TabBar、空态与失败状态 |
| `lib/presentation/modern/player/player_theme.dart` | 播放页紧凑主题与最小 48dp 文本/图标操作目标 |
| `lib/presentation/modern/home/modern_home_view.dart` | SafeArea、760dp 内容上限、Sliver、横向分类、按可用宽度和文字比例改变列数 |
| `lib/presentation/modern/profile/modern_profile_view.dart` | 顶部固定标题，Expanded 内滚动内容，760dp 上限与小屏大字降列 |
| `lib/presentation/modern/pages/content_search_screen.dart` | 56dp AppBar、20dp 标题、输入/筛选/结果区域与 900dp 上限 |
| `lib/presentation/modern/widgets/modern_page_art.dart` | 装饰背景独立 Stack，不占内容空间，不拦点击、不进入读屏 |
| `lib/presentation/shared/tab_shell.dart` | 根导航壳和覆盖可见性，子页复用壳层；与 UI token 分工不同 |

## 字号与尺寸

| 项目 | Playra 当前新版常见值 | Duoscene 应采用的依据 |
| --- | --- | --- |
| 主页面标题 | 22dp；搜索 20dp | 原稿换算约 23–26dp，按页面角色设定 |
| 区块标题 | 16/18dp | 原稿约 15–16dp |
| 正文 | 14dp，行高 1.5 | 原稿 12–14dp，本轮基础正文 13dp |
| 辅助文字 | 12dp；小标签 11dp | 原稿约 10–11dp |
| 普通图标 | 20dp，底栏 21dp | 原稿约 20dp |
| 设置按钮 | 可见最小高 40dp，padded 命中 | 原稿可见高约 32dp，命中区保留 48dp |
| 底栏 | 72dp，图标 21dp、文字 12dp | 原稿底栏更紧凑，不能直接拷贝 72dp |
| 常用间距 | 8/12/16/20/24dp | 使用原稿换算，统一同类组件 |
| 圆角 | 输入 12、卡片 16/20dp | 原稿紧凑卡片约 11dp，按钮为胶囊 |

## Android 布局方法

1. 使用 Flutter 逻辑像素，不按屏幕物理分辨率放大字体。原有字体族通过 `copyWith`/`apply` 传递。
2. 保留 `MediaQuery.textScalerOf`。首页卡片在可用宽度小于 320 或字号比例超过 1.3 时，从双列改为单列；抽屉网格列数使用 `floor((width-40)/(116*scale)).clamp(2,6)`。这是调整排版，不是强制缩小系统字体。
3. 安全区由页面或导航壳单一负责；常见 `SafeArea(bottom:false)` 让底部导航处理底边，避免重复留白。
4. 页面由 `Scaffold → SafeArea → 受限宽度 → 可滚动内容` 组成。手机宽度小于 maxWidth 时填满可用宽度；760/900/1200 是不同页面的宽屏上限，不是手机设计稿宽度。
5. 视觉尺寸与点击区分开。播放器作用域显式使用 `VisualDensity.standard` 和 `MaterialTapTargetSize.padded`，防止 Android 触摸区被桌面密度压缩。
6. 装饰使用 IgnorePointer/ExcludeSemantics，媒体 Surface 与内容布局不由装饰图片决定。
7. `modern_shell.dart` 的底栏外层 SafeArea 先消费系统底边，避免 NavigationBar 再叠加。`mobile_tab_view.dart` 使用 280ms 横移动画和已访问页缓存，离开页关闭 Ticker、焦点、点击与读屏；这属于导航行为，不是字号 token，不需要为尺寸校正整体迁入。

已查看仓库内 `docs/verification/mobile-tabs-android-discover.png`、`mobile-tabs-android-profile.png`、`content-search-android-token.png` 和 `content-search-android-results.png`。这些是已有证据；当前分析没有把它们说成本轮重跑结果。

## 对 Duoscene 的落地

保留原稿森林黑、薄荷绿、四标签和胶囊按钮。借鉴语义 token 与主题消费的方式，在 `lib/design/tokens.dart` 集中正文、标题、辅助字、图标、卡片、按钮与菜单参数，由 `app/theme.dart` 和公共组件读取；保留现有 Navigator/ChangeNotifier，不迁入 Playra 的 Flutter Modular、Hive 或整套 ShadTheme。

屏幕偏大的根因是前一版尺寸层级、默认控件高度和比较画布比例；不能通过修改 Android density 或关闭字体缩放来掩盖。当前 887×1774 原稿以 390×780dp 核对。Android 系统状态栏与原稿 iOS 装饰有差异，图片内生成字形也不是可精确复用的字体，因此最终应逐页比较结构和几何，并明确剩余资产差异。
