# Duoscene 页面统一、设计还原与性能检查

本轮按 L 级跨页面改造执行 Research → Design → Implement → Verify → Review。
目标是统一现有蓝色 token、紧凑间距和玻璃插图，同时保留当前 Flutter 页面、账户、房间和播放架构。

## 1. 截图定位与二级入口

| 用户截图 | 实现位置 | 对应二级页面与操作 |
| --- | --- | --- |
| 图 1：我的 | `features/catalog/profile_page.dart / ProfilePage` | 账户信息、收藏、外观、邀请入口、播放与音频、隐私与记录、帮助、关于、退出确认 |
| 图 2：创建房间 | `features/rooms/room_form_page.dart / RoomFormPage(join: false)` | 房间详情 → 成员、一次性邀请、同看播放器 |
| 图 3：邀请加入 | 同上，`join: true` | 校验完整邀请码 → 加入房间 → 房间详情 |
| 图 4：正在观看 | `features/experience/experience_player.dart / ExperiencePlayer` | 视频地址、本地文件、聊天、简介、选集、音频、播放器功能 |
| 图 5：影片详情 | `features/catalog/detail_page.dart / DetailPage` | 收藏、推荐影片、播放、选集、发出邀请 |
| 图 6 / 7 / 9：发出邀请 | `features/experience/invite_pages.dart / InviteSheet` | 未生成、生成中、可复制/分享、进入房间、撤销、过期；共享同一组件 |
| 图 8：选集 | `features/experience/episode_sheet.dart / EpisodeSheet` | 分段筛选、个人直接换集、共同观看确认与等待 |
| 房间详情内的邀请 | `features/rooms/invite_panel.dart / InvitePanel` | 生成、复制、撤销、到期、进入后台隐藏邀请码 |

上述路径均相对于 `apps/mobile/lib/`。

其他检查入口：

- `collection_pages.dart`：主记录页、个人/共同进度二级页、收藏页。
- `settings_pages.dart`：播放与音频、隐私与记录、账户信息、帮助与支持、关于。
- `appearance_page.dart`：统一蓝色主题的明暗设置。
- `room_list_page.dart / room_detail_page.dart`：房间列表与房间详情。
- `auth/account_access_page.dart`：注册与恢复账户。
- `realtime/room_watch_page.dart`：真实同看与语音设置入口。
- `playback/widgets/player_library_view.dart`：通用播放器与无媒体状态。

## 2. 主要问题与处理

| 优先级 | 证据与原因 | 本轮处理 |
| --- | --- | --- |
| 高 | 记录页额外按状态栏基线补出 48/64dp 顶部空间，和其他页面工具栏不一致 | 移除独立补偿，统一 48dp 工具栏；主页面标题基线回归测试 |
| 高 | 隐私内进度页面嵌套 PageFrame 与完整 HistoryPage，出现重复导航层 | 进度页面增加 secondary 呈现，共用一个返回标题栏 |
| 高 | 部分 AppBar 指定文字样式但缺少明确前景色，媒体上下文与弹层文字继承不稳定 | 标题与正文统一消费 ink；业务弹层显式恢复 DefaultTextStyle/IconTheme |
| 高 | 相同邀请面板不同主题下出现前景不清晰、内容过高与层级不一致 | 统一 DSSheetContent、影片摘要、双人席位、说明、主次操作与可滚动高度 |
| 高 | 原生验收发现新增按钮引用不存在的 plus.svg | 改用已有 Material 加号图标，并加入图标及片库资源引用检查 |
| 中 | 个人中心信息密度偏低、头像与卡片较大，设置入口层级单一 | 40dp 头像、紧凑收藏卡、常用/隐私帮助两组菜单与统一分隔 |
| 中 | 详情页封面占高较大，推荐说明接近固定底栏；封面操作对比度不稳定 | 封面高度收敛到视口 36%（240–320dp），操作图标采用独立深色圆片，推荐卡文字与图片分离 |
| 中 | 空状态大图标与新玻璃插图风格不一致 | 使用票根、对话、明暗、耳机、隐私五张独立透明插图 |
| 中 | 页面、分页、底部弹层节奏不一致 | 路由进入 280ms、返回 220ms，遵循现有 DSMotion；弹层统一处理减少动画设置 |
| 中 | 邀请面板每秒触发整页 setState | 按显示分钟变化与准确到期边界调度，并在关闭/撤销后取消计时 |

## 3. token 与主题约束

唯一设计来源为 `design/tokens.dart`、`design/palette.dart` 和 `app/theme.dart`。

| 类型 | 规则 |
| --- | --- |
| 主色 | 浅色 #465BE0；深色 #A9B9FF；主按钮文字使用 onPrimary |
| 背景 | bg / panel / subtle；正文 ink，辅助文字 muted，分隔 line |
| 字号 | 主页面 18、二级标题 16、正文 14、说明/标签 12；保留系统 TextScaler |
| 间距 | 左右 16；区块 24；内容 12/16；细节 4/8 |
| 圆角 | 面板 14、输入/按钮 12、弹层 20；浮动导航沿用胶囊材质 |
| 点击 | 主要交互至少 48dp；图标与装饰尺寸不决定触控尺寸 |
| 动效 | DSMotion.fast / standard / navigation；单一指示器连续移动，支持中途反向 |

森林主题选项、woodland 调色板、背景图片与背景 ShaderMask 分支已移除。
`forest:<mode>` 本地偏好迁移为 `sky:<mode>`，保留明暗选择与原有账户/片库数据。
`Forest` 背景组件保留原调用名称，作为蓝色语义背景的兼容入口。

## 4. 设计稿与素材

设计稿由内置 image_gen 生成，目录：`.local/designs/unified-ui-20261021/`。

| 文件 | 页面组 |
| --- | --- |
| 01-profile-appearance-account.png | 个人中心、外观、账户 |
| 02-rooms.png | 创建、加入、房间列表；已收紧表单装饰尺寸 |
| 03-detail-player-episodes.png | 详情、播放、选集 |
| 04-invitations.png | 浅/深邀请弹层、接受邀请 |
| 05-settings.png | 音频、隐私、帮助、关于 |
| 06-collections.png | 记录与收藏的紧凑顶部布局 |

原生控件与现有 token 负责文字、交互和尺寸；设计图内示例影片、音量、身份等内容由真实业务数据提供。
未配置的反馈渠道不增加虚假的提交操作，实际帮助问答与账户协助入口保持可用。

五张新增插图位于 `apps/mobile/assets/design/media/`：

- `duo-tickets-glass.webp`：房间、邀请、关于。
- `conversation-glass.webp`：私聊空状态、帮助。
- `appearance-glass.webp`：外观。
- `audio-glass.webp`：播放与音频。
- `privacy-glass.webp`：隐私与记录。

记录/收藏继续使用既有 `collection-history-glass` 与 `collection-favorites-glass`。
PNG 源文件保存在 `.local/backup/unified-ui-20261021/media-png/`；提示词保存在同目录上级的 `prompts-final.json`。
生产素材使用逐像素验证的无损 WebP，关键大封面依据解码测量保留 PNG。

## 5. 性能实验与取舍

测量设备为 `127.0.0.1:5557` Android 模拟器，Flutter 调试模式。

| 实验 | 测量结果 | 决定 |
| --- | --- | --- |
| 首次/重复切页 | 改造前首次个人中心构建峰值约 120ms，重复进入明显降低 | 分开记录首次与重复采样；不将调试 JIT/缓存收益当作发行版帧率结论 |
| 详情封面限制解码宽度 | 1672×941 RGBA 6,293,408 字节 → 1080×607 的 2,622,240 字节，减少 58.3% | 保留，降低解码图像和纹理内存 |
| 强制关键封面改 WebP | 该模拟器上缩放解码耗时上升，收益未覆盖成本 | 撤回此封面的 WebP，保留 PNG |
| 其余图片无损 WebP | 所有可见 RGBA 像素与 alpha 逐像素一致；最终同一组素材 26,793,394 → 18,892,178 字节，减少 29.5% | 保留；源 PNG 归档，不改变构图、尺寸与可见像素 |
| 新增插图并移除森林背景后的总体积 | 改造前约 22.78MB → 最终约 18.89MB，减少约 17%，同时增加五张插图 | 保留 |
| 邀请倒计时 | 从每秒回调改为分钟显示变化/到期调度 | 保留，减少无意义唤醒和整页重建 |
| 主题对象 | MaterialApp 重用浅/深 ThemeData；外观改变不再反复创建相同主题 | 保留语义对象复用 |

资源编码明细：`.local/asset-encoding-unified-20261021.json`。
帧采样基线：`.local/unified-ui-baseline-20261021.json`。
改造后采样：`.local/unified-ui-after-20261021.json`，同一设备、相同临时预览入口与三轮切页。
原生解码与页面记录：`.local/unified-ui-native-final.log`、`.local/unified-ui-native-webp-final.log`。

改造后的第二/三轮构建 P90 为 5.17–8.86ms，基线为 6.33–11.05ms；但首次记录页构建峰值从 66.36ms 升到 137.51ms，个人中心从 119.96ms 降到 111.69ms，部分栅格帧仍超过 16.67ms。样本少且受调试 JIT、首次资源上传与模拟器影响，**不能据此认定整体帧率提高或首次切页卡顿已经消除**。动画连续移动、快速反向与减少动画行为已有测试；真机 Profile/Release 首帧和稳定帧率仍需另行验收。

58.3% 是将该封面限制为最大 1080 宽时的解码内存样本；实际解码宽度还随设备像素宽度限制，不是全 App 内存降低比例。

本轮验证不代表真实手机 Release 模式、长时间播放或复杂网络环境的帧率保证。

## 6. 验收与回退

- 78 项单元/Widget 测试覆盖账户、房间、邀请、记录收藏、导航、键盘、选集与布局。
- 主页面与设置页在 320/390/430 宽度、大字号及现有浅深主题下检查。
- 原生图库覆盖 27 个页面/路由的浅深主题、24 个状态和 4 个交互场景，共 82 张截图。
- 模态开合、快速反向切页、减少动画、滚动末项可达与错误/过期/满员状态纳入检查。
- SVG 图标与片库媒体资源引用增加静态存在性检查。
- 最终结果以 `.local/ui-native-result.json` 与 `.local/backup/unified-ui-20261021/verification.json` 为准。

备份：`.local/backup/unified-ui-20261021/`。
`apps/mobile/` 子目录保存本轮开始前的源代码与测试；`media-png/` 保存转换前 PNG；原森林背景单独归档。
回退只恢复本轮改动文件，并按编码清单恢复对应资源及引用；避免覆盖用户其他未提交工作。

### 修改文件、目的与影响

| 文件组 | 目的与影响 |
| --- | --- |
| `lib/design/`、`lib/app/`、`web/main.dart` | 统一主题、文字前景、弹层、动效与旧偏好迁移；共享组件的调用方式保持兼容 |
| `features/catalog/` | 个人中心、记录、收藏与详情的密度和层级统一；搜索、片库图片引用更新 |
| `features/experience/` | 外观、邀请、选集、聊天、设置沿用 token；减少邀请倒计时无效重建 |
| `features/rooms/` | 创建/加入、房间列表与详情统一布局；原鉴权与房间接口保持原实现 |
| `features/playback/widgets/player_library_view.dart`、`features/realtime/room_watch_page.dart` | 封面解码上限与音频弹层统一；播放引擎、双人同步与语音协议未改动 |
| `assets/design/media/` | 新增五张玻璃插图、删除森林背景、无损编码；关键封面保留 PNG |
| `test/`、`integration_test/`、`tool/ui-native.mjs` | 主题迁移、布局基线、资源引用、交互与原生截图验收 |

精确文件列表、任务开始前哈希与回退来源保存在备份目录的 `verification.json`。本轮没有修改依赖清单、后端、Playra 工程或全局控制配置。

### 最终状态

- DONE：页面定位、六组设计稿、五张插图、页面开发与森林偏好迁移。
- DONE：静态分析、78 项完整测试、最终辅助文字颜色调整后的 6 项专项回归。
- DONE：82 个原生页面/状态截图、最终普通调试 APK 构建安装、现有本地测试账户实际登录与个人中心检查。
- DONE：资源体积、封面解码内存与调试帧采样实验，保留有效优化并撤回关键封面 WebP 实验。
- NEXT（可选）：在真机 Profile/Release 模式继续定位首次切页与栅格超预算帧；本轮不将其标记为已解决。
