# 架构与数据规则

领域身份、应用装配和存储资源规则的唯一维护入口；公共接口见[接口合同](contracts.md)。

## 领域模型与内容身份

领域层保持纯 Dart、不可变，不依赖 UI、网络、SQL 或平台。入口 `lib/domain/models/models.dart`，摘要实现 `lib/domain/content_identity.dart`。

### 模型边界

- 所有模型具有值相等语义；构造时复制集合，对外不可修改。运行时 hashCode 只服务内存集合，不可持久化。
- SourceId / NovelKey / ChapterKey / MediaRef 保留不透明字符串，不 trim、不拼 URL；拒绝空白 ID 和非法 Unicode。SourceId 在注册层使用 `lightnovel`，Domain 不内置具体源常量。MediaRef 无 secret 的前提由 Source 保证，Domain 不猜测 URL 的签名字段。
- Summary / Detail 以字符串列表表示作者和标签；缺少信息保留 empty / null / unknown，不猜作者、完结状态或时间。Source 负责 HTML entity / 标记清理，Domain 只接收普通文本；不因文本含 `<` 等合法字符便把它当 HTML 删除。
- Catalog 只持有不可变卷章树，flatChapters 是惰性视图；不按 ID 或标题排序。全目录 ordinal 必须从 0 连续递增；重复 groupId / ChapterKey、跨小说归属或卷归属错误直接拒绝。Source 先处理重复链接和缺名诊断，不能依赖 Domain 静默去重。无卷可用明确 isSynthetic 的分组，缺卷名为 null，由 UI 展示占位名。
- ChapterContent 接受 Paragraph / Image / Heading / Divider，保留段落顺序和单段完整文本。可读正文至少有一个非空 Paragraph 或 Image；纯图片章有效，只有空白 / 标题 / 分隔符无效。空 Paragraph 可在有效正文中表达已确认的语义空白。
- Paragraph 的 alignment 为 start / center / end，leadingIndent 为整数 0–8 em，表示段落首行缩进，不是整段左内边距；展示用前缀不计入原文位置。当前不启用 text runs / 嵌套 AST；Source 的 Ruby 初始降级为基字加括注、强调保留文字，不在 Domain 处理站点标签。
- Paragraph / Heading 可携带有序的 inlineImages：每项用 Unicode 码点偏移引用文本中的单个 U+FFFC，保存 MediaRef、alt 和 em 宽高；图片参与相同的资源校验与生命周期。无行内图片的旧记录及内容身份保持兼容，em 尺寸只影响布局，不改变语义身份。
- Paragraph / Heading 可携带按 Unicode 码点定位的有序、不重叠 inlineStyles，保存颜色与相对字号、粗斜体；相邻块可通过 BlockBox.group 共享简单容器。两者均为纯 Dart、可序列化的排版元数据，不改变 blockKey / contentRevision，旧记录缺字段时使用默认值。排版缓存通过完整内容值变化失效。
- 图片尺寸各自可未知；已知值须正数。封面和正文图片必须属于相同 Source。ImageBlock 尺寸为后续可发现的布局元数据，更新尺寸不改变 blockKey / contentRevision；mediaId、alt、caption 的改变会改变语义身份。
- ReadingProgress 持有 NovelSummary 快照以保留离线标题 / 封面，并检查 ChapterKey 与快照属于同一本书；是否收藏由独立 BookshelfEntry 表示。lastReadAt 统一为 UTC 毫秒，写入先后由持久化 sequence 控制。

### 摘要 v1 与序列化

固定输入为无额外空白的 JSON 数组：`["shiori",1,kind,fields]`，再按 UTF-8 编码、SHA-256 输出 64 位小写十六进制。fields 只允许字符串、整数、布尔值、null 和嵌套数组，拒绝 map / 浮点值，避免字段顺序和非有限数歧义。文本只将 CRLF / CR 统一为 LF；不 trim、不做 NFC/NFKC，不改变全角字符、标点、emoji、段内换行或首尾空白。拒绝孤立 UTF-16 surrogate，避免编码替换造成内容碰撞。

| 摘要 | 固定 fields 顺序 |
| --- | --- |
| Paragraph 语义 | text、alignment.name、leadingIndent；有行内图片时追加 `[offset, media.identityFields, alt]` 列表 |
| Image 语义 | `[sourceId, mediaId]`、alt、caption；不含 width / height |
| Heading 语义 | text、level（1–6）；有行内图片时追加 `[offset, media.identityFields, alt]` 列表，再追加非默认 alignment，默认 start 保持旧格式 |
| Divider 语义 | 空数组 |
| blockKey（kind=block） | block kind、该类 semantic fields、同章该语义的 occurrence（从 0 开始） |
| contentRevision（kind=chapter） | title、按正文顺序排列的 blockKey 数组 |
| Catalog revision（kind=catalog） | `[sourceId, novelId]`，然后每个卷依次为 `[groupId,title,isSynthetic,章节数组]`；章节项为 `[[sourceId,novelId,chapterId],title,ordinal]` |

ChapterContent 统一重新分配 occurrence，不信任调用方手填值。不同语义块的插入不改变既有块键；在同样内容的重复块之前插入另一个相同块会改变后续 occurrence，这是规则的明确限制。blockKey 只在章节内使用；纯文本内容完全相同的不同章节可以得到相同摘要，业务定位始终同时使用 ChapterKey。

ChapterContent 提供 toJson / fromJson；读取时校验 normalizationVersion、块类型、blockKey、occurrence 和 contentRevision。JSON 返回的是独立容器，改动它不会修改值对象。存储 envelope 的 parserVersion、cache codec version、抓取时间不进入 Domain 摘要；其他模型由存储层 codec 负责。ReaderSettings 当前为 schemaVersion=3；读取 v1 / v2 保留原数值与阅读明暗，v1 补 paged，旧版统一补 paper=paper、controlsHintSeen=false。未知版本仍拒绝。

字号、屏宽、DPR、主题、pixelOffset、layoutKey、临时渲染切片都不进入正文摘要或序列化。一个极长 Paragraph 始终一个语义块，presentation 可临时切片但不能回写 Domain。

测试中的固定向量由 .NET `SHA256.HashData` 对手写精确 UTF-8 JSON 独立计算，包含 paragraph 语义、重复块 0/1、image、chapter 和 catalog。`tool/domain_example.dart` 在两个实际 Dart 子进程中输出完全一致，Windows 的输入/输出编码显式指定 UTF-8。

### 阅读位置与设置

ReaderPosition 的 blockIndex 非负，blockFraction / chapterFraction 必须有限且位于 0..1；NaN / Infinity / 越界直接拒绝，不静默改写错误进度。fractionFor 依 `(blockIndex + blockFraction) / blockCount` 计算，检查 index 属于本章；空内容仅允许 0/0 起点。文本 fraction 按 Unicode code point 偏移定义，UTF-16 布局索引转换留 presentation。构造位置时尚无正文实例，不假装已验证 blockKey 在某章内存在；实际恢复由阅读器处理。

像素提示必须同时包含合法 pixelOffset 和 layoutKey，仅用于同布局提示，不能替代语义位置。ReaderSettings 当前 schemaVersion=3，默认字号 20、行高 1.6、段间距 20、左右边距 40；有效历史排版保留，未知版本拒绝。ReaderMode.scroll 只保留兼容解码，生产偏好层归一化为 paged，详见[阅读器](reader.md)。

AppSettings 独立 schemaVersion=2，包含 system / light / dark 和 teal / blueGrey / warmBrown / softPink；旧 v1 补默认青绿，不借用阅读主题。ReaderPaper 表示阅读纸色，controlsHintSeen 记录提示已确认；恢复默认保留该提示状态。所有值模型不含 Flutter Color 或语言文案。



### 本地与缓存模型

本地书籍以原文件 SHA-256 标识，章节使用稳定解析定位符。LocalNavigationEntry 独立保存嵌套目录与可选 blockKey，不改变 Catalog 章顺序；LocalBookInfo / LocalBookDeletion 描述管理结果，不暴露平台路径。规则见[本地导入](local-import.md)。

CachedChapter / CacheOverview / PrefetchState 是不可变投影，预取目标是既有 ChapterKey，不代表已读或未经确认的续卷关系。见[契约](contracts.md)与[缓存](architecture.md)。

模型与摘要测试位于 `test/domain/`；`fvm dart tool/domain_example.dart` 使用自制内容演示跨进程确定性。

### 本地重解析位置

`migrateLocalPosition` 是纯 Dart 确定性迁移，输出不可变进度与 approximate 等级。使用章节/块身份、唯一文本/图片语义、受限邻近窗口，无法唯一匹配时回退比例/邻章并标记近似。跨块匹配按 code points；所有重解析位置清 layoutKey/pixelOffset，近似位置不保留 completed。EPUB 3 资源首次章键兼容旧规则，后续 occurrence 使用独立摘要 kind，与媒体资源身份分离。见[重解析规则](local-import.md)。

本地链接侧表与主阅读顺序仅属于本地书籍元数据；正文块文本及 blockKey/contentRevision 不因新增链接交互变化。辅助文档仍使用 ChapterContent 和本地资源身份，但不伪装成 spine occurrence 或推进主阅读进度。缺失目标必须为显式不可用项；不存储原始 URL 供 presentation 解释。


## 应用结构

### 页面与行为

正式入口为 `lib/main.dart`，组合根负责初始化本地存储、偏好、导入订阅和在线服务；开发入口为 `lib/main_dev.dart`，不进入生产依赖图。

首页只有书架，没有发现页或底部推荐标签。顶部展示品牌图，保留搜索与更多菜单；导入在更多菜单中。继续阅读使用本地进度，书架封面统一 2:3 容器、完整显示图片，标题行数不改变封面尺寸。本地书在书名下方以小号次要文字标记“本地 · EPUB / TXT”，网格和列表一致；格式信息尚未就绪时显示“本地”。在线书移出同时清缓存，失败保留条目供重试；本地书移除先确认，再删除应用内文件和进度，详情成功后返回首页。均无撤销入口。

搜索显式提交才请求，不随输入自动发请求。结果支持分页、错误重试与空状态；不向应用 UI 暴露 Source 游标、原始协议或站点诊断。详情展示简介、书架操作和目录；真实分组与合成无卷分组保持区别，目录顺序来自领域快照。

阅读入口汇集在线缓存和本地书籍；本地 EPUB 目录可按嵌套条目 / fragment 直接定位。继续阅读和历史使用语义位置。具体规则见[阅读器](reader.md)、[本地导入](local-import.md)和[缓存](architecture.md)。

### 状态与资源所有权

Presentation 依赖领域契约，通过显式注入获得服务。应用根拥有共享 Repository、调度器、图片缓存与数据库；页面只关闭自己创建的请求、订阅、会话和 lease，不关闭借用的共享服务。

请求切换使用取消及代次判断，旧响应不能覆盖新查询或已销毁页面。Controller 订阅更新流后再发起加载；共享流不因一个页面退出而关闭。应用关闭时先停预取与媒体消费者，最后关闭数据库，详见[契约](contracts.md)。

### 外观与本地化

应用外观和阅读器纸张 / 排版分开存储。应用支持跟随系统、浅色、深色，强调色包括青绿、蓝灰、暖棕、淡粉；阅读器设置独立见[阅读器](reader.md)。

用户文案统一维护在 `lib/l10n/app_zh.arb`、`app_en.arb`，使用 `AppLocalizations`；修改后运行 `fvm flutter gen-l10n` 并提交生成文件。内容标题不作为 UI 翻译，错误展示使用本地化 Failure 映射，不直接打印站点响应。

页面保留 SafeArea、可读语义标签与足够触控区域，关注小屏、横屏、大字和英文长度。iOS 路由遵循平台返回方式；自动化语义测试不能替代 TalkBack / VoiceOver 设备验证。


## 数据库与用户数据保护

### 当前存储

| 位置 | Schema | 内容 |
| --- | --- | --- |
| `users/users.sqlite` | v4 | bookshelf、reading_progress、progress_sessions、prefetch_choices、prefetch_settings、local_books、local_chapter_revisions |
| `disposable/cache.sqlite` | v2 | novel_cache、catalog_cache、chapter_cache、image_cache、image_owners |
| 平台 preferences | 独立 codec | readerSettings v3、appSettings v2 |
| `users/books/` | manifest v1 | 本地书托管原件、语义正文索引与媒体 |

AppPaths 通过 path_provider 解析 ApplicationSupport / temporary，固定 `shiori/production` 或 `shiori/development` 子目录。机器绝对路径、URL 和 Source 秘密不进入持久身份。

LocalDatabases.open 顺序打开用户库和缓存库，各用 NativeDatabase.createInBackground 的后台连接；应用根拥有数据库，Repository 借用。运行期复用连接，不逐页 open。localBooks 管理器负责文件回收，先关闭管理器，再关库。

### 事务与 codec

Library 写入由事务串行执行；重复收藏保留首次 addedAt，移除书架保留历史。书架按最近阅读时间（无历史时 addedAt）降序，平局按 Source / Novel 键排序。watch 返回初始及后续不可变快照。

beginProgressSession 原子递增 generation 并重置 sequence；saveProgress 只接受当前 generation 和严格递增 sequence，旧写返回 false。clearHistory 推进 generation 并保留会话保护行，防止晚响应恢复已清历史。提交前取消可回滚，提交后返回真实结果。

缓存存规范化领域 JSON、codec / parser 版本及抓取、过期、访问时间。校验类型、身份和摘要，单项损坏局部失败；离线列表同时检查外层 codec 和内部数据。TTL / LRU 由[缓存策略](architecture.md)负责。

用户与缓存没有跨库事务或跨库外键；缓存失败不能回滚已保存的书架和进度。用户库升级成功而缓存打开失败时保留用户库，不删除重建。

preferences 使用独立 JSON key，Store 串行写入，读取等待已排队写入。坏 JSON、未知版本或非法数据返回默认与安全诊断，读操作不覆盖坏值 / 未来版本。偏好不承诺与 SQLite 跨存储事务。

### 迁移与生成

保留 `lib/data/local/database/schemas/user/` v1 / v2 / v3 / v4 和 cache v1 / v2 快照。schema、记录 codec、parser 版本、偏好版本、进度 generation 互不替代。

升级 DDL、完整性检查和 user_version 同事务提交；失败回滚，损坏或未知未来版本保留原文件并报错。不提供自动删用户库、drop/recreate 或生产 reset 来绕过故障。旧快照不能被当前 schema 重新导出覆盖。

运行时 Drift 2.32.1 / sqlite3 3.5.2；生成器独立在 `tool/db_codegen`，避免 analyzer 与固定 Flutter 工具链冲突。安装工具锁定依赖后：

```sh
bash tool/generate_database.sh
fvm flutter test --no-pub test/data/local
```

Windows 用 `tool/generate_database.ps1`。生成 `.g.dart` 与 schema 快照一并评审，CI 检查 diff 及新增快照。首次正式发布后保留实际发布版本的升级起点与自制旧库样本，不能仅靠开发 schema 声称正式升级通过。

### 备份与恢复

Android XML 排除 disposable、开发目录和导入暂存，用户数据可参与系统备份 / 换机。iOS 尚未完整验证缓存排除属性；目录分开本身不证明不会备份。系统备份恢复和整机磁盘耗尽按用户决定未执行。

排障先退出应用，保全数据库、WAL / SHM、preferences、托管原件及 manifest，在副本上检查；不以卸载或删库作为默认恢复步骤。本地文件发布协议见[本地导入](local-import.md)。

### 重解析发布

v4 仅添加活动 bundle、解析版本、维护标记及章节版本索引，旧记录 active_bundle=NULL 仍读根 manifest。DDL 与 user_version 同事务升级。重解析切换活动文件指针、位置及 generation 使用一个事务；文件先就绪再提交，未引用文件由管理器恢复清理。维护标记重启后解除；坏活动 manifest 不触发旧文件删除。详见[重解析规则](local-import.md)。


## 缓存、图片与预取

### 在线内容

详情默认 TTL 24 小时、目录 1 小时；正文没有硬性到期，显式刷新产生新快照。cacheOnly 不访问 Source，cacheFirst 优先缓存并可后台刷新，refresh 显式获取；刷新失败保留可用旧值并标注失败，不在阅读中偷偷替换活动正文。

元数据 / 正文缓存预算 64MiB，LRU 超限清到 80%。图片文件预算 192MiB，活动 lease 锁定其文件。用户库、偏好与本地导入原件不属于可淘汰缓存。

### 图片

编码内存总预算 64MiB（包括正在读取的字节），生产空闲保留 32MiB；单图 20MiB，读取并发 2、等待队列 20、截止时间 45 秒。解码串行、单图最多约 400 万像素，解码 LRU 最多 5 项 / 24MiB。

每次加载返回独立 `MediaLease`，消费者必须关闭；不能广播同一 lease 给多个页面。持久化使用 staging 写入 / flush / 原子改名后写索引，存稳定 MediaRef 和校验和，不持久化带时效凭据的 URL。路径、长度、哈希和可解码性检查通过才列为离线可用。

文件写入失败可继续使用 memoryOnly 图片，但携带 persistenceFailure，不宣称已经离线保存；损坏或缺失资源局部失败。图片身份与尺寸提示分离，重排不更改媒体身份。

### 有限预取

先处理当前页附近前 4 / 后 1 张图片，再处理当前章剩余图片，最后才处理用户选定的下一章。最多提前一章，不靠 ordinal 推断下一卷，不创建下一章进度会话。

进程后台预算 64MiB / 200 次 HTTP 尝试，调度全局并发 2、后台 1、同源启动间隔至少 500ms，重试和跳转也计预算。前台请求优先。遇到限额、访问限制或 429 暂停，用户显式恢复才开始新预算，不无限循环补下载。具体请求规则见[网络](architecture.md)。

这是阅读辅助缓存，没有整本下载中心、永久保留或系统后台下载服务。

### 清理与竞态

缓存管理页按书或全部清理需要确认；书架 / 详情中在线书移出先清该书缓存，无撤销；本地书经确认后走托管文件完整删除流程，见[本地导入](local-import.md)。清理推进 generation、停止旧预取，晚响应不得回填已清数据；已有活动 lease 在关闭前仍可读取，新读取看到 cache miss。按书清理保留其他书共享的资源。

本地导入走独立文件层，清在线缓存不会删除原件、书架、进度或设置。离线列表必须同时校验外层 codec 与内部数据，不兼容记录不能列为可读。


## 请求预算与诊断

请求作用域 BackgroundWork（Dart Zone 传递元数据，不是全局服务定位器）。进程所有者共享 BackgroundBudget，Source 定位 / 重定向 / 重试和流式响应体均记账。Scheduler 保存提交时 Zone，避免延迟执行继承其他请求上下文；共享后台资源遇前台消费者立即提升排队优先级，HTTP 单次大小 / deadline / 同源间隔保持不变。详见 [缓存](architecture.md)。

Source 各自拥有 NetworkTransport / Dio，注入允许的 HTTPS URI 和私有 Header / 响应接收策略；自动 redirect 关闭。响应通过流逐块计数，解压后元数据最多 8 MiB、媒体最多 20 MiB；MIME 不符、声明 / 实际长度异常及超限均不返回成功正文。connect / send 10s，receive 默认 20s（媒体可指定 30s），绝对 deadline 覆盖等待响应及流读取。取消绑定 Dio abort 和响应订阅取消；没有重写 Domain 契约。

AppLogger 只接受类型化摘要字段，内存最多 200 条；Release 不保存成功请求明细。不接收 URL / body / Header / exception / 自由文本。opaque SourceId 用 SHA-256 标识，requestId 为本地随机 ID；取消不产生错误事件。Source 原始响应只留在 data 层，状态与 Dio 异常映射为既有 AppFailure。

依赖：精确锁定 Dio 5.11.1，官方 [包元数据](https://pub.dev/api/packages/dio/versions/5.11.1) 与本机下载包均声明 Dart >=2.18.0 <4.0.0，满足本项目 Dart 3.10.3；使用默认 IO adapter，未增移动平台插件、修改最低 OS 或放宽 TLS 校验。fake_async 1.3.3 从既有传递依赖提升为直接 dev 依赖。

离线复验：`fvm flutter test --no-pub test/data/network --reporter expanded`。使用 FakeAdapter 和秘密哨兵检查字节 / MIME / 长度、超时、取消、错误映射与日志；未以 fake 宣称真实网站 HTTPS / 会话有效。

应用组装层拥有共享 RequestScheduler，每个 Source 的 NetworkClient 借用它与独立 transport。默认全局 2 在途、Source 2 在途、后台 1，Source 启动间隔 500ms、队列 20；前台等待时不启动新后台，满队列可取消尚未启动的后台为前台让位。取消 / 过期排队立即移除；已启动工作收到取消后仍占槽直到底层退出，不用逻辑完成伪造空闲连接。

逻辑 send 的队列、退避、最多一次额外 safe-read 重试及最多 5 次重定向共享 45s deadline。safeToRepeat 默认 false，包括 POST；仅 Source 有证据明确声明后才能自动重复。502 / 503 / 504、连接 / 超时可参与，其他状态不自动重试。429 在释放调度槽前冻结同 Source 排队请求，合法 Retry-After 按秒或 HTTP 日期处理，缺失 / 无效使用 60s；没有自动到期重放，需用户再次发起。

逐跳重新调用 Source policy；拒绝降级、未允许 URI、循环及超跳数。301 / 302 的 POST、303 非 HEAD 改 GET 并丢弃 body；307 / 308 保留方法。跨 origin 移除 Authorization / Cookie / Referer 以及自定义请求头，仅保留 representation 类头；有 body 的跨域 POST 保持型重定向拒绝。Cookie 接收钩子属于私有 Source，当前不引入 cookie_jar 或会话恢复策略；未来恢复调用仍须经过此 scheduler，并禁止叠加通用 retry。

时间测试使用 fake_async 与确定性 attempt 替身隔离 Dio 拦截器 Future 的时间域；另以真实 Dio + FakeAdapter 验证响应处理、取消和 redirect method / Header，不将二者混为真实 TLS 测试。

### 装配和所有权

应用组装者创建一份 RequestScheduler；每个 Source 创建 SourceNetworkPolicy、NetworkTransport，并把二者和同一 scheduler 注入 NetworkClient。Source 私有适配器构造 NetworkRequest，显式声明 MIME / 编码后的 body / 可重放性；UI 不使用这些 data 类型。owner 退出时关闭自己的 transport，应用退出时关闭 scheduler；NetworkClient 不擅自关闭借用对象。后续 Source 初始化 / 恢复应沿用同一个绝对 deadline，并以 safeToRepeat=false 禁止恢复与通用 retry 叠加。当前 Source 使用无会话分支，不自动恢复登录。

Transport.attempt 是内部“单次 HTTP 尝试”边界：3xx / 4xx / 5xx 可作为 NetworkResponse 交给 NetworkClient 处理，不是业务成功；业务读取应使用 client.send，由它处理 redirect / 429 / retry / status failure。响应 Header 含敏感数据，仅供 Source 私有策略，不传入 Domain 或 Logger。每次连接在响应流读取期间持有调度槽；当前按上限缓冲完整 bytes，未实现跨层零拷贝流。调用取消会立即 abort，原始 adapter 清理异常不会透出。


### Source 收紧规则

NetworkRequest.maxRedirects 为 0..5，Source 可以收紧。当前 LightNovel JSON API 设为 0，POST 不自动重放、不恢复未经确认的会话。网络替身测试不等于真实 TLS 或实时书源可用性。
