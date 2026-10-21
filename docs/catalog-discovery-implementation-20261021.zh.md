# 分类发现页重构交付

日期：2026-10-21。依据 `output/design/catalog-discovery-20261021/` 的四类页面总览与筛选交互稿，采用现有 Flutter、DSPalette、DS、DSMotion 与电影票签，不增加框架或依赖。

## 结果

- DONE：仅推荐页保留整行搜索框、轮播、续播与房间邀请；电影、电视剧、动漫、短剧改成标题旁的搜索图标，进入相应类型搜索。
- DONE：筛选默认收起，展开后显示题材、片长／集数、排序；摘要实时更新，收起保留选择，重置恢复发现模块。各分类分别保留条件、片单顺序和浏览位置。
- DONE：紧凑 2×2 片单、横向海报、三列片库。每类文案遵循设计稿；候选不足四张时显示实际数量。换一组仅在本模块淡入更新，不重建下方片库。
- DONE：一个主 CustomScrollView 与 SliverGrid，按实际显示尺寸解码 WebP，接近底部后每次追加最多 12 条本地片目；按 ID 去重，到底结束，不循环复制内容。
- DONE：沿用统一的 `>` SVG；常规手机三列，200% 字号下片库两列、紧凑片单一列，筛选条件可横向浏览。标题操作保留 48dp 触控区域。
- DONE：动画沿用 220ms easeOutCubic；减少动画时直接切换筛选面板，避免零时长 AnimatedSize 在布局阶段重新标脏的断言。

## 文件与影响

| 文件 | 目的与影响 |
| --- | --- |
| `apps/mobile/lib/features/catalog/home_page.dart` | 分类头部、搜索类型、票签导航与分类状态所有权；推荐内容保持原逻辑 |
| `apps/mobile/lib/features/catalog/category_discovery.dart` | 新增分类页组合、条件查询、局部换组、懒构建片库和有限分批加载 |
| `apps/mobile/lib/features/catalog/home_content.dart` | 移除被新分类页取代的双下拉框／双列实现；保留推荐轮播、续播与横向分区 |
| `apps/mobile/test/home_content_test.dart` | 更新筛选交互验收，覆盖四类、深浅主题及大字号，保留推荐与导航回归 |
| `apps/mobile/test/category_discovery_test.dart` | 搜索类型、筛选／详情、时长边界、去重排序、换组滚动稳定与 40 条测试数据的分批结束 |

无鉴权、播放、数据库或 CatalogRepository 接口修改。图内扩展海报与元数据没有写入片库。

## 验证

- PASS：完整 `flutter analyze`；最后修改后的三个源文件定向分析也通过。
- PASS：最终 `flutter test --concurrency=2 --reporter expanded`，98 项全部通过，日志 `.local/catalog-discovery-tests.log`。
- PASS：Android 14 雷电测试实例 `127.0.0.1:5557`，真实本地账户登录；四分类切换、科幻筛选、收起、条件保留、重置、三列片库结尾在底栏上方可达。
- PASS：正常入口 APK 构建、安装与热更新成功。模拟器／ADB 曾中断，已恢复测试实例和本地 API，重新连接 Flutter 调试。
- PASS：原生字体回退造成约 1px 海报底部溢出，已通过向上取整并预留行高解决；最终原生截图无溢出标记。
- 环境记录：并行复核曾中断，随后 Windows 构建缓存 `libmpv-2.dll` 清理失败。保留该生成文件到本轮备份目录并让工具重新生成后，串行完整测试通过。没有修改媒体插件、SDK 或项目依赖。

原生截图目录 `.local/screenshots/catalog-discovery-20261021/`：

- `03-movie-final.png`：电影发现页与更新后的向前箭头。
- `04-filter-expanded.png`、`05-filter-results.png`：展开与收起结果。
- `06-tv.png`、`07-anime.png`、`08-short.png`：其他分类。
- `09-three-column-end.png`：三列片库及可达结尾。
- `10-ready-to-test.png`：测试结束后返回电影发现页。

## 数据边界与回退

当前静态片库仅 13 部，每类 3–4 部，因此正常数据会很快到底。“换一组”在现有小片库中轮换顺序；有更多候选时才会带入更多片目。本轮分批加载是真实的本地有限列表追加，40 条独立测试数据验证了 12→24→36→40 与不再重复追加。远程分页、更新时间／热度排序和个性化推荐尚无数据服务，不能据此声称已接入。

原生调试截图和 debug 启动不等于真机首帧／帧率基准，本次没有给出性能提升百分比。公网与双人同步不属于本轮回归。

回退来源 `.local/backup/catalog-discovery-implementation-20261021/`：保存本轮修改前的三个既有文件、状态清单、范围契约和差异。需要回退时仅恢复这些文件，并移除本轮新建的分类组件／测试；保留用户之前的所有修改，不使用 HEAD 覆盖整个工作区。

NEXT（可选）：有真实资源接口后接入远程 cursor、hasMore、失败重试和更新时刻字段。
