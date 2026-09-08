# 本地导入：身份、托管存储与文件接收

> iOS 状态更新（2026-09-08）：Mac / Simulator 已可用，当前证据见 [IOS-001 报告](validation/ios-001.md)。正式应用启动证据及 LOCAL-002 原生验证分开记录，后者见 [LOCAL-002 报告](validation/local-002.md)。系统分享面板及扩展交接已补验；Files 实际选中文件和签名真机矩阵仍待验。下方带日期的 `DEFERRED_NO_MAC` 等结论是当次历史记录，不代表当前环境。

LOCAL-001 已交付存储基础与解析器提交契约；LOCAL-002 增加文件选择、外部接收与导入编排，详见文末。LOCAL-003 / 004 已接入 TXT / EPUB 实际解析，详见 [解析支持范围](local-parsers.md)；LOCAL-005 已接入书架 / Reader 闭环，见 [验收记录](validation/local-005.md)。未实现在线整书下载。

## 身份与内容边界

- 保留 `SourceId('local')` namespace，`NovelKey.novelId` 为原文件完整字节的 SHA-256。文件名、外部路径、标题、格式选择和排版不参与身份；同文件重复导入返回已有记录，不重新解析、覆盖正文或更新进度。同名不同文件是不同书籍。
- `LocalBookIdentity.chapter` 对解析器提供的稳定定位符生成 ID。TXT 使用原始章节起点的 code-point offset；EPUB 使用规范化 spine href。具体切章及 href 规范化由 LOCAL-003 / 004 固定，不得使用显示标题、屏幕页码或临时解压目录。
- `ChapterContent` 沿用既有 blockKey / contentRevision 算法。`LocalBookContent` 提交完整 Detail、Catalog 和按目录顺序的 Chapters；提交校验同书归属、章数量 / 顺序及所有封面 / 插图均为本次托管资源。
- LOCAL-004 用独立的 LocalNavigationEntry 树保存 nav / NCX 与语义块映射，不改变 Catalog 的唯一 spine 章序；LOCAL-005 已接入实际点击跳转，缺失 fragment 从章首开始。
- `MediaRef` 无需增加平台路径或 URL 字段：本地资源使用 `local` SourceId，mediaId 为 `书籍摘要/资源字节摘要`。这里是逻辑引用，数据层自行解析；搬迁应用根目录后引用不变。

## 接口与生命周期

纯 Dart 契约位于 `lib/domain/contracts/local_books.dart`。`LocalBookStore.importBook` 接收原文件字节流、格式、取消 token 和异步解析回调；回调获得短生命周期 `LocalImportSession`，通过 `openOriginal()` 读取已暂存原文件，`writeMedia()` 流式提交资源，返回不可变 `LocalBookContent`。

解析回调必须等待自己的工作、协作检查取消，不得在回调结束后继续使用 session。媒体写入串行，结束时收束全部已登记写入。外层导入、书籍读取、媒体读取都返回 Result，IO / SQL 异常不跨领域边界。取消发生在 DB 提交前时回滚；提交后返回真实成功，不声称已取消。

`read` 只返回已发布书籍，未导入为 Success(null)；缺失 / 损坏的已发布文件为失败，保留原数据以便后续修复，不静默删书。`readMedia` 校验文件包含性、长度及字节摘要后返回只读字节，不访问 Source。

`LocalDatabases` 持有唯一 ManagedLocalBooks，在数据库打开后初始化并回收残留，关闭时先等待本地导入存储再关闭 DB。LOCAL-005 的 LocalReadingRepository / LocalImageRepository 在在线装饰器之前按 `local` 身份分派到本契约，图片交付既有 MediaLease；在线 NovelRepository / ImageRepository 的签名不变。不能把本地导入送入在线缓存装饰器或纳入 LRU。

## 文件、数据库与恢复协议

存储布局（均相对于 AppPaths.root）：

```text
users/users.sqlite                         # 用户库 v3，local_books 导入索引
users/import-staging/import-随机目录/      # 本次原文件、规范化正文、资源
users/books/<原文件 SHA-256>/
  original                                # 保留原始文件字节
  manifest.json                           # codec v1：格式、时间、详情、目录、正文、资源集合
  <资源 SHA-256>                          # 图片原始字节
disposable/                               # 在线缓存，所有权完全独立
```

不保存外部绝对路径、临时访问授权或 ZIP entry 文件名为落盘路径。用户库 v1 / v2 增量升级到 v3：增加 local_books 表，不重建已有表；历史 v1 / v2 snapshots 保留，新增 v3 snapshot。cache.db 仍为 v2。

提交顺序：

1. 限量复制原文件并计算摘要；已有提交则返回原记录。
2. 在暂存目录解析、写入图片、验证整体归属，flush 所有输出；manifest 存储现有 RecordCodec 字符串，不复制领域实体格式。
3. 同一私有文件系统内 rename 到最终摘要目录。
4. 在 users.db 事务内插入格式、标题、导入时间与 manifest SHA-256；该事务是唯一发布点。

文件与 SQLite 不假装是一个原子事务。步骤 1–3 中断无可见导入记录；步骤 4 失败时删除未发布目录，清理失败留待重开。重开先成功读取索引，再回收暂存目录及无索引摘要目录；DB 无法读取时停止，不据此误删文件。已提交目录永不因恢复或缓存清理而删除。操作串行，要求一个应用生命周期一个 owner，不支持多个进程同时执行导入 / 回收。

写入使用 flush + rename + SQLite transaction，覆盖进程终止 / 事务失败；不宣称已证明设备突然断电时文件系统的持久顺序。备份恢复若出现索引与文件不一致，读取明确失败并保留记录，不发布空内容。

路径检查允许应用私有根目录的系统别名，但拒绝托管子目录 / 文件的链接逃逸。清理只操作已验证父目录下的直接子项，链接本身被移除而非遍历其目标。

## 容量与所有权

当前工程硬上限：原文件 128 MiB、单资源 32 MiB、导入原文件及资源累计 512 MiB（重复资源也计入处理预算）、manifest 32 MiB、最多 4096 次媒体写入。实际字节数超限即停止，不只相信元信息。整体提交还检查 manifest 加总大小。后续解析器须另外限制 ZIP 展开比、条目数和 HTML / TXT 解析成本，存储上限不代替解析防护。

移出书架只操作 bookshelf；清理历史只操作 progress；清理缓存只操作 disposable / cache.db。它们均不删除本地托管文件。LOCAL-005 增加独立的“本地文件”管理页与删除确认，不能复用“移出书架”。

Android 使用已有 Application Support 私有目录，用户数据备份规则不排除正式 books。临时 import-staging 排除备份，iOS 同样应排除该可恢复暂存区；iOS 备份属性及备份一致性实测归 IOS-005 / ANDROID-002。没有新增 Native 依赖，沿用 Dart IO、crypto、Drift、path_provider，Android / iOS 最低版本不变。

## 验证记录

离线测试覆盖去重、同名不同文件、SQL 事务失败、模拟 IO 失败、等待输入时取消、提交前取消、重开回收、目录搬迁、缓存 / 书架删除隔离、资源损坏 / 路径拒绝、容量上限及 v1 / v2 迁移。模拟 IO 失败不代表实际填满手机磁盘的验证。

Android 探针 `integration_test/local_books_smoke.dart` 使用单独 local001-probe 开发目录和自制字节，不导入真实 Source。2026-09-07：新增 10 项本地存储测试，连同已有 v1 迁移及完整回归共 **320 项 PASS**；analyze 无问题。

MuMu Android API 32 首次 `LOCAL001_PREPARE_AND_REOPEN_PASS`，最终探针版本两次 force-stop / 新进程得到 `LOCAL001_COLD_REOPEN_DEDUP_MEDIA_PASS`（PID 18031、18166）。验证原文件提交、normalized chapter 身份重开、去重不重调解析器、媒体原字节跨进程读取；不是 TXT / EPUB 真实解析或图片 codec 验收。

排查中初版有 FAIL 标记：根目录系统别名导致过严路径判断，已改为对托管根下资源进行 canonical 校验；另一次未分类 FAIL 未记录具体异常，后续增加仅输出阶段 / 异常类型的诊断，最终连续两次冷启动 PASS。没有真实书源请求，没有清空现有书架 / 历史。

iOS Level A 代码兼容审查完成，runtime 仍 DEFERRED_NO_MAC，未宣称 iOS 真机通过。Android 真机磁盘满 / backup-restore / 断电持久性未实测，归 ANDROID-002；模拟器结果不替代这些验证。

验收结束已用 `lib/main.dart` 构建普通 Android Debug 包并 `install -r` 成功替换探针；未自动启动真实书源页面。没有开始 LOCAL-002。

## LOCAL-002：文件接收与导入编排（2026-09-08）

新增首页文件入口，以及不会替换 Navigator / Reader 的根级提示。外部接收只显示待处理提示，用户可“稍后”，由用户确认后才调用导入。中英文文案来自 ARB；扩展使用独立 en / zh-Hans Localizable.strings。面板支持滚动与大字号。复制和文件 I/O 在后台执行；取消会等待复制 / 解析收束，再删除对应 receipt，提交后的成功优先于迟到的取消。

领域层 `ImportSource` 只暴露不可变文件候选、事件、流式读取、确认与取消；不泄露 URI、平台权限或路径。数据层 `PlatformImportSource` 持有 native 返回的应用自有文件路径。应用装配显式注入源、LocalBookStore 和解析器映射。LOCAL-002 验收时正式解析器映射为空，fake parser 仅用于测试；后续 LOCAL-003 / 004 已以 BookDecoder 接入生产实际解码、章节和 EPUB 结构校验，新增编码预览和明确格式错误。

### 平台接收与持久交接

- Android 使用 ACTION_OPEN_DOCUMENT、ACTION_VIEW、ACTION_SEND / SEND_MULTIPLE。只接收单个 content URI，在临时读取授权仍有效时通过 ContentResolver 流式复制到 noBackupFilesDir/import-inbox。不请求全盘存储权限，也不依赖永久 URI 授权。
- iOS 使用 UIDocumentPicker、TXT / EPUB 文档类型关联和 Share Extension。主应用用 security-scoped access / NSFileCoordinator 读取；扩展在 NSItemProvider 的临时 URL 回调返回前完成副本，不将临时 URL 留给之后的异步任务。
- 双端共享“working → pending”目录发布协议：只保留一个待处理文件，receipt 含随机 ID、显示文件名及真实字节数；payload 使用固定内部文件名。读、写和 ack 受文件锁保护；iOS flock 跨扩展与主应用进程。部分复制不暴露，重开在获取锁后清理 working。已有 pending 不被新文件覆盖，多文件或繁忙明确提示重新处理。
- app 启动 / resume 查询持久 pending；事件只负责提示，不作为唯一数据源。只有成功提交或明确取消才按 ID 回收；陈旧 ack 不删除新候选，重复 ack 无害。提交成功但 ack 失败时保留 receipt，下次用既有 SHA-256 去重恢复，不重复解析 / 覆盖进度。
- 外部接收不自动导航；打开中的 Reader 继续保留。扩展完成后告知用户打开 Shiori 确认，不使用未保证的“扩展强行拉起主应用”方案。

### 限制与错误

入口副本按实际读取字节限 128 MiB，单槽最多保留一个 128 MiB 文件；解析服务额外复制原文件，因此峰值须预留两份原文件空间及 LOCAL-001 的资源 / manifest 预算。空间不足按读写错误返回可恢复提示，清理部分副本，允许重新选择；不承诺只凭元信息就能准确预估剩余空间。

扩展名和 MIME / UTType 仅作初筛。Dart 流检查空输入、实际大小、EPUB ZIP 魔数、TXT 的 ZIP / 二进制伪装（容许 UTF-16 BOM）；这不能代替 TXT 解码或 EPUB 合法性校验。失败保留完整 pending 以便重试或取消；纯链接 / 不支持格式、多文件、权限失效、繁忙、取消、空间错误均使用封闭错误词汇，不把底层异常或外部路径显示给用户。

### iOS App Group 配置

主应用和 ShareExtension 的 `SHIORI_IMPORT_GROUP` 必须一致，当前开发占位为 `group.dev.shiori.reader.import`；各自 entitlements 声明该组，Info.plist 通过 build setting 读取。扩展 Bundle ID 为 `dev.shiori.reader.ShareExtension`，最低 iOS 15，与主应用一起嵌入构建。签名真机必须为自己的 Team 注册两个 App ID、同一个 App Group 并更新 provisioning profiles；改变发布身份时同步两个 target，不能只改 Dart 常量。发布版本升级时同步扩展的 MARKETING_VERSION / CURRENT_PROJECT_VERSION。

App Group 的 ImportInbox 排除备份；正式书籍仍由主应用用户库管理。扩展不直接打开 SQLite、不解析正文。该协议覆盖进程中断恢复，不宣称已证明突然断电时的持久写入顺序。

证据、重现命令与未验项见 [LOCAL-002 验证记录](validation/local-002.md)。iOS 原生测试与真实分享 UI 证据分别记录；Files、云文档提供者及签名真机的剩余矩阵归 IOS-005。

## LOCAL-005：上架、阅读与删除

生产导入传 `addToShelf: true`，书籍索引与书架行在同一用户库事务发布；任一写入失败则回滚并清理本次目录。契约默认 false 保留独立存储调用语义。重复导入复用已有内容、导入时间和进度，并保证书架存在，保留已有 addedAt。

导入成功可“立即阅读”，首页书架与“更多 → 本地文件”均可继续阅读。本地文件页可重新上架，也可确认删除托管原文、规范化正文、图片、书架及进度；外部原文件不受影响。删除事务推进 progress_sessions generation，防止旧 Reader 或稍后重导入后恢复已删进度。清理目录失败时书籍仍从 UI 消失，并提示下次启动重试清理；未索引目录由启动恢复回收。

本地 Repository 的详情 / 目录 / 正文在所有 ReadMode 下只读托管文件，返回 LoadOrigin.local；更新流为空。图片以验证过的 MemoryMedia 租约进入统一 SourceImage 解码器，旧租约在删除后仍可用，新请求失败。媒体读取只检查发布索引与摘要，不逐张反序列化整本书。manifest 解码与验证在可取消 worker 中完成。在线缓存清理和预取不涉及这些文件。

目录独立保留 nav / NCX 层级与顺序；前后章使用 Catalog spine 顺序。目录项携带 ChapterKey / blockKey，复用 BookReaderScreen、ReaderController、ProgressTracker，显式目标覆盖历史位置；继续阅读不覆盖历史位置。翻页与滚动共用语义锚点，缺 fragment 章首降级。详细证据与未验范围见 [LOCAL-005](validation/local-005.md)。
