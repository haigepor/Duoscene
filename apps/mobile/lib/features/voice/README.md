# voice

麦克风权限、PeerConnection 生命周期、静音和独立语音音量。平台音频适配由 app 协调；禁止改变电影权威时间线。

当前为模块边界，尚未实现功能。依赖方向为 app -> features -> core。
跨功能流程由 app 应用协调，不建立 feature 之间的循环依赖。
