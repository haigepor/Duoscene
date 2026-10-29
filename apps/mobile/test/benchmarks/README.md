# 性能与加载探针

在仓库根加载 `scripts/mobile-env.ps1` 后，切到 `apps/mobile` 执行。文件不以 `_test.dart` 结尾，普通 `flutter test` 不发现这些探针，也不会请求外部来源。

```powershell
flutter test test/benchmarks/loading_benchmark.dart --no-pub --reporter expanded
flutter test test/benchmarks/player_rebuild_benchmark.dart --no-pub --reporter expanded
flutter test test/benchmarks/provider_live_probe.dart --no-pub --dart-define=LIVE_PROVIDER_PROBE=true --reporter expanded
```

- `loading_benchmark.dart`：7 轮，每轮新的 provider，详情请求固定 60ms、筛选请求固定 240ms；保留真实协议编码/解码、目录与身份检查。统计详情页后切 6 集、并发失败合并和分类首次请求。结果不包含媒体下载、解码和渲染首帧。
- `player_rebuild_benchmark.dart`：7 轮，各推进 25 次进度、再保持 25 次状态不变；统计真实 PlayerPage presentation 调用与会话通知，验证进度条最终位置。它测重建次数，不测 FPS。
- `provider_live_probe.dart`：显式运行的真实元数据探测，连续 3 轮推荐、电影分类、首次详情、缓存详情；不输出片目、凭据或媒体地址，不打开视频。源站失败使探针失败，保留阶段和错误码。

三者输出 `PERF_RESULT:` 后的 JSON。对照原始样本、切片顺序与限制见 `docs/playra-architecture-performance-20261023.zh.md` 和 `docs/performance/20261023-results.json`（均相对于仓库根）。同一机器与模式复测，避免将缓存命中或测试进程耗时写成手机首帧。
