# DB-001 / DB-002：本地存储

2026-09-07。DB-001 的 v1 schema、目录、生成快照与非破坏迁移基线已完成；DB-002 的本地仓库和设置实现已完成，Android 探针已验证正式 SQLite / preferences。**两项 DONE**，具体验证边界见下方记录。

## 数据与所有权

`LocalDatabases.open(AppPaths)` 创建两个数据库，各自使用 `NativeDatabase.createInBackground` 的单后台连接，依次完成用户库、缓存库的打开与 schema 检查。装配方拥有并关闭数据库；LibraryRepository 和 NovelRecordStore 借用连接，不自行关闭。应用运行中复用这一组连接，不为每个页面重复 open。生产应用的 Repository / Source 装配仍归 CORE-005，当前普通入口不自行写入用户数据。

- `users/users.sqlite`：bookshelf、reading_progress、progress_sessions。复合键包含 source_id / novel_id；进度快照和位置原子写入。分数、索引、代次和 sequence 有 SQL CHECK。进度表不额外伪造 Domain 中不存在的 chapterTitle。
- `disposable/cache.sqlite`：novel_cache、catalog_cache、chapter_cache，章节另包含 chapter_id。存规范化 Domain JSON 和 codec / parser 版本、抓取 / 过期 / 访问时间、UTF-8 payload 字节数。当前只提供基本记录读写；不执行 TTL 判断、LRU、图片元数据、文件缓存或清理任务。last_access_at 初始为 fetched_at，后续缓存策略再负责访问更新。
- 用户表没有指向缓存表的外键；清缓存不需要也不允许操作用户数据库。没有跨库事务；缓存写失败不能回滚已保存的书架或进度。

LibraryRepository 的所有写操作通过 Drift 事务串行执行。重复收藏保留首次 addedAt，移除收藏返回原条目且保留历史；书架按最近阅读时间（无历史时 addedAt）降序，平局按 Source / Novel 键排序。watch 返回初始与后续不可变快照，SQL / codec 错误作为 Failure 数据发出，不泄漏原始异常。

进度会话代次在 progress_sessions 中持久化；beginProgressSession 原子递增 generation 并重置 sequence。saveProgress 只接受当前代次且严格递增的 sequence，旧写返回 false。clearHistory 删除历史并推进代次，保留 session 行作为拒绝晚写的记录；移除书架不删除这条保护记录。取消在事务内提交前检查，取消则回滚；已经提交的写入返回真实成功结果。

NovelRecordStore 只接受类型化 Detail / Catalog / Chapter；缓存 codec 检查版本、类型、身份以及目录 / 正文摘要。写失败保留旧记录，单条损坏返回局部 cache Failure，不自动清库、不影响其他记录。没有网络调用，也没有 Source locator 表；只有 SRC-010 实证需要时才扩展。

ReaderSettings 继续使用现有 v1 codec，通过注入的 SharedPreferencesAsync 存一个 JSON 字符串，key 按 production / development 隔离。单 Store 串行保存，读取等待已排队的保存；坏 JSON、类型、数值或未知版本返回默认设置并写入不含路径 / 原始值的本地诊断，读取不覆盖坏值或未来版本。设置不是关键数据，不承诺与 SQLite 的跨存储事务。此处没有提前增加 READER-004 设置 UI 或阅读模式 codec。

## 路径与备份（OQ-08）

AppPaths 从 path_provider 取得 ApplicationSupport / temporary 根，固定子目录 `shiori/production` 或 `shiori/development`；数据库和托管图片 / 正文在 support 内分离。staging 位于 disposable 下，与目标文件同文件系统；临时日志使用 temporary。Source ID、URL、宿主绝对路径均不参与磁盘目录命名或持久配置。

选择拆库，避免可淘汰记录混入用户备份文件。Android backup_rules（旧 API）与 data_extraction_rules（API 31+ 的 cloud-backup / device-transfer）均排除 file domain 的 `shiori/production/disposable/` 和整个开发数据目录，用户库保持可备份。两个文件及目录内可能存在的 SQLite journal / WAL 均由目录边界覆盖。临时目录由平台排除。设置使用平台偏好存储的命名空间，与这两个数据库文件分开。

依据：[Android Auto Backup](https://developer.android.com/identity/data/autobackup)、[path_provider 2.1.5](https://pub.dev/packages/path_provider/versions/2.1.5)。Android 路径及实际安装验证见下；完整备份 / 恢复演练归 ANDROID-002，不能把 XML 配置等同于云端恢复成功。

iOS 使用同一 ApplicationSupport 抽象，用户库与 disposable 子目录分开。排除缓存备份的兼容路径为 Foundation `isExcludedFromBackup`；尚未接原生属性设置或实际验证，IOS-005 必须补齐。因此 iOS backup exclusion / runtime 保持 DEFERRED_NO_MAC，不能宣称已排除。此边界不阻止 Android 存储任务验收。

## Schema 与生成流程

两个数据库当前 schemaVersion 都为 1；已提交的快照分别在 `lib/data/local/database/schemas/user` 与 `schemas/cache`。schema version、RecordCodec envelope version、ReaderSettings version、parser version 和进度 generation 互不替代。

尚无历史发布 schema，不虚构旧版本迁移。当前仅创建 v1；未知升级 / 降级直接拒绝，打开时执行 quick_check。坏目录、损坏或未来版本失败后保留原文件，不自动删除重建，不通过 drop/recreate 升级用户表。没有生产 reset 入口。后续 schema 变更必须保留旧快照、提高版本并添加非破坏迁移及测试；完整旧版本 / 损坏 / RC 回归留 DB-003。

运行时固定 Drift **2.32.1**、sqlite3 **3.5.2**、path_provider **2.1.5**、shared_preferences **2.5.5**。计划中的 Drift 2.34.4 生成器要求 analyzer 13，而 Flutter 3.38.4 的 test 1.26.3 要求 analyzer <9；不升级固定 SDK 或强制 dependency_overrides。独立工具包 `tool/db_codegen` 固定 drift_dev 2.32.1 / build_runner 2.10.5，使用自己的 lockfile 与 analyzer 10.2.0；生成产物仍编译在主工程，运行时没有生成器依赖。

```powershell
# 使用项目固定 Dart 3.10.3；首次在工具包解析依赖
Push-Location tool/db_codegen
dart pub get
Pop-Location
./tool/generate_database.ps1
flutter test --no-pub test/data/local --reporter expanded
flutter analyze --no-pub
flutter build apk --debug --no-pub --target test/support/database_probe.dart
```

脚本只复制 schema 输入到被忽略的工具工作目录，再生成 `.g.dart` 与当前版本 snapshot；评审必须检查 snapshot 差异，不得用重新导出 v1 来掩盖受支持数据库的 schema 变化。依据：[Drift native](https://drift.simonbinder.eu/platforms/vm/)、[schema / migrations](https://drift.simonbinder.eu/migrations/)。SQLite 3 由 hooks 打包，不增加旧的 sqlite3_flutter_libs。

## 验证记录

- **127 项完整 Flutter 测试 PASS**，静态分析 PASS。新增 7 项本地测试覆盖内存建表 / 索引 / CHECK、临时目录后台重开、未来 schema 保留、坏目录保护、跨源相同 ID、收藏幂等 / 历史隔离、事务失败与取消回滚、乱序 sequence、持久 generation 与 clearHistory 后重开、缓存 codec / 原子替换 / 单条损坏、设置坏值 / 版本 / 类型与失败。
- 测试只在新建的临时目录模拟坏文件 / 未来版本，并在校验目录归属后清理；未操作真实用户库。SQL trigger 模拟写失败，不能代替真实磁盘满 / 文件系统故障，后者仍归 DB-003 / ANDROID-002。
- Android 探针 `test/support/database_probe.dart` 采用开发路径和正式数据库 / LibraryRepository / NovelRecordStore / SharedPreferencesAsync，首次 MuMu 安装与冷启动 PASS，输出 `DB_PASS coldExisting=false generation=1 reopen=true settings=26 staleWriteRejected=true`。最终移除临时诊断的 APK 连续两次独立启动（进程 6642 / 6764）均为 `coldExisting=true`，generation 从 6 到 7，`reopen=true settings=26 staleWriteRejected=true`；第二次通过 force-stop 后启动验证，包含进度、书架、章节缓存与平台偏好检查。截图 `.tooling/evidence/db-restart.png`。Android `run-as` 实测文件位于 `files/shiori/development/users/users.sqlite` 与 `files/shiori/development/disposable/cache.sqlite`，与 file-domain 备份路径一致。
- iOS Level A：Drift native / sqlite3 hooks 文档支持 iOS；SharedPreferences Foundation 最低 iOS 13，项目 iOS 15 满足；路径通过官方插件，无 Android-only 核心读写。Xcode 最终链接、SQLite ABI、preferences / filesystem 与备份属性实际行为均 DEFERRED_NO_MAC（IOS-001 / IOS-005）。

Windows 构建初次下载 SQLite 库遇到 Dart TLS handshake 错误：通过正常 TLS 的 curl 获取官方 GitHub release 文件，并与 sqlite3 包内 asset_hashes.dart 的 SHA-256 比对后放入被忽略的构建缓存，未关闭证书校验，也未修改应用依赖以引用宿主路径。Android 插件另触发 SDK Platform 35 安装及 Maven 首次下载；具体版本保留在锁文件，临时下载和 Gradle 报告均不属于源码。

构建时另遇到仓库已知 Windows Gradle transform 移动失败及 Kotlin 跨盘增量缓存异常：停止该项目 Gradle daemon 后重试，并在被忽略的项目 Gradle 用户目录中设置 `kotlin.incremental=false`，构建通过；未修改全局 Gradle 配置。

运行期观察：早期探针在 MuMu 间歇返回 SQLITE_CANTOPEN（数据库文件保留且后续可读），新进程与同进程重开阶段均需关注。初始化已改为顺序执行，最终无诊断版本连续冷启动复测通过，但不能据此确认间歇故障根因已彻底消除；保留 ANDROID-002 / DB-003 的真机及反复启动关注项。没有通过删除数据库、自动重建或无限重试绕过故障。SQLite 实际 Android 编译选项 THREADSAFE=1。

最终普通 `lib/main.dart` Android Debug 构建 PASS；127 项完整回归通过后，对最终初始化 / 诊断清理再执行 7 项本地测试与静态分析，均 PASS。备份云端往返、ARM64 真机和 iOS runtime 不在此次成功声明内。
