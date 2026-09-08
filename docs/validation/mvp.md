# TEST-004 Android MVP 回归与书源维修演练

**状态：DONE（2026-09-08）。** 此报告验收应用功能链路与维护流程，不授予正式发布状态；ANDROID_MVP_DONE 仍需要 CI / RELEASE 后续任务，iOS 完整运行回归归 IOS-005。

## 离线回归与故障演练

默认全量测试 **393 项通过**，包括新增四项维修演练；静态分析无问题。无新增依赖，未改生产 Reader / Domain / Source / UI。本轮新增的 HTTP fixture、设备探针和运行脚本位于 integration_test / test，不进入生产 main。

| 破坏位置 | 触发 | 定位结果 | 缓存及重放 |
| --- | --- | --- | --- |
| Search | 列表条目缺少 title | parse / search | 一次请求即失败，不重试；现有缓存及用户库不变；恢复黄金协议后搜索成功 |
| Detail | 详情缺少 title | parse / novelDetail | 返回旧本地详情、isStale 与 refreshFailure；原 payload 不变 |
| Catalog | 必填 list 改名为 items | parse / catalog | 在卷列表失败后停止，不继续请求卷内章节；旧目录保留 |
| Chapter | body_snapshot 改名 | parse / chapter | 不拿预览替代正文，不覆盖旧正文；旧内容可离线读取 |

四项均通过真实 LightNovelSource → Repository → 临时文件 SQLite，检查每次失败只调用一次 adapter，书架哨兵不变，缓存 payload 不变。恢复原黄金协议后显式刷新成功，详情/目录/正文 cacheOnly 再读全部成功且零新增请求。演练“修复”是恢复已知协议重放，**不声称已经兼容未知的未来网站改版**，也不为假设的新字段增加生产 fallback。

## Android 真机链路

设备：BMH-AN10，Android 12 / API 31，ARM64，Profile，Flutter 3.38.4 / Dart 3.10.3。探针使用正式界面与数据层、真实 SQLite 文件与图像解码，仅 HTTP 响应与存储根目录为隔离测试数据。

- 首页启动与输入搜索词后，adapter 调用数为 0；按 Enter 后才执行搜索。
- UI 打开合成书详情，点击 Add to bookshelf，真实用户测试库得到一条收藏；Start reading 经过目录选择进入 BookReaderScreen，正文和合成插图可见。
- 真实手势滚动后，等候读取到非章首的已提交 ReadingProgress，再执行 Android `am force-stop`，没有依赖 Dart dispose 模拟进程退出。
- 新进程在禁止 adapter 请求的模式启动，保留书架与封面；继续阅读恢复同一 revision / blockKey / blockIndex / blockFraction，整个冷启动阶段 adapter 调用数为 0。
- 返回章首验证离线正文插图，使用可见 SourceImage 的解码结果与截图共同核查。

本轮 warm 合成 adapter 调用 9 次（搜索、详情、目录、正文、图片定位及读取），实际外网 0 次。强制停止前已提交 index=7、fraction=0.42391304347826086；冷重启后的初始持久位置及继续阅读位置完全一致。再次滚回章首 index=0，读到正文 image:v1 引用的解码图，冷阶段调用仍为 0。截图已人工核查合成插图、书架封面与恢复正文；Flutter error 记录为空。结构化证据见 [mvp-android.json](mvp-android.json)。

对应入口、隔离/恢复边界与命令见 [MVP 探针说明](../../integration_test/README-mvp.md)。没有切手机飞行模式，使用禁止传输的 adapter 做确定性离线验证；本轮不重复声称真实 TLS 或系统网络切换已重验。TXT / EPUB、外部导入、跨章、清理、失败回滚、布局与性能复用 [LOCAL-005](local-005.md)、[Android](android.md)、[UX](ux.md)、[DB-003](db-003.md)、[TEST-002](stability.md)、[TEST-003](performance.md) 及本轮完整 suite，未重复每个真机专项。

## 书源维修步骤

1. 先按 AppFailure 的 operation 定位 search / novelDetail / catalog / chapter / media；区分 parse 与 network / TLS / accessRestricted / rateLimited，不把权限限制当 parser bug。
2. 复现使用最小脱敏 JSON / 合成 HTML，保留必需字段、类型与顺序；不记录 Cookie、token、签名 URL、完整作品正文。先写失败 fixture，确认只在目标阶段失败，缓存和用户库不变。
3. 修复边界位于 `lib/data/sources/lightnovel/` 的 search / detail / catalog / chapter 解析器或 API envelope；已有通用模型和 Reader 不应为某站字段名而修改。只有真实协议证据才引入兼容分支，不猜新端点、不用 render_preview 冒充完整正文。
4. 运行该 parser 回归、维修演练、Repository stale/cacheOnly 与缓存保留测试。若改身份、MediaRef 或 parserVersion，另覆盖持久引用与升级；禁止清用户库来“修复”解析失败。
5. 只有离线结果不足以判断接入时，另执行显式 opt-in 的有界 live smoke：事先固定预算、串行、无重试，遇访问限制/验证码/付费/明确拒绝即停。定位成功也不代表获得内容再分发许可。

## 真实源证据复核

最新已记录真实完整链路为 **2026-09-07**：SRC-010（Windows 媒体跨进程），TEST-001 与 READER-007（Android MuMu 生产 Source / 正文 / 插图），详见 [源站记录](../source/lightnovel.md)、[reading-flow.json](reading-flow.json)。这些是历史实现与协议证据，不是 9 月 8 日 ARM64 真机当前在线可用性的证明。

核查本轮改动与此前任务：没有变更 Source endpoint、字段解析、身份或媒体定位规则，四阶段黄金协议与完整离线 suite 仍通过，未发现需要新增真实请求才能定位的问题。因此本轮新增真实源 HTTP **0**，不消耗/复用历史一次性授权，不循环请求直到成功。源站当前可达性 / 页面协议是否在历史验证后变化仍为 **NOT_REVALIDATED_LIVE**；后续发布前如需现时证据，再做一次有界 opt-in 验证。

## 缺陷与平台边界

- 本轮未发现新的可复现生产功能缺陷；不因此宣称无任何潜在问题。
- 仍未关闭的发布门槛：CI-002、内容/依赖/权限发布检查、正式签名 RC 安装升级及交接；不自动开始。
- iOS Level A：生产共享代码、依赖、模型、导航与存储接口本轮未变化；共享离线 suite 通过。Python UI 驱动明确仅用于 Android 测试，不进入应用。iOS 运行时仍 **NOT_RUNTIME_VERIFIED**，不将 Android 证据外推。历史报告中的 DEFERRED_NO_MAC 只描述当时环境，当前 Mac/Simulator 已存在。
- 正式内容源的新鲜度限制、此前用户主动跳过的整机磁盘写满/备份恢复，以及 iOS/签名工作保持原范围，不因 TEST-004 通过而被勾选为通过。

## 证据与环境恢复

`.tooling/evidence/test004-final/` 包含 `report.json`、`warm-reader.png`、`cold-home.png`、`cold-reader.png`、`cold-illustration.png`；日志为 `test004-final-device.log`、`test004-tests.log`、`test004-repair.log`、`test004-analyze.log`、`test004-build.log`。初轮已通过的基本链路保留在 `test004/`；最终轮补充指定正文媒体引用及离线插图断言，没有失败重试至偶然成功。

脚本删除自身 test004 测试目录与 UI dump，覆盖恢复此前 TEST-003 的生产 Release APK 并启动。没有卸载应用或清除生产数据；本轮没有生产代码修改，因此没有重复构建相同 Release 包。该包不是正式签名 RC。
