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

LibraryRepository 是书架和阅读进度唯一写入口，所有操作本地完成，不依赖 Source。watchBookshelf / watchRecentReading 发初始及后续不可变完整快照；排序使用最近阅读 / addedAt 降序和稳定键 tie-break。订阅者持有并取消自己的数据库监听。

putBookshelf 按 NovelKey 幂等，保留既有 addedAt；removeFromBookshelf 返回被移除条目，底层只删除书架记录。产品 LibraryController 对在线书经确认后先调用 CacheManagement 按书清理，再调用 removeOnlineBook，在用户库同一事务删除书架、阅读进度、书签、持久目录和预取选择，推进并保留 progress_sessions 的写入及移除代次。缓存清理失败保留条目供重试；两个存储不共用事务，缓存清理成功但用户库提交失败时，书架及阅读数据一起保留，缓存可能已清。成功移除通知使旧 Reader 失效；旧目录和预取观测核对移除代次，不能写回，新阅读会话可以重新入架。本地书移除改走 LocalBookManagement.deleteBook，确认后删除托管文件、索引、书架、进度和书签并失效旧写；不使用仅删书架的接口。文件清理延后时明确提示 cleanupPending。getProgress 无记录为 Success(null)。clearHistory 单独删除历史，不影响书架 / 书签 / 缓存，且使在途旧进度代次失效，避免晚写复活历史。

进度晚写保护使用 `beginProgressSession(NovelKey) → Result<int>` 与 `ProgressWriteStamp(generation,sequence)`：仓库生成每本书跨进程单调代次，调用方在同代次递增 sequence；saveProgress 原子检查 stamp 并写入。正式激活的在线 Reader 首次成功保存有效进度时，使用 ReadingProgress.snapshot 在同一事务幂等加入书架，保留既有 addedAt，并可提交该会话的完整目录依据；预览、预加载和取消候选不保存进度，也不入架。返回 true 表示已提交，false 表示旧代次 / 重复 / 倒序写被忽略，不能当作已保存。普通目录浏览不建立持久归属；只有已有书架或进度，或首次进度事务，才持久化目录依据，仍保留版本仲裁、进度重算和离线回退。目录依据暂缺或冲突返回可手动重试的 `Failure(cache, catalogBasisUnavailable)`，保留待保存位置；它不使当前 generation 失效。代次与正文 revision、时间戳无关，不塞进 ReadingProgress 实体；存储层负责持久代次与串行事务，协议测试和设备重启证据分开记录。

SettingsStore.load/save 使用 ReaderSettings；取消前提交规则同上。存储层遇坏存储 codec / 未知版本可按既定策略回退默认设置并记录安全诊断，不重置无关书架 / 进度，实际写失败返回 Failure(database/cache)。不承诺设置与进度跨存储事务。


## 用户书签

`UserBookmarkRepository` 独立管理用户库中的多位置书签，列表订阅和读取不请求正文或网络。语义锚点保留章节身份、无像素提示的位置及有界文本上下文；同版本严格校验，跨版本只接受唯一可信对应，不能将进度 fallback 作为书签成功结果。清历史与清缓存保留书签，删除书籍原子删除书签并推进保留的变更戳。

书签写入复验集合版本，单条删除复验行版本；过期请求返回未提交，不创建已删除记录。手动与自动重解析在事务外批量计算书签位置，在原内容发布事务内复验并更新仍存在的行；不可定位保留最后可信锚点及状态，不作为自动发布的进度准入条件，数据库错误则整体回滚。

## 阅读统计

`ReadingStatisticsRepository` 只访问本机用户库；缺少偏好默认开启，读取失败返回 Failure，不能视为首次使用。`begin` 捕获书籍身份、全局 epoch 与移除代次；检查点以会话 ID 和严格递增序号串行提交，已发起的日增量不可变，相同序号只接受相同内容。每日总量、分书量、序号及首次记录日期同事务提交；无增量不写入。清空、关闭或移除书籍使旧写失效，重新导入不复用旧移除代次。

统计读取在同一事务返回设置、区间日桶、全期与今日总量、当前分书量；匿名时长由区间总量减去全部仍有关联的分书量计算，不从 UI 已显示的条目推算。缺少元数据的书籍仍保留关联，元数据损坏返回失败。页面绑定范围、请求代次及 epoch，迟到结果不得覆盖切换范围或清空后的状态。运行期只有应用根持有写入者，沿用托管书库的跨进程所有权；关闭时有界结算并先于数据库释放。计时条件见[阅读器](reader.md#阅读时长)。

## 应用更新

`AppUpdateRepository` 由应用根拥有，页面借用同一个 `UpdateController`。更新检查与小说 Source 的网络服务独立；领域候选只暴露发布身份、大小、纯文本说明和发布页，不暴露缓存文件路径。候选须通过内置公钥验签及平台资产校验；下载完成核对大小与摘要，重启恢复时重新验签并核对文件。

`UpdateChannel` 表示 Stable / Beta 版本筛选；`InstalledUpdateApp.installation` 描述安装形态与分发渠道，无法确认时保留 unknown。macOS 安装形态为 `.app`，DMG 是更新包格式。direct 包含通过 AltStore 或其他用户自选签名工具安装的 iOS IPA，签名工具不单列渠道。`UpdateCapabilities` 以更新方式和可选外部入口描述检测、下载、安装能力，可表达 iOS 仅检测新版、由用户通过原签名方式更新。更新是否启用仍使用 `UpdateAvailability`，安装位置及权限由现有安装器检查。

检查与下载共用互斥操作状态，取消等待 I/O 结束后完成；根关闭时先取消并等待操作，再关闭更新网络。检查预算内找到有效升级时，返回已验证的最高构建号候选；未穷尽历史且没有有效候选时报告检查不完整。渠道及自动检查偏好独立持久化；自动检查按当前渠道上次尝试间隔 24 小时，切换渠道使检查结果和尝试时间失效，服务端限流等待仍然保留。正式包核对原生版本与包内身份后启用更新，开发构建不访问正式更新源。

Android 安装交接前重新核对签名清单与包摘要，原生层再核对包名、版本、递增构建号及 APK 证书与已安装应用的一致性。安装权限由用户授权，返回后需再次点击安装；已提交的 `PackageInstaller` 会话由系统确认或取消，页面的下载取消操作不撤销安装。原生安装记录跨进程保留，重启以实际安装版本确认结果并清理过期下载；中断留下的本应用未提交会话会被清理以允许重试。取消或可重试安装失败保留完整下载；本地包失效恢复下载入口，清单或安装身份校验失败则要求重新检查。更新页通过首页菜单或桌面工作区进入，阅读中的通知要求先走正常保存退出流程。

Windows 安装版通过本地标记和当前用户卸载注册共同识别，使用已验签的 Setup EXE 升级，由安装器维护卸载清单与快捷方式；便携版只接受 ZIP，不转换发行模式。两种模式可在不同目录并存。便携更新程序使用结构化任务交接，在安装目录之外运行；替换前核对进程、安装身份、签名清单及完整解压结果。拒绝绝对路径、目录穿越、符号链接 / junction、重复或大小写冲突路径以及超限解压内容。事务只管理当前与目标程序清单覆盖的文件，保留其他文件；持久记录支持未完成替换恢复。主程序先保存阅读位置和设置、释放存储与媒体资源，更新程序等待对应进程退出后替换程序。自动回滚仅适用于新应用尚未开始数据迁移的阶段；迁移后故障保留备份并按数据恢复流程处理，不能直接用旧程序读取新 schema。更新写入范围限于已校验程序目录和专用暂存 / 备份目录，不接管用户数据库、书籍或缓存。

macOS 与其他平台共用统一签名清单，安装和自动更新均使用 DMG，复用检查、下载和保存退出流程。安装时由当前包内置的辅助程序再次验签、核对摘要和发布身份；通过系统 `hdiutil` 只读挂载 DMG，检查 Bundle 代码封装、路径、数量与大小后复制完整 `.app`；允许 Framework 的包内链接，禁止路径逃逸和硬链接。正常失败和中断恢复仅卸载本更新工作区的固定挂载点。辅助程序在应用目录外等待主进程退出，重新挂载并复制已验证包、卸载映像后，在同卷原子交换完整应用；拒绝只读、DMG、App Translocation 位置与其他运行实例。应用在 Flutter 启动前取得安装父目录的共享租约并持有至退出；替换与回滚持有同目录独占锁并复查运行实例，提交期间的新启动不进入 Flutter。事务恢复不会触碰用户数据；系统启动命令失败时仅在重新取得独占锁且确认无运行实例后恢复旧包，否则保留事务与备份。启动后运行故障不承诺自动回滚。ad-hoc 签名只保证本地代码封装，更新信任来自内置公钥，不来自 Apple 身份认证。

## 本地与缓存能力

ImportSource 只接收候选副本：不透明 ID、显示名、字节大小、封闭错误码及进度事件；pending 返回有序待确认回执列表，是重启恢复依据。acknowledge(id) 是按 ID 幂等的确认消费回执，只消费指定回执，不影响其他项；cancelCopy 等待 Native 接收结束（复制、流关闭与暂存清理完成）后才返回，不在写入尚未停止时声称完成。回执对应的路径与平台文件结构保留在 native / data 层私有，不进入 ImportCandidate 或领域模型。Native 批次发布是原子的：任一复制失败或取消不暴露部分回执；该原子性不改变此后 Dart 逐书入库可部分成功的语义。平台入口、目录结构与 durable inbox 协议见[本地导入](local-import.md#平台接收)。

PlatformImportSource 完整验证两平台 List<Map> 或 legacy Map/null 后才替换 ID → path 缓存，malformed 响应报告 storage 并保留旧绑定；路径不进入 ImportCandidate。ImportProblem.batchLimit 只表示原生选择 / 接收超过批量上限（项数或整批实际字节数，限额见[本地导入](local-import.md#公共收件箱协议)），单文件超限仍使用 tooLarge；移动端全局收件额度不足为 inboxFull，发布后同步未确认使用 publicationUncertain。它们不扩大控制器 fatal policy，也不增加进度事件字段。

导入控制器按用户确认时的回执快照严格串行处理，晚到文件留待下一次确认；忙碌期间记录刷新需求，空闲后补刷，启动 / 恢复不会自动提交。接收进度不覆盖当前文件的解析进度：单文件失败只标记该项并继续；storage / parserUnavailable 视为全局失败停止后续项；成功项提交后立即按 ID ack 并从 inbox 删除，失败与未处理回执保留待重试（dedup 命中仍视为成功）。「停止导入」停止当前处理，不回滚已成功项、不 ack 未完成回执；非运行态的「放弃文件」经用户确认后只放弃确认时的回执快照，逐条 ack 并 discard 剩余 inbox 副本，不删除用户原文件或已入库书籍。放弃清理期间禁止重新选择或提交；部分 ack 失败只移除已 ack 项，保留剩余项和 storage 错误供重试；旧 pending 查询不得重新加入已放弃回执。

LocalBookDecoder 接收导入 session、格式、文件名、token 和编码确认回调，严格解码后才提供有界预览。LocalBookStore 唯一负责发布，importBook 返回 LocalBookImportResult，以 book 提供持久记录、disposition 区分本次新建与已有内容；去重命中仍是成功，不重新解析。生产使用 addToShelf 同事务加入书架；LocalBookManagement 删除后失效旧会话，cleanupPending 表示 SQL 已提交但文件待回收。

LocalNavigationRepository 返回嵌套目录与 ChapterKey / 可选 blockKey。阅读器生成的名称可附 `generatedLabel` 类型，`title` 保留兼容兜底；原书标题及旧记录缺省不带该标记，未知标记回退到 `title`。LocalPagePresentationRepository 为特殊短页提供可选惰性静态 HTML，普通正文返回空；领域正文仍保存原生语义块，不持有 WebView 对象。发布与兼容见[本地导入](local-import.md)。

可选的 LocalLogicalChapterRepository 从同一已导入快照返回 Reader 专用的只读目录区段索引，包含主阅读顺序、完整块权重、内容版本与块身份；TXT 返回空。索引不改变 ChapterContent、ReaderPosition 或存储格式；逻辑显示与导航合同见[阅读器](reader.md#全书进度与阅读完成)。

可选的 `LocalBookSearchRepository.openLocalSearch` 只接受本地书籍身份，从已校验、已发布的 EPUB/TXT 语义快照建立调用方拥有的单书会话，不读取原件或访问在线服务。`LocalBookUse` 存活期间明确 pin 已读取的快照，搜索可共享这一对象；最后使用许可及搜索会话释放后移除 pin，普通读取缓存仍仅保留最近一本。扫描不占用存储串行队列，也不写阅读进度。

`LocalSearchSession.search` 替换并取消旧查询，`nextPage` 消费本会话当前查询的一次性游标；每页最多 64 项，工作文本批次最多 65,536 UTF-16 单元。关键词 trim 后接受 1–256 UTF-16 单元的合法 Unicode 普通子串，ASCII 大小写不敏感，不跨自然段，不搜索 Ruby 注音及图片占位符。游标表示仍有未扫描文本，允许末次返回空页；`totalMatches` 仅在扫描完成后提供，不设置全书命中总量上限。

正文结果包含章节／块身份、原文码点范围及 `before/match/after` 摘要；脚注独立携带来源引用和注释内部范围，不将注释位置冒充正文 offset。结果绑定会话存活期间的书籍发布身份。使用结果前须调用 `validate` 复验发布信息及 manifest 元数据；删除、手动维护或自动发布均退役旧快照，包括语义 revision 不变的重新发布，失效返回 `cache/invalidContent`。字体重排不影响此身份。关闭会话或取消查询须等待 worker 退出和回复端口释放；取消结束等待中的 Future，关闭后不再保有搜索正文与续扫状态。

CacheManagement 提供 inspect、按书 / 全部 clear 和可释放 pin；ReadingPrefetch 提供目标选择、开关、暂停 / 恢复与生命周期通知。预取不创建阅读进度。ImageRepository 持久化失败可返回 memoryOnly + persistenceFailure，清理不破坏活动 lease，但阻止旧响应回填。

应用根先关闭预取，再关闭媒体 / 小说仓库与调度器，最后关闭数据库。ReaderPreferences 读取或更新时将旧 scroll 归一化为 paged，保留排版；读取不为了模式迁移主动覆盖存储。详见[阅读器](reader.md)、[缓存](architecture.md)与[数据库](architecture.md)。

## 显式重解析

LocalBookReparse 接收书籍 Key、编码选择回调/可选 override 与 cancellation；返回 LocalReparseResult（approximate、cleanupPending）。失败前旧版本保持可读，提交后成功优先于取消；新旧正文及进度经同一 SQL 事务发布。LocalBookInvalidation 的 invalidations 在维护开始退役旧 Reader，changes 在提交后触发本地 detail/catalog/chapter 更新；两者广播、无初始事件，消费者取消订阅。

手动维护期间不发新进度会话，saveProgress 返回 false；clearHistory 仍生效并阻止使用旧快照发布。已重解析书的保存还校验 catalog/content revision，旧正文即使申请到新 generation 也不能覆盖迁移位置。位置迁移不保留像素提示，近似结果供 UI 明示。内容可选 txtEncoding 只属于本地解析元数据，不进入正文身份摘要。详见[结果与边界](local-import.md)。

自动升级由 ManagedLocalBooks 拥有：Prepare 在串行发布队列之外生成独立暂存产物，不设置 maintenance、不改活动指针或进度，不发 invalidation。LocalBookUsage 在首次读取前提供书籍级使用许可；Reader 与辅助页持有许可，章节 Controller 的关闭屏障等待在途读取和最后 ProgressTracker 写入后才释放。失败的最后写入暂缓该书自动发布，后续更新的阅读会话成功保存并关闭或下次进程启动可重新评估；未采样会话不能证明失败进度已保存。

自动 Commit 在迁移计算之外取得独占发布许可，无活动 Reader 和未保存进度延期才可进入。新 Reader 等待此短暂发布完成；事务内重新校验活动 Bundle/hash/parserVersion、进度 generation/sequence 和实际持久化进度，原子更新解析结果及关联记录。清理旧 Revision 不持发布许可；媒体文件读取沿用串行队列，完成后才允许版本切换。手动操作取消并等待自动 Prepare，已进入 Commit 则等待提交或回滚后重新读取状态。

LocalBookInfo.autoReparseIssue 仅提供本地管理页的被动异常原因；正常排队与成功升级没有标记。尝试记录不含正文、私有路径或堆栈，手动成功及删除清除对应记录。


## 书内链接与连续阅读合同

LocalContentLink 是独立于 ContentBlock 的不可变侧表项：来源 ChapterKey/blockKey、标签、可选目标 ChapterKey/blockKey，以及封闭 unavailable 原因；没有原始 URL/路径，不改变正文摘要。目标可附非负 targetOffset，以目标块内 Unicode code points 计数，必须同时有目标块；旧记录缺省时定位块首。同章、跨章和辅助页导航均保留该偏移。受限 SVG 短页的矩形热点可附经校验的归一化 viewBox 区域，由 Reader 命中并复用同一导航；WebView 不执行原链接。LocalBookContent 可保存 auxiliaryChapters、links 和可空 readingOrder；旧 manifest 缺字段时 links/auxiliary 为空，readingOrder 默认为原目录顺序。


可点击范围使用 sourceOffset / sourceLength，均按来源块内 Unicode code points 计数；跨块链接逐块保存范围，不改正文。sourceOffset 非空且 sourceLength 为空的项兼容旧脚注合同，label 对应数字上标，并有可空 footnoteText（纯文本）。可用脚注的 target 指向来源章，面板直接消费 footnoteText，不进行章节导航；不可用项保留入口位置及原因。旧侧表缺范围字段时仍可通过菜单访问普通链接。解析器替换脚注入口并移除注释正文会正常产生新的正文 revision；交互本身不修改内容身份。
LocalContentLinkRepository 提供按来源章节的链接和主阅读顺序，所有请求仍携带取消 token。包内 href/fragment 在 data 层解析；远程、越界、缺文档或缺锚点只报告不可用，不能退到网络或错误地跳章首。同资源链接保留当前 occurrence，跨资源链接选择目标第一次出现。非 spine 的 manifest XHTML 可作为有界辅助文档加载；不进入主目录/连续阅读序列。

正文内链、结构化目录和“本章注释”复用目标导航：同章在原视口恢复块位置；readingOrder 内其他章节使用现有切章及进度会话；其余文档打开临时辅助阅读页（不注入 LibraryRepository），最多嵌套 8 层。辅助页的原 Reader 保持挂载，返回使用原页/原 occurrence。维护 invalidation 同时退役主页和辅助页。linear=no 仍可明确选择，但不参与连续翻章。
