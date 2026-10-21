# 全页面原样式恢复与数据接线验收

## 1. 结论与边界

视觉基线固定为接入 SDK 前的 `027337fa36fc452c5e8a871665b9b60f9f5df6a5`。本次不是重新设计：删除另起炉灶的 `ProviderCatalogView`，真实接口数据与设计预览均使用原来的页面组件。标题、海报、简介、集数、片源可随数据变化；主题、配色、字号、间距、导航、裁切比例与控件外观不变。

此前 `whisklet-provider-analysis-20261022.zh.md` 是接入当时的历史报告，其中独立 provider 网格的描述已被本报告替代。协议实现、Android 网络策略、依赖、后端和测试账号不在本次修改范围，没有提交或推送。

## 2. 根因与修复

| 页面/区域 | 回归根因 | 恢复方式 |
| --- | --- | --- |
| 首页 | provider 分支提前返回新的 SafeArea/通用网格，绕过原首页 | 恢复 ScrollChrome、头像、原搜索框、票签分类、四项轮播、续播、同看卡、横向片单；只注入真实 Film |
| 分类 | 真实数据没有进入原分类发现页 | 原 CatalogDiscovery 接收分类数据；保留筛选卡、精选组合、横向片单与原三列网格，滚动追加真实页码 |
| 搜索 | 原输入框、分类标签与纵向条目被新网格替换 | 原 SearchPage 绑定分页 SearchState；350ms 防抖、过期响应隔离；空分类页可继续查找 |
| 短剧 | 全屏竖向播放流被片库网格替换 | 恢复竖向 PageView、原渐变、右侧操作栏、底部信息；SDK 负责详情、集数和播放地址 |
| 详情 | 新线路下拉表单改变排版；真实片目隐藏相关推荐 | 去掉插入式表单，恢复原简介/选集/相关推荐；线路选择接入播放器既有“片源”弹层 |
| 历史/收藏 | 需要从硬编码 films 查找迁移到真实元数据 | 保留原行、筛选、管理和海报组件，使用账户隔离快照；续播刷新详情后解析，不保存临时播放 URL |
| 我的收藏缩略图 | ProfilePage 仍从虚构 films 查找，真实收藏有数量但无封面 | 只把 _favoriteCovers 的数据集合替换为 library.knownFilms，原排序与三张封面上限、面板/行/点击入口不变 |
| 海报 | 通用图片包装统一缩图，影响本地图片像素 | 本地图片默认不缩图，各调用点原 cacheWidth 保留；网络图使用原容器尺寸和 cover 裁切，失败占位不冒充其他影片 |

短剧进度按实际装载片源的 identity 绑定集数，而非解析中提前变化的 UI 页码；快速切集的旧响应不得覆盖新选择。切标签/覆盖路由暂停媒体并保留同集位置。播放器线路和集数切换保持原有外壳。

## 3. 数据与职责

```text
SDK HTTP/解密 → WhiskletProvider → Film / CatalogPage / MediaDetail / PlaybackSource
                            ↓
        CatalogFeed / SearchState / LibraryState
                            ↓
           原首页、分类、搜索、详情、短剧、历史、收藏组件
                            ↓
                 原播放器与原片源/选集弹层
```

新增 `catalog_data.dart` 只管理加载、错误、真实分页、去重和元数据快照，不包含页面布局。后端仍只承担账户、房间与通讯，不代理 SDK 解密或片库处理。

## 4. 全页面核对清单

| 原设计页 | 处理/证据 |
| --- | --- |
| 01 观影首页、02 短剧推荐流、03 观看记录 | 恢复/保留原组件，接入数据；双主题 golden |
| 04 我的、05 影片详情、06 长视频与私聊 | 我的收藏缩略图改为真实快照；详情恢复；播放器数据接线；双主题 golden |
| 07 短剧私聊、08 发送邀请、09 搜索 | 私聊/邀请组件未改；搜索恢复；双主题 golden |
| 10 选集、11 播放与音频、12 私有账户登录 | 原组件未改；选集数据由实际线路提供；双主题 golden |
| 13 我的收藏、14 接收邀请、15 隐私与记录 | 收藏数据接线；其他组件未改；双主题 golden |
| 16 账户信息、17 帮助与反馈、18 关于 Duoscene | 页面源码未改；双主题 golden |
| 独立外观设置、注册/找回、房间列表/表单/详情/同看 | 源码保持基线，既有布局/交互测试回归；不宣称这些真实路由有新增逐页截图 |

源码审计遍历基线 91 个已跟踪 Dart 文件：78 个字节完全相同，13 个为片库和观看数据绑定改动。另新增数据状态与回归测试。design、app/theme、auth、rooms、底层 playback、assets、vendored media-kit、apps/api、packages/contracts 均无基线差异。此次任务开始前的其他未提交修改逐项 SHA256 比对保留。

## 5. 验证与产物

- `flutter analyze --no-pub`：0 问题。
- `flutter test --no-pub`：337 项通过，包含真实 provider 页面结构、我的收藏缩略图、分页/重试/去重、旧响应隔离、历史续播、原有大字体/主题/多尺寸交互回归。
- 原 18 设计页 × 明暗主题：36/36 严格像素比较通过，390×844 / DPR 1 / 中文 / 字体缩放 1。基准在隔离的原版提交生成，先独立验证基准可复现，再冻结；未使用修改后页面更新基准。
- golden 不等于所有真机路由逐页实测，也不要求真实影片内容与虚构原稿像素相同。真实 provider 另有首页/搜索/短剧/详情结构测试与 Android 实测。
- `scripts/check-structure.mjs`、`git diff --check`：通过；UTF-8 无 BOM、LF、无替换字符。
- APK：`output/android/duoscene-style-restored-arm64-debug.apk`，199779114 字节，SHA256 `ded0142a20207c4b6ff9b450c19bba7ba98e39e1f0f402ee666f52959e3f8019`。本机 debug 签名校验通过，证书 SHA256 `fa4ec0e036ba5760beaab14bed70e1f6d625462317b8a42d828ac7c3797927fe`。
- 真机：Honor LLD-AL20 / Android 9 / arm64，`adb install -r -t` 成功，保留当前登录、收藏和历史；首页和分类已显示实际片目与原样式。
- 真机搜索 `007` 返回 15 项，以原纵向条目渲染；进入真实详情，简介、观看按钮和“你可能也喜欢”保留，未插入线路表单。既有播放器“片源”弹层正常列出多条真实线路。007 示例已探测出时长 `02:43:31`，未把该示例声明为已播放成功。
- 真机短剧真实视频画面已截取，Android MediaSession `state=3`、位置 5886ms；退出/返回短剧后 `state=2`、位置 9006ms，确认同集暂停续播。实际首个片目线路提供一条全集视频，因此显示“共 1 集”，不虚构拆集。
- 真机发现并修复未知总时长的历史进度被除零画成 100%：先添加断言复现 `Expected 0 / Actual 1.0`，再改为保留已看秒数、总长未知时不画满条，复跑全套通过。
- 我的收藏缩略图漏接快照的测试先复现 `Expected 1 FilmPoster / Actual 0`，修复为真实账户集合后与整套布局测试一并通过。

详细证据位于忽略目录 `.local/style-restore/source-audit.json`、`.local/style-restore/artifact-proof.json`、`.local/style-restore/runtime-before-final-proof.json`、`.local/style-restore/reference/manifest.json`、`candidate-final.log`；原设计 PNG 位于 `apps/mobile/test/goldens/style_reference/`。真机截图/XML 位于 `.local/provider-probe/style-restored-*`。最终安装包须与设备 base APK 的 SHA256 相等，原有 1 项收藏、3 项历史及登录值比对保留；实测新增观看记录不覆盖旧记录。

## 6. 修改清单与回滚

- `home_page.dart`、`home_content.dart`、`category_discovery.dart`、`search_page.dart`：原壳与数据绑定；不改变路由或设计系统。
- `catalog_data.dart`、`library_state.dart`：片库状态、分页与快照；不改存储键，不迁移账户数据。
- `detail_page.dart`、`posters.dart`、`profile_page.dart`：原详情结构、真实海报渲染和我的收藏缩略图数据绑定。
- `experience_player.dart`、`watch_controls.dart`、`short_feed.dart`：原播放外观与片源/集数接线。
- 新增 `catalog_data_test.dart`、`style_provider_binding_test.dart`、`style_reference_test.dart` 和 36 张原版 golden；删除弃用的新网格及其专属测试，历史用例迁入新测试。
- 本轮修改前文件备份与哈希在 `.local/style-restore/before/`；原本干净文件可从固定基线逐文件提取。禁止全仓 reset，以免覆盖此前 SDK、账号和用户修改。
- 安装前设备偏好备份在 `.local/style-restore/device-before.xml`（含登录信息，不应提交/公开）；旧本机签名安装包仍在 `output/android/duoscene-provider-arm64-debug.apk`。

## 7. 保留风险

1. 分类题材/时长排序只作用于已加载数据，不宣称 SDK 支持已验证的全库远端过滤；未知时长不当作 0 分钟短片参与时长筛选。
2. 上游 API 仍使用 HTTP，部分海报 CDN 或播放解析家族可能不可用；不绕过证书校验、不假造封面或播放成功。
3. 18 页 golden 验证的是同环境原稿布局；Android 字体与真实内容仍以设备截图和实际交互为准。
4. 既有 Gradle/AGP/Kotlin 即将弃用提示保留，未为此次样式恢复升级工具链。
5. 交付为本机联调 debug 包，后端地址仍是 `http://127.0.0.1:3000`，依赖当前 ADB reverse 与本机服务；不是已配置公网后端的商店发布包。
