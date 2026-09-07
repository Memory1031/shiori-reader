# LOCAL-001：本地书籍身份与托管存储

本任务只交付存储基础与解析器提交契约。文件选择、外部应用打开、TXT / EPUB 解析以及书架 / Reader 路由分别留给 LOCAL-002..005；当前没有新增用户可见导入入口，也未实现整书下载。

## 身份与内容边界

- 保留 `SourceId('local')` namespace，`NovelKey.novelId` 为原文件完整字节的 SHA-256。文件名、外部路径、标题、格式选择和排版不参与身份；同文件重复导入返回已有记录，不重新解析、覆盖正文或更新进度。同名不同文件是不同书籍。
- `LocalBookIdentity.chapter` 对解析器提供的稳定定位符生成 ID。TXT 使用原始章节起点的 code-point offset；EPUB 使用规范化 spine href。具体切章及 href 规范化由 LOCAL-003 / 004 固定，不得使用显示标题、屏幕页码或临时解压目录。
- `ChapterContent` 沿用既有 blockKey / contentRevision 算法。`LocalBookContent` 提交完整 Detail、Catalog 和按目录顺序的 Chapters；提交校验同书归属、章数量 / 顺序及所有封面 / 插图均为本次托管资源。
- EPUB nav / NCX、fragment 与语义块的映射仍由 LOCAL-004 / 005 完成；本任务不把现有 Catalog 冒充已经具备 EPUB 片段导航。
- `MediaRef` 无需增加平台路径或 URL 字段：本地资源使用 `local` SourceId，mediaId 为 `书籍摘要/资源字节摘要`。这里是逻辑引用，数据层自行解析；搬迁应用根目录后引用不变。

## 接口与生命周期

纯 Dart 契约位于 `lib/domain/contracts/local_books.dart`。`LocalBookStore.importBook` 接收原文件字节流、格式、取消 token 和异步解析回调；回调获得短生命周期 `LocalImportSession`，通过 `openOriginal()` 读取已暂存原文件，`writeMedia()` 流式提交资源，返回不可变 `LocalBookContent`。

解析回调必须等待自己的工作、协作检查取消，不得在回调结束后继续使用 session。媒体写入串行，结束时收束全部已登记写入。外层导入、书籍读取、媒体读取都返回 Result，IO / SQL 异常不跨领域边界。取消发生在 DB 提交前时回滚；提交后返回真实成功，不声称已取消。

`read` 只返回已发布书籍，未导入为 Success(null)；缺失 / 损坏的已发布文件为失败，保留原数据以便后续修复，不静默删书。`readMedia` 校验文件包含性、长度及字节摘要后返回只读字节，不访问 Source。

`LocalDatabases` 持有唯一 ManagedLocalBooks，在数据库打开后初始化并回收残留，关闭时先等待本地导入存储再关闭 DB。暂不改造在线 NovelRepository、SourceMedia 或 ImageRepository；LOCAL-005 的路由 / 适配器按 `local` 身份分派到本契约，图片适配交付既有 MediaLease。不能把本地导入送入在线缓存装饰器或纳入 LRU。

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

移出书架只操作 bookshelf；清理历史只操作 progress；清理缓存只操作 disposable / cache.db。它们均不删除本地托管文件。本任务未提供删除导入原文件 API，未来必须作为独立明确操作设计，不能复用“移出书架”。

Android 使用已有 Application Support 私有目录，用户数据备份规则不排除正式 books。临时 import-staging 排除备份，iOS 同样应排除该可恢复暂存区；iOS 备份属性及备份一致性实测归 IOS-005 / ANDROID-002。没有新增 Native 依赖，沿用 Dart IO、crypto、Drift、path_provider，Android / iOS 最低版本不变。

## 验证记录

离线测试覆盖去重、同名不同文件、SQL 事务失败、模拟 IO 失败、等待输入时取消、提交前取消、重开回收、目录搬迁、缓存 / 书架删除隔离、资源损坏 / 路径拒绝、容量上限及 v1 / v2 迁移。模拟 IO 失败不代表实际填满手机磁盘的验证。

Android 探针 `integration_test/local_books_smoke.dart` 使用单独 local001-probe 开发目录和自制字节，不导入真实 Source。2026-09-07：新增 10 项本地存储测试，连同已有 v1 迁移及完整回归共 **320 项 PASS**；analyze 无问题。

MuMu Android API 32 首次 `LOCAL001_PREPARE_AND_REOPEN_PASS`，最终探针版本两次 force-stop / 新进程得到 `LOCAL001_COLD_REOPEN_DEDUP_MEDIA_PASS`（PID 18031、18166）。验证原文件提交、normalized chapter 身份重开、去重不重调解析器、媒体原字节跨进程读取；不是 TXT / EPUB 真实解析或图片 codec 验收。

排查中初版有 FAIL 标记：根目录系统别名导致过严路径判断，已改为对托管根下资源进行 canonical 校验；另一次未分类 FAIL 未记录具体异常，后续增加仅输出阶段 / 异常类型的诊断，最终连续两次冷启动 PASS。没有真实书源请求，没有清空现有书架 / 历史。

iOS Level A 代码兼容审查完成，runtime 仍 DEFERRED_NO_MAC，未宣称 iOS 真机通过。Android 真机磁盘满 / backup-restore / 断电持久性未实测，归 ANDROID-002；模拟器结果不替代这些验证。

验收结束已用 `lib/main.dart` 构建普通 Android Debug 包并 `install -r` 成功替换探针；未自动启动真实书源页面。没有开始 LOCAL-002。
