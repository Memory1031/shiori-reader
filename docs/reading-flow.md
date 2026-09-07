# 目录、跨章阅读、书架与继续阅读闭环

2026-09-07。按用户授权顺序实施 DETAIL-002 → READER-007 → SHELF-001 → HOME-001 → SHELF-002 → PROGRESS-001，六项均 DONE。本文记录本轮实际范围，不能外推为完整离线下载、真机性能或发布验收。

## DETAIL-002

CatalogController 先订阅对应 catalogUpdates 再 cacheFirst 加载，沿用详情的陈旧快照/局部刷新失败语义、身份验证、取消和通知优先规则。CatalogView 是详情和 Reader 共用的目录列表；按源顺序显示卷与章节，合成无卷目录不加虚构标题，缺名卷使用本地化名称。卷折叠及当前选择按 groupId/ChapterKey 保持，目录更新移除无效状态。同名章、番外通过完整 ChapterKey 选择；openCatalog 使用固定路由名返回选择，取消返回 null。

目录以轻量行引用展开，ListView.builder 懒构建 Widget；2,000章测试可见条目少于30。详情目录按钮和阅读器目录按钮共用同一页面，空目录与加载失败区分。没有新增章节层级或改变 Source 解析规则。

## READER-007

BookReaderScreen 持有单个 ReaderController 和目录 Controller，复用原有 ReaderContentView、双模式视口、图片组件和进度追踪。前/后章按规范化目录顺序跨卷选择，首末端禁用。切换先 await 进度 flush；保存失败保留当前会话并提示重试。切换释放旧会话及请求，再加载新章；章内容 ready 前不写入新章进度。加载失败允许重试或返回，目录仍可重新选择。

Android 真图文探针 `integration_test/live/reader_smoke.dart` 使用正式 SourceServices / Repository / 内存 ImageRepository，以及独立内存数据库。仅检查既定书籍31607、章节309555与首张插图；不启用持久图片缓存、不保存正文/图片、不把渲染限制放进生产组件。探针限制其他插图为本地占位，避免页面懒加载扩大真实请求范围。

首轮授权12次，实际10次：真实搜索/详情/四卷十章/4084正文块/14图统计/首图2048×829解码均通过，但页面挂载失败。原因是探针提前关闭唯一图片租约，内存仓库按契约释放图片，而后续网络已封闭。修正为持有租约直到挂载完成；用户另行授权10次，补验实际10次，正式 ReaderContentView 和 RawImage 均挂载成功。旧失败记录保留，不能用后续成功抹去。

第二次探针带独立一次性标记 `reader007-live-20260907-v2.started`，默认 READER007_LIVE 未开启时零请求；本轮授权已用于对应验证，不自动删除标记或再次运行。请求串行、至少1秒间隔、无重试，页面挂载阶段禁止网络。记录见 `docs/validation/reading-flow.json`。

## SHELF-001

LibraryController 借用 LibraryRepository，分别监听书架/最近阅读快照，保留已显示数据和独立读写失败。按最近阅读时间、加入时间、sourceId/novelId 稳定排序；异步写 single-flight。添加通过 putBookshelf 保持幂等，移除只删收藏，撤销恢复原 BookshelfEntry 和加入时间。写失败保留数据，用户可重做原操作；缺源/缺封面仍显示本地标题。

BookshelfView 支持网格/列表、封面/标题、移除与撤销、空状态搜索。500本实际 fixture 网格有懒构建检查；大字可切换列表，长标题保留详情入口。媒体通过 SourceImage 契约加载，失败局部显示；书架数据不等图片或网络。SQLite 重开测试验证收藏与未收藏历史持久化、稳定排序和清除边界。

## HOME-001

ReadingHome 默认显示本地书架，发现页仅在被选择且 SourceDescriptor.supportsDiscover 为 true 时请求；不支持推荐时显示书源说明并保留搜索，不伪造排行榜。发现加载失败保留已有 sections 并提供符合失败策略的重试。来源选择与分页能力显式传入 SearchScreen。

`main.dart` 通过 ProductionApp 打开正式环境数据库、偏好和 SourceServices，再注入首页/详情/Reader，构造和空书架启动不发 HTTP。生产代码不导入 dev。开发菜单新增书架首页入口，也可使用 `--target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=home`；Fixture 内容与生产装配隔离。App 外观沿用既有独立偏好；导入入口明确说明 TXT/EPUB 和外部打开仍待 LOCAL 系列任务，不提供无响应按钮。

## SHELF-002

详情通过 LibraryObserver 观察借用的同一 LibraryController，收藏状态跨页面同步。操作用详情现有 NovelSummary，不为收藏重发元数据请求；写入期间禁用，显示业务失败，已接通页面不显示“功能开发中”。Observer 不拥有 Controller，导航树整体卸载时也能安全移除监听。

首页显示最近一项继续阅读入口，并提供完整最近阅读列表；未收藏的阅读记录同样展示本地标题快照。历史按小说单独清除，调用 clearHistory 使旧写 generation 失效，保留书架/缓存。详情开始/继续标签由实际历史驱动。所有继续操作通过统一 ContinueDestination 传 NovelKey，不把身份放进 route name。

## PROGRESS-001

ContinueController 先读取本地进度；有记录且章节 cacheOnly 命中时直接选择原 ChapterKey，不请求 Source。其他情况先查缓存目录，缺缓存才 cacheFirst 获取：无记录选首章，原章节消失则按原 ordinal 在当前目录内有界降级并提示。空目录给目录选择入口，不清空原进度；进度读取失败不当成“从头开始”。选择阶段没有任何历史写入，真正 Reader ready/布局稳定后由既有 Tracker 保存。

Android 返回等待 flush，未保存时留在当前 Reader 提供重试；切章也走同一保存边界。inactive/hidden/paused 触发 flush，既有周期/尾沿提交仍是强杀恢复的基础，不声称 force-stop 后仍能执行 dispose。Cupertino 保留 canPop 以支持系统交互式返回，返回通知发起 flush；持久保证仍以最后完成提交为准，iOS 实机手势/lifecycle 留 IOS-004。没有隐藏系统栏或修改平台 SystemChrome 模式，因此不引入离开 Reader 后的系统栏恢复差异。

Android 离线 `integration_test/progress_smoke.dart` 使用正式 LocalDatabases / LocalLibraryRepository、Fixture 内容与专用 `phase5-lifecycle-probe` 子目录，绝不读取/清理普通用户库。已实际验证：磁盘双库打开、阅读器 ready 后提交、inactive→hidden→paused→resumed、恢复后读取、系统返回、force-stop 后冷启动位置快照相等。该次成功说明本次独立测试目录可用，不自动关闭 UI-002 历史滚动重开问题，也不外推所有旧库/极端恢复场景均通过。

## 验证与剩余范围

- 新增15项离线测试，全量 **270项 PASS**；`.tooling/evidence/phase5-tests.txt`。复用既有恢复、DB写失败、布局变化、媒体失败及契约回归。
- `flutter analyze --no-pub`：No issues found。新增文案均有中英文 ARB / gen-l10n。
- 正式 `lib/main.dart` 和开发 `lib/main_dev.dart --dart-define=SHIORI_SCENARIO=home` Android Debug 构建均 PASS。模拟器已安装恢复正常离线开发首页包，启动 UI 层级确认书架/发现、最近阅读及搜索入口（`.tooling/evidence/phase5-home.xml`）；不再停留在一次性联网探针。真实 Source 和离线生命周期 Android 探针结果单独记录，不以构建代替 runtime。
- iOS Level A：共享 Flutter UI/Domain、既有跨平台存储和解码、Cupertino 路由；没有新增依赖或原生插件。iOS runtime 仍 DEFERRED_NO_MAC。
- 未执行本地导入、持久图片缓存、缓存容量管理、预取、ARM64真机性能、正式迁移/损坏恢复或发布审计。本轮不自动领取 CACHE-001。
