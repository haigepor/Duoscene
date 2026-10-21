## 1. Research
- [x] DONE 1.1 固定两个工作树、设备、产物、回滚和性能测量边界。
- [x] DONE 1.2 核对播放器既有移植范围，绘制启动/内容/播放链路；26/26 原始源文件哈希匹配。
- [x] DONE 1.3 对比图片、分页、通知、Tab 可见性、播放协调及缓存。
- [x] DONE 1.4 读取 APK 实物，记录包体积分解与单 ABI、符号、资产边界。
- [x] DONE 1.5 建立 Honor Debug/Profile 单轮真机基线，记录原始帧及测量限制；未将其当作长期收益。

## 2. Design
- [x] DONE 2.1 交付有源码位置的借鉴清单、不可直接搬用项、优先级与验收预算。
- [x] DONE 2.2 选定构建结构压紧、Profile LAN 与显式帧采集作为首片；保留源码/设备回滚点。

## 3. Implement and verify
- [x] DONE 3.1 复现 Debug ZIP 空洞并压紧，结构减少 29.51 MiB；完成 Profile 构建与开发帧采集回归。
- [ ] NEXT 3.2 内容/图片/通知/播放协调按独立切片继续；先做受控 GPU 定位、详情与目录复用，再实施同键合并、总预算/取消和 prepared 身份校验。
- [x] DONE 3.3 完整 379 项测试、30 张原风格加 6 张独立短剧变体、LAN 就绪及原生封面/真实筛选/首集播放验证；覆盖安装后 1 收藏及 5 历史与回滚证明完全一致。
- [x] DONE 3.4 最终普通 Profile 104,820,026 B，同签名覆盖安装、设备/产物 SHA-256 匹配；默认采集关闭，报告明确非正式 Release。
- [ ] NEXT 3.5 滑动连续换集、弱网/取消、长时播放、快速往返、同步房间性能和第二台 Wi-Fi 设备独立验收；目前不宣称完成。

证据：`docs/playra-performance-study-20261022.zh.md` 与 `.local/performance-study/delivery-proof.json`。本 change 尚未完成，不归档；研究与第一切片已完成，剩余工作列为 NEXT，不将 raster p95 35.054 ms 写成流畅达标。
