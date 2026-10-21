## Goals and boundaries

以已恢复原样式的当前工作树和 `duoscene-style-restored-arm64-debug.apk` 为回滚点。追剧喵只作为同源数据显示与交互参考，不复制其整套视觉，也不自动点击广告、登录、升级、付费或账号操作。

## Research evidence to collect

1. 比较相同 vod_id 在原始响应、Duoscene 模型、实际图片 HTTP 与参考 App 的差异，区分 URL 被丢弃、网络失败和图片格式/解码问题。
2. 记录参考 App 的分类项、筛选维度与结果；通过少量只读请求核验服务端参数、分页和返回字段。不得把加载第一页后的本地筛选宣传为全库筛选。
3. 短剧现有结构是 PlayerPage → Scaffold → SafeArea → presentation，外层 AppShell 已有 extendBody 和底栏 inset；必须调查重复消费安全区、控件/手势冲突和播放器重复创建，不先认定解码引擎错误。
4. GitHub 官方仓库和 Context7 已开始调研，正式选型需记录当前来源、许可、支持平台、预载/缓存能力与集成成本。

## Implementation direction

先修数据与呈现边界，再处理短剧播放控制；图片安全策略不放到通讯后端。所有新平台/播放器行为采用明确状态和实际会话所有权。暂不承诺更换内核，研究完成后在本文件记录选择与依据。

## Verified decisions

- 选择保留 media-kit/PlaybackSession，以短剧专用 Video 表面与控件替代长视频手势层，不引入第二个播放内核。video-pool、better_player_plus、Chewie 与 Media3 官方示例的许可、能力和成本见 `docs/provider-rendering-refinement-20261022.zh.md`。
- 短剧默认选分集线：600318 的 BBA 为 40 集，备用直连为 1 集；支持显式换源。内层移除 bottom padding，信息继续使用外层底栏 inset。
- 筛选仅接入实测有效的 class/area/lang/year，选项来自 nav；不冒充支持被源站忽略的热度/评分参数。请求代次隔离过期响应，本页片名排序明确标注。
- 图片仅升级两条精确主机规则；豆瓣公开请求头通过独立有界加载器使用 set 语义，避免 Flutter NetworkImage 的头部追加差异。失败封面提供手动重试，不使用后台图片代理。
- 新增优先 LAN 切片：API 0.0.0.0，数据库保持 127.0.0.1；防火墙限同子网/程序/网卡/端口，私网 HTTP 仅为显式调试选项。没有改变正式认证或 Release HTTPS 策略。

## Visual regression acceptance

原版 36 张基准保留。因本次用户明确授权变化的短剧页及其覆盖层，可创建独立的批准变体；不得更新其他原版基准来掩盖回归。
