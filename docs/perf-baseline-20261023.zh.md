# 真机性能基线：Honor LLD-AL20（2026-10-23）

## 测量环境

- 设备：Honor LLD-AL20，Android 9，arm64-v8a，1080×2280（Kirin 659 / Mali-G71 MP2）。
- 构建产物：`output/android/duoscene-lan-arm64-profile-perf.apk`（Profile + `PERF_CAPTURE=true`，apiBaseUrl `http://192.168.0.4:3000`，与当日电脑 IP 一致，未重打包）。
- 后端：`.local/test-account` 便携 MySQL 8.4（33307）+ Fastify API（0.0.0.0:3000），账号 `test123` 会话自动恢复。
- 原始数据：`.local/perf/`（`ft-*.json` 各场景 FrameTiming 原始报告、`perf-*.png` 截图、`duoscene-performance.json` 首轮报告）。
- 工具：`scripts/perf-baseline.mjs`（可重复基线）；交互场景以每场景冷启 + 40s 应用内 FrameTiming 窗口采集。

## 测量边界（沿用 playra-performance-study 的纪律）

- 仅 Profile 构建数据作为证据；Debug/JIT 不作数。
- `am start -W` 只衡量 Activity 首次显示，不含登录恢复、片库与首帧全就绪。
- build/raster 超 16.667ms 是 60Hz 单阶段超预算参考，不等于实际丢帧率。
- 宿主 `gfxinfo` 统计不到 Flutter 帧（本轮实测恒为 0），Flutter 帧证据一律以应用内 FrameTiming 为准。

## 结果

冷启动 `am start -W` TotalTime ×3：**2685 / 2644 / 2720 ms**（Profile）。

| 场景（每场景独立冷启 40s 窗口） | 帧数 | build p50 / p95 | build 超预算 | raster p50 / p95 | raster 超预算 | raster max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| S1 冷启 + 首页加载 + 海报解码 | 229 | 1.68 / 10.56 ms | 6（2.6%） | 16.36 / 36.32 ms | **93（40.6%）** | 333.2 ms |
| S2 首页连续滑动 ×7 | 453 | 2.19 / 5.92 ms | 6（1.3%） | 16.44 / 32.22 ms | **211（46.6%）** | 107.9 ms |
| S3 短剧 Tab + 滑动 ×4 | 225 | 1.54 / 4.99 ms | 8（3.6%） | 9.29 / 35.53 ms | 36（16.0%） | 141.4 ms |
| S5 详情页加载 | 78 | 1.79 / 42.79 ms | 8（10.3%） | 13.91 / 52.36 ms | 35（44.9%） | 103.2 ms |
| S7 房间页视频播放 | 880 | 2.76 / 14.57 ms | 33（3.8%） | 17.09 / 25.80 ms | **498（56.6%）** | 159.8 ms |

内存（dumpsys meminfo TOTAL PSS）：详情页 ≈ 137–141 MB；播放中 ≈ **163 MB**（RES 296 MB，swap ≈ 0；Native Heap 基线 ≈ 36 MB）。CPU：静态页 ≈ 0%；播放中 ≈ **117%**（mpv 解码 + 音频，双核吃满）。

## 结论

1. **UI 线程全线健康**：所有场景 build p50 ≤ 2.8 ms，超预算 ≤ 10%；性能研究文档担心的 200ms 通知问题在本窗口未构成 build 瓶颈。
2. **raster（GPU）是系统性瓶颈**：首页稳态滚动 raster p50 ≈ 16.4 ms（一半帧贴 60Hz 预算线），播放中 56.6% 帧超预算；短剧信息流明显更轻（p50 9.3 ms）。实证了文档 P1#8 的假设：玻璃底栏 blur sigma 14 + 海报大图渐变 + 视频纹理叠加是主要 raster 成本，且在该档位 GPU（Mali-G71 MP2）上放大。优化方向应按文档先测层树、隔离重绘/缩小采样区域，而不是先动视觉设计。
3. **冷启动稳定**在 ≈ 2.7 s（Activity 显示口径）。
4. **内存收敛**：播放峰值 163 MB PSS，无泄漏迹象（多轮冷启数值一致）。
5. **片源可用性闪断被实测捕获一次**：`resolve` 的第二次详情往返失败 → 详情加载失败、播放按钮禁用。失败 UX 正确（禁用 + 重试），但暴露播放链路对上游的两次串行详情依赖——与 implementation-plan NEXT-5（目录缓存 + pending 合并）的优先级一致。
6. S4（误触分类 Tab）测得切换布局爆发 build p95 = 71 ms，属瞬态，量级可接受。

## 复现

```sh
# 后端（非管理员也可用 start.ps1；LAN 防火墙规则 Duoscene-LAN-API-3000 已存在）
pwsh -NoProfile -File .local/test-account/start.ps1 -BindAddress 0.0.0.0
# 基线（安装 + 冷启×3 + FrameTiming 拉取 + 内存）
node scripts/perf-baseline.mjs --install output/android/duoscene-lan-arm64-profile-perf.apk
```

交互场景的手动编排：`am start` 后在 40s 窗口内用 `input tap/swipe` 驱动目标页面，满 44s 后 `adb shell "cat .../duoscene-performance.json"` 拉取（先 `rm` 旧文件防串读）。
