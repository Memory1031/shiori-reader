# 数据库与用户数据保护

## 当前存储

| 位置 | Schema | 内容 |
| --- | --- | --- |
| `users/users.sqlite` | v3 | bookshelf、reading_progress、progress_sessions、prefetch_choices、prefetch_settings、local_books |
| `disposable/cache.sqlite` | v2 | novel_cache、catalog_cache、chapter_cache、image_cache、image_owners |
| 平台 preferences | 独立 codec | readerSettings v3、appSettings v2 |
| `users/books/` | manifest v1 | 本地书托管原件、语义正文索引与媒体 |

AppPaths 通过 path_provider 解析 ApplicationSupport / temporary，固定 `shiori/production` 或 `shiori/development` 子目录。机器绝对路径、URL 和 Source 秘密不进入持久身份。

LocalDatabases.open 顺序打开用户库和缓存库，各用 NativeDatabase.createInBackground 的后台连接；应用根拥有数据库，Repository 借用。运行期复用连接，不逐页 open。localBooks 管理器负责文件回收，先关闭管理器，再关库。

## 事务与 codec

Library 写入由事务串行执行；重复收藏保留首次 addedAt，移除书架保留历史。书架按最近阅读时间（无历史时 addedAt）降序，平局按 Source / Novel 键排序。watch 返回初始及后续不可变快照。

beginProgressSession 原子递增 generation 并重置 sequence；saveProgress 只接受当前 generation 和严格递增 sequence，旧写返回 false。clearHistory 推进 generation 并保留会话保护行，防止晚响应恢复已清历史。提交前取消可回滚，提交后返回真实结果。

缓存存规范化领域 JSON、codec / parser 版本及抓取、过期、访问时间。校验类型、身份和摘要，单项损坏局部失败；离线列表同时检查外层 codec 和内部数据。TTL / LRU 由[缓存策略](cache.md)负责。

用户与缓存没有跨库事务或跨库外键；缓存失败不能回滚已保存的书架和进度。用户库升级成功而缓存打开失败时保留用户库，不删除重建。

preferences 使用独立 JSON key，Store 串行写入，读取等待已排队写入。坏 JSON、未知版本或非法数据返回默认与安全诊断，读操作不覆盖坏值 / 未来版本。偏好不承诺与 SQLite 跨存储事务。

## 迁移与生成

保留 `lib/data/local/database/schemas/user/` v1 / v2 / v3 和 cache v1 / v2 快照。schema、记录 codec、parser 版本、偏好版本、进度 generation 互不替代。

升级 DDL、完整性检查和 user_version 同事务提交；失败回滚，损坏或未知未来版本保留原文件并报错。不提供自动删用户库、drop/recreate 或生产 reset 来绕过故障。旧快照不能被当前 schema 重新导出覆盖。

运行时 Drift 2.32.1 / sqlite3 3.5.2；生成器独立在 `tool/db_codegen`，避免 analyzer 与固定 Flutter 工具链冲突。安装工具锁定依赖后：

```sh
bash tool/generate_database.sh
fvm flutter test --no-pub test/data/local
```

Windows 用 `tool/generate_database.ps1`。生成 `.g.dart` 与 schema 快照一并评审，CI 检查 diff 及新增快照。首次正式发布后保留实际发布版本的升级起点与自制旧库样本，不能仅靠开发 schema 声称正式升级通过。

## 备份与恢复

Android XML 排除 disposable、开发目录和导入暂存，用户数据可参与系统备份 / 换机。iOS 尚未完整验证缓存排除属性；目录分开本身不证明不会备份。系统备份恢复和整机磁盘耗尽按用户决定未执行。

排障先退出应用，保全数据库、WAL / SHM、preferences、托管原件及 manifest，在副本上检查；不以卸载或删库作为默认恢复步骤。本地文件发布协议见[本地导入](local-import.md)，已有迁移 / 故障 / 设备结果见[验收摘要](validation/README.md)。
