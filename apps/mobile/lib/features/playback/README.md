# playback

播放器适配、同步校时、generation 隔离、缓冲报告和漂移修正。UI 只发意图，服务端 snapshot 驱动状态；此模块不负责麦克风或 WebRTC。

当前为模块边界，尚未实现功能。依赖方向为 app -> features -> core。
跨功能流程由 app 应用协调，不建立 feature 之间的循环依赖。
