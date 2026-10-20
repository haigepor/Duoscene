# rooms

已实现分页列表、创建、邀请码加入、成员详情，以及房主生成/复制/撤销邀请。
room_repository.dart 通过 auth 的 Session 调用现有 REST 契约，不直接操作 token。

成员由手动刷新和前台恢复更新，尚无在线/播放状态推送。不依赖 voice 或 playback 的内部状态。
