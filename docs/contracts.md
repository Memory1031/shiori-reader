# 跨层契约与资源所有权

入口 `lib/domain/contracts/contracts.dart`。接口保持纯 Dart，不暴露 Dio、SQL、Flutter、平台 URI 或原始异常。

## Result、失败和取消

`Result<T>` 是 sealed Success<T> / Failure<T>，以 switch 解构或 map 处理；Success(null) 与 Failure 明确不同，void 操作使用 Success<void>(null)。返回 Future 的操作及各数据流的预期失败都通过 Result 传递；数据层负责拦截、映射原始传输 / 文件 / SQL 异常，不让 server message、cause、stack 跨边界。构造参数不合法或已关闭资源继续使用属于调用方编程错误，不伪装成网络失败。

AppFailure 包含 FailureKind、Operation、RetryPolicy、可选本地 diagnosticId、FailureContext 和可选 retryNotBefore。context 是供 UI 本地化的封闭枚举，不接受任意文本；diagnosticId 限定本地生成的 32 位小写十六进制关联 ID，不得取自响应或 secret。这个格式校验不是通用脱敏器，日志白名单见[网络](architecture.md)。

- network / timeout / sourceUnavailable 才允许 boundedAutomatic；实际次数、deadline、退避见[网络](architecture.md)。
- confirmedSessionRecovery 仅允许 session + sessionExpired；accessRestricted / cancelled / unsupported / tooLarge 必须 never。parse 可由用户明确重试，但不能自动循环。
- rateLimited 不能自动重试，合法 Retry-After 转为 UTC retryNotBefore；缺少时间时网络层使用保守冷却，不能由 UI 直接马上重发。
- cancelled 不作为刷新失败 badge 或弹窗；UI 丢弃已过时请求的结果。AppFailure 没有 raw message / URL / Header / exception 字段。

调用方创建 CancellationSource，只向下传递 token；cancel 幂等，token 提供同步 isCancelled 和异步 whenCancelled，无失败消息。操作开始前必须检查 token，在返回 / 发布晚结果前再次检查。读取取消返回 Failure(cancelled)；写入在提交前可取消，提交已发生则返回真实提交结果，不能声称取消而隐藏已发生的写入。

取消是协作协议，不是 Future.any 自动中断 IO 的承诺。数据实现须绑定传输 abort / stream cancel，并在操作完成时清理关联；调用方结束操作或销毁页面时 cancel 自己持有的 source。共享 in-flight 的每个调用者有独立 token，一个调用方取消不终止其他消费者；最后消费者及预取/后台所有者均退出后才取消底层请求。

## NovelSource 与分页

SourceDescriptor 同步描述 sourceId、displayName、supportsDiscover、supportsSearchPaging，不触发 session。NovelSource 的 discover、search、getNovelDetail、getCatalog、getChapter 均为异步 Result，并要求 CancellationToken；没有强制 initialize，也不向 App 提供 Cookie 状态。SourceMedia 由同一具体 Source 对象实现。

SearchCursor 只包含 sourceId 和 opaqueValue，不提供 page / offset。Source 对查询做自己的正规化、编码并验证 cursor 的查询绑定与 Source；UI 原样回传，不解析、修改或记录 cursor。SearchPage 复制 items，拒绝重复 NovelKey、跨源 items / cursor；nextCursor=null 表示终止，空页必须终止。跨页重复 ID、重复 cursor / 服务器重放页由 Source 检查，返回 parse + repeatedPage 等诊断后停止，不无限翻页。

DiscoverSection 只有 label 与不可变 items；不支持 Discover 返回 Failure(unsupported)，不能把未实现冒充合法空结果。Source 实现负责验证输入/返回身份与请求一致，目录聚合不向 UI 暴露请求数量；getChapter 不依赖 UI 先取目录。发现接口保留为底层能力，当前产品无发现入口。

## NovelRepository 与刷新通知

查询接口接收 SourceId；detail / catalog / chapter 接收现有 Key，以 `Future<Result<LoadResult<T>>>` 返回。LoadResult 的 value、origin(memory/local/remote)、UTC fetchedAt、isStale、refreshFailure 都是一次观察的固定字段；T 须为不可变领域值，媒体 lease 的生命周期是明确例外。

| ReadMode | 契约行为 |
| --- | --- |
| cacheOnly | 只读内存或本地；miss 为 Failure(cache, cacheMiss)，不初始化 session、不发请求、不启动预取 |
| cacheFirst | 新鲜缓存直接返回；陈旧缓存先返回 stale，再按策略安排一次去重刷新；无缓存才走远端 |
| refresh | 明确请求刷新；失败且有旧缓存时返回 Success(stale LoadResult + refreshFailure)，无缓存才返回 Failure |

LoadResult 不允许 remote + isStale，不允许没有 stale 缓存却携带 refreshFailure，也不将 cancelled 包装为刷新错误。返回陈旧数据不改变它的 fetchedAt；本地写失败与是否已持久保存不能靠 origin 推断。

刷新通知固定为按 Key 的 `detailUpdates` / `catalogUpdates` / `chapterUpdates`：广播、无初始事件、订阅本身无 IO，事件类型与对应 load 返回类型相同，预期失败是数据而非 Stream.addError(rawException)。Controller 必须先订阅再 load，销毁时 cancel 订阅；仓库发出新值而非偷偷修改旧对象。生产仓库只发布经过 generation 仲裁的当前结果，不发布已清理 / 已过时响应；去重、TTL 和清理竞态见[缓存](architecture.md)。通知流取消仅移除该监听者，不取消其他读取者。

## SourceMedia 与 ImageRepository 所有权

`SourceMedia.openMedia(ref, maxBytes, cancellation)` 返回 Result<SourceMediaBody>，maxBytes 必须为正。Source 必须按实际累计字节限制完整流，不能只相信 Content-Length；元数据 MediaInfo 只包含格式、可选长度 / 尺寸，未知值为 null / unknown。原始 URL / Referer / Cookie / 重定向全部留在 Source。

SourceMediaBody.chunks 是单消费者 `Stream<Result<List<int>>>`，成功块不可修改，累计不超过 maxBytes；读取失败、超限或取消发出一次终止 Failure，然后结束，不继续发送成功字节。成功获得 body 后消费者即拥有关闭责任，即便从未订阅也必须 finally close；读取完成、提前取消及重复 close 均须安全，底层请求最终释放。返回 Failure 前尚未交付的资源由生产者关闭；close 不抛原始 cleanup 异常，数据层自行记录安全诊断。

`ImageRepository.load(ref, mode, cancellation)` 返回 `Result<LoadResult<MediaLease>>`：

- MediaData 为 MemoryMedia（复制并只读的 Uint8List）或 LocalMedia（已验证 App 私有路径），不含 ImageProvider / File / Widget。路径包含性、非远端 URL 和文件有效性由持久媒体仓库保证，不把路径写入日志；Flutter 适配放 presentation。
- 每次成功加载交付独立 lease，消费者 finally close；close 只释放自己的内存引用 / 文件 pin，不影响其他 lease。关闭后不能继续使用其 data。文件 lease 在存活期间应被保护免遭淘汰，由持久媒体仓库实现。
- persistence 独立于 LoadOrigin：内存结果不能自称已落盘；LocalMedia 必须 persistedLocal。写盘失败仍可交付可读 MemoryMedia + memoryOnly + persistenceFailure，不能宣称离线可用。只有完成数据层验证并成功持久化才设置 persistedLocal。
- cacheOnly 读取已有缓存；持久缓存支持重启后离线读取。远端字节读取成功不等于平台图像解码或实际显示已通过验证。

媒体 lease 不经 NovelRepository 的广播通知传递，每个 load 单独交付所有权，避免多个订阅者误用同一可关闭资源。未来媒体刷新通过显式重新 load 获得新 lease，交替释放由 UI/image adapter 负责。

## LibraryRepository 与 SettingsStore

LibraryRepository 是书架和阅读历史唯一写入口，所有操作本地完成，不依赖 Source。watchBookshelf / watchRecentReading 发初始及后续不可变完整快照；排序使用最近阅读 / addedAt 降序和稳定键 tie-break。订阅者持有并取消自己的数据库监听。

putBookshelf 按 NovelKey 幂等，保留既有 addedAt；removeFromBookshelf 返回被移除条目，底层只删除书架记录。产品 LibraryController 对在线书先调用 CacheManagement 按书清理，再移出书架，不提供撤销；清理失败保留条目供重试。两个存储不共用事务，若清理成功但移出失败，条目仍在、缓存可能已清。在线阅读进度保留。本地书移除改走 LocalBookManagement.deleteBook，确认后删除托管文件、索引、书架和进度并失效旧写；不使用仅删书架的接口。文件清理延后时明确提示 cleanupPending。getProgress 无记录为 Success(null)。clearHistory 单独删除历史，不影响书架 / 缓存，且使在途旧进度代次失效，避免晚写复活历史。

进度晚写保护使用 `beginProgressSession(NovelKey) → Result<int>` 与 `ProgressWriteStamp(generation,sequence)`：仓库生成每本书跨进程单调代次，调用方在同代次递增 sequence；saveProgress 原子检查 stamp 并写入。返回 true 表示已提交，false 表示旧代次 / 重复 / 倒序写被忽略，不能当作已保存。代次与正文 revision、时间戳无关，不塞进 ReadingProgress 实体；存储层负责持久代次与串行事务，协议测试和设备重启证据分开记录。

SettingsStore.load/save 使用 ReaderSettings；取消前提交规则同上。存储层遇坏存储 codec / 未知版本可按既定策略回退默认设置并记录安全诊断，不重置无关书架 / 进度，实际写失败返回 Failure(database/cache)。不承诺设置与进度跨存储事务。


## 本地与缓存能力

ImportSource 只接收候选副本：不透明 ID、显示名、字节大小、封闭错误码及进度事件；pending 返回有序待确认回执列表，是重启恢复依据。Android 支持 picker 多选及 SEND_MULTIPLE，iOS 支持 UIDocumentPicker 多选及 ShareExtension 多附件，Runner 与扩展共用 App Group 批量 inbox。两平台每批最多 64 项、单文件 128 MiB、累计 512 MiB，只保留一个 pending batch。两平台均在 lock 内整批 working → pending 原子发布，任一复制失败或取消不暴露部分回执；逐 ID ack 先原子 detach 到墓碑再清理，重启保持剩余 order，兼容旧单回执 pending。完整 Native 协议见[平台接收](local-import.md#平台接收)。

PlatformImportSource 完整验证两平台 List<Map> 或 legacy Map/null 后才替换 ID → path 缓存，malformed 响应报告 storage 并保留旧绑定；路径不进入 ImportCandidate。ImportProblem.batchLimit 只表示选择超过 64 项或实际整批超过 512 MiB，单文件超限仍使用 tooLarge；不扩大控制器 fatal policy，也不增加进度事件字段。

导入控制器按回执顺序严格串行处理：单文件失败只标记该项并继续；storage / parserUnavailable 视为全局失败停止后续项；成功项提交后立即按 ID ack 并从 inbox 删除，失败与未处理回执保留待重试（dedup 命中仍视为成功）；「停止导入」停止当前处理，不回滚已成功、不 ack 未完成项；非运行态的「取消」显式放弃当前批次，逐 ID ack inbox 副本，不删除原文件或已入库书籍。取消清理期间禁止重新选择或提交；部分 ack 失败只移除已确认项，保留剩余项和 storage 错误供重试；旧 pending 查询不得重新加入已取消回执。ack 按 ID 幂等且只删除指定回执，cancelCopy 等待复制结束，平台路径和权限留在 native / data。Native 整批接收原子性不改变此后逐书入库可部分成功的语义。

LocalBookDecoder 接收导入 session、格式、文件名、token 和编码确认回调，严格解码后才提供有界预览。LocalBookStore 唯一负责发布，生产使用 addToShelf 同事务加入书架；LocalBookManagement 删除后失效旧会话，cleanupPending 表示 SQL 已提交但文件待回收。

LocalNavigationRepository 返回嵌套目录与 ChapterKey / 可选 blockKey。LocalPagePresentationRepository 为特殊短页提供可选惰性静态 HTML，普通正文返回空；领域正文仍保存原生语义块，不持有 WebView 对象。发布与兼容见[本地导入](local-import.md)。

CacheManagement 提供 inspect、按书 / 全部 clear 和可释放 pin；ReadingPrefetch 提供目标选择、开关、暂停 / 恢复与生命周期通知。预取不创建阅读进度。ImageRepository 持久化失败可返回 memoryOnly + persistenceFailure，清理不破坏活动 lease，但阻止旧响应回填。

应用根先关闭预取，再关闭媒体 / 小说仓库与调度器，最后关闭数据库。ReaderPreferences 读取或更新时将旧 scroll 归一化为 paged，保留排版；读取不为了模式迁移主动覆盖存储。详见[阅读器](reader.md)、[缓存](architecture.md)与[数据库](architecture.md)。

## 显式重解析

LocalBookReparse 接收书籍 Key、编码选择回调/可选 override 与 cancellation；返回 LocalReparseResult（approximate、cleanupPending）。失败前旧版本保持可读，提交后成功优先于取消；新旧正文及进度经同一 SQL 事务发布。LocalBookInvalidation 的 invalidations 在维护开始退役旧 Reader，changes 在提交后触发本地 detail/catalog/chapter 更新；两者广播、无初始事件，消费者取消订阅。

维护期间不发新进度会话，saveProgress 返回 false；clearHistory 仍生效并阻止使用旧快照发布。已重解析书的保存还校验 catalog/content revision，旧正文即使申请到新 generation 也不能覆盖迁移位置。位置迁移不保留像素提示，近似结果供 UI 明示。内容可选 txtEncoding 只属于本地解析元数据，不进入正文身份摘要。详见[结果与边界](local-import.md)。

## 书内链接与连续阅读合同

LocalContentLink 是独立于 ContentBlock 的不可变侧表项：来源 ChapterKey/blockKey、标签、可选目标 ChapterKey/blockKey，以及封闭 unavailable 原因；没有原始 URL/路径，不改变正文摘要。LocalBookContent 可保存 auxiliaryChapters、links 和可空 readingOrder；旧 manifest 缺字段时 links/auxiliary 为空，readingOrder 默认为原目录顺序。

LocalContentLinkRepository 提供按来源章节的链接和主阅读顺序，所有请求仍携带取消 token。包内 href/fragment 在 data 层解析；远程、越界、缺文档或缺锚点只报告不可用，不能退到网络或错误地跳章首。同资源链接保留当前 occurrence，跨资源链接选择目标第一次出现。非 spine 的 manifest XHTML 可作为有界辅助文档加载；不进入主目录/连续阅读序列。

Reader 的“本章链接”打开临时辅助阅读页（不注入 LibraryRepository），最多嵌套 8 层。原 Reader 保持挂载，返回使用原页/原 occurrence，不用保存/再读近似恢复来模拟返回。维护 invalidation 同时退役主页和辅助页。linear=no 仍在目录中、明确选择可阅读，但连续翻章只使用 readingOrder。
