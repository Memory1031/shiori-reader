# CORE-003：Source / Repository / Error 契约

2026-09-07。入口 `lib/domain/contracts/contracts.dart` 导出契约、Result 和 AppFailure；模型继续来自 CORE-002。全部纯 Dart，只增加 dart:async / dart:typed_data，无新包、无 Dio / SQL / Flutter 类型。这里固定接口和所有权；生产 Source、网络调度、存储、媒体缓存仍由后续任务实现。

## Result、失败和取消

`Result<T>` 是 sealed Success<T> / Failure<T>，以 switch 解构或 map 处理；Success(null) 与 Failure 明确不同，void 操作使用 Success<void>(null)。返回 Future 的操作及各数据流的预期失败都通过 Result 传递；数据层负责拦截、映射原始传输 / 文件 / SQL 异常，不让 server message、cause、stack 跨边界。构造参数不合法或已关闭资源继续使用属于调用方编程错误，不伪装成网络失败。

AppFailure 包含 FailureKind、Operation、RetryPolicy、可选本地 diagnosticId、FailureContext 和可选 retryNotBefore。context 是供 UI 本地化的封闭枚举，不接受任意文本；diagnosticId 限定本地生成的 32 位小写十六进制关联 ID，不得取自响应或 secret。这个格式校验不是通用脱敏器，完整日志白名单仍归 NET-001。

- network / timeout / sourceUnavailable 才允许 boundedAutomatic；实际次数、deadline、退避交 NET-002。
- confirmedSessionRecovery 仅允许 session + sessionExpired；accessRestricted / cancelled / unsupported / tooLarge 必须 never。parse 可由用户明确重试，但不能自动循环。
- rateLimited 不能自动重试，合法 Retry-After 转为 UTC retryNotBefore；缺少时间时 NET-002 实施计划的保守冷却，不能由 UI 直接马上重发。
- cancelled 不作为刷新失败 badge 或弹窗；UI 丢弃已过时请求的结果。AppFailure 没有 raw message / URL / Header / exception 字段。

调用方创建 CancellationSource，只向下传递 token；cancel 幂等，token 提供同步 isCancelled 和异步 whenCancelled，无失败消息。操作开始前必须检查 token，在返回 / 发布晚结果前再次检查。读取取消返回 Failure(cancelled)；写入在提交前可取消，提交已发生则返回真实提交结果，不能声称取消而隐藏已发生的写入。

取消是协作协议，不是 Future.any 自动中断 IO 的承诺。数据实现须绑定传输 abort / stream cancel，并在操作完成时清理关联；调用方结束操作或销毁页面时 cancel 自己持有的 source。共享 in-flight 的每个调用者有独立 token，一个调用方取消不终止其他消费者；最后消费者及预取/后台所有者均退出后才取消底层请求。测试 fake 保留仓库生命周期作为后台所有者，不冒充 NET-002 的完整引用计数实现。

## NovelSource 与分页

SourceDescriptor 同步描述 sourceId、displayName、supportsDiscover、supportsSearchPaging，不触发 session。NovelSource 的 discover、search、getNovelDetail、getCatalog、getChapter 均为异步 Result，并要求 CancellationToken；没有强制 initialize，也不向 App 提供 Cookie 状态。SourceMedia 由同一具体 Source 对象实现。

SearchCursor 只包含 sourceId 和 opaqueValue，不提供 page / offset。Source 对查询做自己的正规化、编码并验证 cursor 的查询绑定与 Source；UI 原样回传，不解析、修改或记录 cursor。SearchPage 复制 items，拒绝重复 NovelKey、跨源 items / cursor；nextCursor=null 表示终止，空页必须终止。跨页重复 ID、重复 cursor / 服务器重放页由 SRC-006 检查，返回 parse + repeatedPage 等诊断后停止，不无限翻页。

DiscoverSection 只有 label 与不可变 items；不支持 Discover 返回 Failure(unsupported)，不能把未实现冒充合法空结果。Source 实现负责验证输入/返回身份与请求一致，目录聚合不向 UI 暴露请求数量；getChapter 不依赖 UI 先取目录。最小 fake 为一个合成书 / 章和两页交互示例，不是 DEV-001 的完整 fixture 场景集。

## NovelRepository 与刷新通知

查询接口接收 SourceId；detail / catalog / chapter 接收现有 Key，以 `Future<Result<LoadResult<T>>>` 返回。LoadResult 的 value、origin(memory/local/remote)、UTC fetchedAt、isStale、refreshFailure 都是一次观察的固定字段；T 须为不可变领域值，媒体 lease 的生命周期是明确例外。

| ReadMode | 契约行为 |
| --- | --- |
| cacheOnly | 只读内存或本地；miss 为 Failure(cache, cacheMiss)，不初始化 session、不发请求、不启动预取 |
| cacheFirst | 新鲜缓存直接返回；陈旧缓存先返回 stale，再按策略安排一次去重刷新；无缓存才走远端 |
| refresh | 明确请求刷新；失败且有旧缓存时返回 Success(stale LoadResult + refreshFailure)，无缓存才返回 Failure |

LoadResult 不允许 remote + isStale，不允许没有 stale 缓存却携带 refreshFailure，也不将 cancelled 包装为刷新错误。返回陈旧数据不改变它的 fetchedAt；本地写失败与是否已持久保存不能靠 origin 推断。

刷新通知固定为按 Key 的 `detailUpdates` / `catalogUpdates` / `chapterUpdates`：广播、无初始事件、订阅本身无 IO，事件类型与对应 load 返回类型相同，预期失败是数据而非 Stream.addError(rawException)。Controller 必须先订阅再 load，销毁时 cancel 订阅；仓库发出新值而非偷偷修改旧对象。生产仓库只发布经过 generation 仲裁的当前结果，不发布已清理 / 已过时响应；去重、TTL 和清理竞态留 CORE-005 / CACHE 任务。通知流取消仅移除该监听者，不取消其他读取者。

## SourceMedia 与 ImageRepository 所有权

`SourceMedia.openMedia(ref, maxBytes, cancellation)` 返回 Result<SourceMediaBody>，maxBytes 必须为正。Source 必须按实际累计字节限制完整流，不能只相信 Content-Length；元数据 MediaInfo 只包含格式、可选长度 / 尺寸，未知值为 null / unknown。原始 URL / Referer / Cookie / 重定向全部留在 Source。

SourceMediaBody.chunks 是单消费者 `Stream<Result<List<int>>>`，成功块不可修改，累计不超过 maxBytes；读取失败、超限或取消发出一次终止 Failure，然后结束，不继续发送成功字节。成功获得 body 后消费者即拥有关闭责任，即便从未订阅也必须 finally close；读取完成、提前取消及重复 close 均须安全，底层请求最终释放。返回 Failure 前尚未交付的资源由生产者关闭；close 不抛原始 cleanup 异常，数据层自行记录安全诊断。

`ImageRepository.load(ref, mode, cancellation)` 返回 `Result<LoadResult<MediaLease>>`，Phase 4 与 Phase 6 使用同一接口：

- MediaData 为 MemoryMedia（复制并只读的 Uint8List）或 LocalMedia（已验证 App 私有路径），不含 ImageProvider / File / Widget。路径包含性、非远端 URL 和文件有效性由 CACHE-003 保证，不把路径写入日志；Flutter 适配放 presentation。
- 每次成功加载交付独立 lease，消费者 finally close；close 只释放自己的内存引用 / 文件 pin，不影响其他 lease。关闭后不能继续使用其 data。文件 lease 在存活期间应被保护免遭淘汰，归 CACHE-003 实现。
- persistence 独立于 LoadOrigin：内存结果不能自称已落盘；LocalMedia 必须 persistedLocal。写盘失败仍可交付可读 MemoryMedia + memoryOnly + persistenceFailure，不能宣称离线可用。只有完成数据层验证并成功持久化才设置 persistedLocal。
- Phase 4 的 cacheOnly 可以命中 RAM；重启后的持久离线保证仍要等 Phase 6。读取新远端字节不等于平台图像 codec 验证，MEDIA-001 / TEST-001 / ANDROID-002 继续负责真实显示与资源上限。

媒体 lease 不经 NovelRepository 的广播通知传递，每个 load 单独交付所有权，避免多个订阅者误用同一可关闭资源。未来媒体刷新通过显式重新 load 获得新 lease，交替释放由 UI/image adapter 负责。

## LibraryRepository 与 SettingsStore

LibraryRepository 是书架和阅读历史唯一写入口，所有操作本地完成，不依赖 Source。watchBookshelf / watchRecentReading 发初始及后续不可变完整快照；排序按计划使用最近阅读 / addedAt 降序和稳定键 tie-break。订阅者持有并取消自己的数据库监听。

putBookshelf 按 NovelKey 幂等，保留既有 addedAt；removeFromBookshelf 返回被移除条目供撤销，不删除 progress / 正文 / 图片。getProgress 无记录为 Success(null)。clearHistory 单独删除历史，不影响书架 / 缓存，且使在途旧进度代次失效，避免晚写复活历史。

为落实计划中的晚写保护，新增明确的 `beginProgressSession(NovelKey) → Result<int>` 与 `ProgressWriteStamp(generation,sequence)`：仓库生成每本书跨进程单调代次，调用方在同代次递增 sequence；saveProgress 原子检查 stamp 并写入。返回 true 表示已提交，false 表示旧代次 / 重复 / 倒序写被忽略，不能当作已保存。代次与正文 revision、时间戳无关，不塞进 ReadingProgress 实体；DB-002 负责持久代次、串行事务和真正重启验证，本轮 fake 只验证协议。

SettingsStore.load/save 使用 ReaderSettings；取消前提交规则同上。DB-002 遇坏存储 codec / 未知版本可按既定策略回退默认设置并记录安全诊断，不重置无关书架 / 进度，实际写失败返回 Failure(database/cache)。不承诺设置与进度跨存储事务。

## 最小 fake 与验收

`test/support/contract_fakes.dart` 实现最小 Source / SourceMedia、章节缓存刷新、媒体两种 lease 和 SettingsStore；`contract_library.dart` 实现仅供测试的内存书架 / stamp 协议。这些未注册到 App，无网络、文件读写、SQL、TTL/LRU 或生产 Source，只为具体接口提供可编译、可执行的使用例。

运行 `dart --suppress-analytics test test/domain`；**33 项测试通过（CORE-002 的 18 项 + 本轮 15 项）**，全项目静态分析通过。覆盖分页绑定/终止、取消前无工作、共享调用者取消隔离、cacheOnly 零 Source 调用、stale 刷新及失败事件、媒体超限/取消/重复释放、内存/本地持久性、书架/历史隔离、stamp 晚写、Settings 保存和 Domain import 边界。生产网络异常映射、真正文件 pin、数据库事务及 Source 跨会话恢复仍由后续任务验收。

iOS Level A：PASS，纯 Dart 标准库扩展，无 Native 插件、平台分支或最低 OS 变化。未运行 Flutter / Android / iOS runtime；本任务使用纯 Dart fake 验证，不把它当真实缓存、平台解码或 Source 准入的新证据。

交接建议：下一项 CORE-004 建立应用组装和导航壳；DEV-001、NET-001、DB-001 也已满足各自前置，后续按计划领取，不把本次 fake 当正式 DEV-001 完成。

DB-001 / DB-002 后续实现已完成：生产本地 LibraryRepository、进度持久代次、记录 stores 和 SharedPreferencesAsync 设置适配已落地，契约签名不变，见 [存储验收](database.md)。
