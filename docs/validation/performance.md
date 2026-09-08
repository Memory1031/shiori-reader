# TEST-003 Android Reader 与启动性能验收

状态：DONE（2026-09-08）。BMH-AN10 Android ARM64 真机 Profile 验收通过，无需调整性能阈值；补齐进度标签 4Hz 展示预算。iOS：**NOT_RUNTIME_VERIFIED**，留 IOS-004 / IOS-005。

## 环境与测量边界

- BMH-AN10，Android 12 / API 31，arm64-v8a，1080×2400，DPR 3，系统唯一上报显示模式约 60Hz。没有 120Hz 模式，故不宣称高刷性能通过。
- Flutter 3.38.4 / Dart 3.10.3，Android Profile APK；全部使用离线合成内容、隔离 SQLite 与生产图片持久层。无真实 Source 请求，无整机磁盘写满，无用户数据删除。
- [探针与复跑说明](../../integration_test/performance/README.md)；[结构化测量摘要](performance-android.json)。ProductionApp 新增可选存储路径解析函数，默认仍解析 production 路径；阅读器另修复下述标签限频；计时、手势、VM service、合成内容均在独立 integration_test 入口，不进入生产 main。

## 本轮修复

`ReaderContentView` 原先每次位置采样都更新进度标签，缺少计划中的约 4Hz 展示限制。新增离线 widget 回归在 600 次、每次间隔 16ms 的采样中复现 **599 次**展示通知；修复后由可取消的 250ms 定时器合并为不超过 40 次。真实 `session.sampleProgress` 仍接收每次样本，进度面板使用独立保留的最新位置，退出时取消定时器。

回归同时验证进度面板立即看到最新的 95%，而非等待标签刷新。该改动不修改正文布局、颜色、数据库写入规则或语义位置。修复后重跑全部离线测试与受影响的三轮真机滚动；图片循环和冷启动保留此前有效结果。

## 结果

### 10 万字正文：3 次各 10 秒连续滚动

每次使用 2000 个、各 50 字的语义块，从章首移动 6000 logical px；实际到达 blockIndex=59。只在正文 Scrollable 注入匀速 drag，不靠主机 swipe 时序。超过 300 帧、正文位置前进、发生进度写入是探针有效性前提。

| 轮次 | 帧数 | UI p95 | Raster p95 | UI / Raster 最大值 | 常规成功写入 | 退出额外写入 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 609 | 4.571ms | 4.952ms | 8.044 / 6.869ms | 6 | 0 |
| 2 | 609 | 4.566ms | 4.955ms | 7.073 / 11.596ms | 5 | 0 |
| 3 | 609 | 4.470ms | 4.865ms | 6.512 / 6.558ms | 5 | 0 |

三轮 UI / raster 均没有超过 16.7ms 的样本，满足 60Hz gate。每轮仅新构建 59 个阅读单元，采样结束挂载 11 个；ReaderContentView Widget 身份保持不变，未重建整章树。成功写入计数来自调用真实 SQLite LibraryRepository 的薄包装，测量窗口包含末尾 400ms settling / trailing；均符合 10s 常规写入 ≤6 次。退出前 trailing 已落盘，因此本轮退出额外写入为 0，不代表生命周期永远无需 flush。

### 500 项书架进程冷启动

预先向隔离用户库写入 500 本无封面合成书，再关闭数据库；每次 force-stop 后走真实 ProductionApp（含数据库、偏好、导入订阅、SourceServices 初始化）到真实 BookshelfView 数据就绪并完成布局。封面解码压力由下方图片场景单独覆盖，本场景不代表 500 张封面同时解码。

| 轮次 | Dart main 到书架就绪 | 主机启动命令到观察到就绪的上界 | Android Activity TotalTime |
| --- | ---: | ---: | ---: |
| 1 | 447ms | 1105ms | 750ms |
| 2 | 458ms | 1023ms | 679ms |
| 3 | 412ms | 1068ms | 718ms |

三次均低于 2s 目标。主机上界包含 adb 往返与轮询；Activity TotalTime 只作首屏参考，不替代书架就绪时间。这里是进程冷启动、OS 文件缓存可能温热，不声称系统重启后的存储冷缓存。就绪定义是生产书架控制器 ready、500 项加载完成和布局完成，没有把启动占位页当完成。

### 深恢复与极长单段

- 2000 块中恢复到第 1500 块（index 1499）准确；只构建/挂载 11 个阅读单元，未构建前面 1499 块。
- 十万字单段：横向恢复 75%，只测量 5 个 chunk；转纵向得到 74.994%，构建 3 个单元，误差约 6 个字符。
- 语义 chunk 不改变原文与 blockKey 的 host 回归继续通过；上述为真机功能与懒构建证据，不将其解释为未测量的恢复毫秒时延。

### 20 图、10 次章节会话

每章 20 个独立 MediaRef，内容为 19 张 1200×1800、一张 1200×6000 的不同 PNG；10 个章节会话重复阅读该组图。每个目标 SourceImage 均等待其 RawImage 解码，再切到下一图，累计 200 次目标图验证。退出章节释放 ReaderScreen / 解码作用域后请求 VM GC。文件按内容去重沿用生产行为；不冒充 200 张不同原图下载测试。

| 指标 | 第 3 次 | 第 10 次 |
| --- | ---: | ---: |
| GC 后 Dart heap | 14.65 MiB | 14.78 MiB |
| GC 后观测 RSS | 230.88 MiB | 235.71 MiB |
| VM external | 291696 bytes | 291696 bytes |
| 图片编码内存保留 | 0 | 0 |
| 未关闭 Source body | 0 | 0 |

- 100ms 周期 RSS 采样峰值 **364.46 MiB**；周期采样可能漏掉更短峰值，不冒充全局精确峰值。
- 第 3–10 次 RSS 在 230.88–239.83 MiB 间波动，第 9 次回落至 233.23 MiB，第 10 次相对第 3 次增加约 4.83 MiB（2.1%），没有持续逐次增长或 OOM。
- Dart heap 增加约 0.14 MiB；探针保留逐帧记录、10 章缓存元数据与结果，不能声称 heap 完全恒定。结合 external 恒定、所有周期编码内存/body 归零、RSS 波动回落，未观察到图片缓冲随切章累积。该结论限本次 10 轮，不是任意长时间泄漏证明。
- 最大全部已观察解码图为 **3,997,968 pixels**，符合 400 万像素上限。这里检查解码像素，未用压缩文件大小推断图像 RAM。

## 其余预算与验证

- 全量离线回归 **389 项通过**；最终探针静态分析无问题，Profile 构建与真机执行通过。
- 调度预算复用 `test/data/network/request_scheduler_test.dart` 中全局 2 / 后台 1、前台优先与取消回归。此次合成媒体并非真实 HTTP，因此不把合成 Source 调用数当真实网络并发 trace。
- Chrome 与正文 rebuild 隔离复用 `reader_screen_test.dart`，本次实际滚动补充 Widget 身份与懒构建证据。进度 label 的 4Hz 限频由本轮 `progress_frequency_test.dart` 补充验证；未新增逐帧序列化逻辑。
- 不新增依赖、isolate 解析或架构 ADR：本轮无性能热点证据支持这些修改。共享代码变更为组合根可选路径注入与 Flutter 展示定时器，Dart / Drift / path_provider 接口不变；iOS 只做兼容审查，未运行性能探针。Windows 本轮未执行。

## 原始证据与测量纠错

有效冷启动：`.tooling/evidence/test003/cold.json`。修复后有效滚动：`.tooling/evidence/test003-fixed/report.json`、`timeline.json`（32557 个 Dart/GC trace events）。有效图片循环：`.tooling/evidence/test003-final/report.json`、`timeline.json`（32508 个 events）、`meminfo.txt`、`test003-final-device.log`。逐帧数据位于 report 的 timingsUs，避免只留下 p95 而无法核查样本。

探针开发阶段发现并修正了惰性计时器初始化、默认横向模式、选错 Scrollable，以及合成图片内容重复导致缓存过度复用。静止正文的 21 帧/0 写入数据作废，早期两种图片内容的循环不用于本报告。最终有效数据要求正文实际前进、有成功 SQLite 写入，图片为 20 种内容。不是通过降低阈值让无效样本通过。

验证脚本已删除其专用 test003 目录；验证后安装包含标签限频修复的生产 Release 包，原书架与进度不变。该包仍为本机调试证书后备配置，不属于正式签名 RC。TEST-004 未自动开始。
