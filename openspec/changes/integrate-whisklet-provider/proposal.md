## Why

Duoscene 当前片库使用虚构设计数据，不能从影片详情解析真实剧集。用户提供的 Whisklet SDK 已实测具备片库和播放能力，需要作为首个真实播放源接入，但不把采集、解密或媒体代理职责放入通讯后端。

## What Changes

- 在 Flutter 内增加独立、可测试的 provider、协议 codec 和影片/线路/剧集模型。
- 真实会话默认使用第一播放源；设计预览继续使用静态夹具，远端失败不得伪装成本地成功。
- 接通推荐、分类分页、搜索、详情、选线选集、解析播放和本机收藏历史。
- 封装并验证全部 17 个 SDK 方法；广告、上游更新与 HTML 不自动执行。
- 增加可复现接口巡检、协议回归测试及最小 Android HTTP 白名单。

## Capabilities

### New Capabilities
- `frontend-media-provider`: 前端片源协议、浏览、播放、错误边界与本机记录。

### Modified Capabilities
无现存 OpenSpec 能力需要修改。

## Impact

影响 apps/mobile 片库、播放入口、图片展示、本机记录与 Android 网络策略；增加 Dart 密码学依赖及回归测试。apps/api、packages/contracts、数据库、账户策略和原 SDK 包保持不变。房间仍仅同步现有媒体地址和播放指令，不作为片源代理。
