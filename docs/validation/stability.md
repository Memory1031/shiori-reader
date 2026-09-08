# TEST-002 存储、缓存与竞态故障回归

状态：DONE（2026-09-08）。本轮补齐故障测试缺口，未修改生产实现或 UI。DB-003 的迁移和 codec 修复沿用其独立报告，不重复计为本任务修复。

## 故障矩阵

| 场景 | 确定性证据 | 结果 |
| --- | --- | --- |
| SQLite 空间不足 | 新增 `test/data/stability/storage_failure_test.dart`：临时文件数据库将 `max_page_count` 限制为当前页数，1 MiB 分配确认实际返回 `database or disk is full`；再通过真实 Repository 写大正文 | 远端内容仍可返回；本地旧正文保留，用户书架行未变；记录 `cacheWriteFailed`；一次调用只请求一次，解除页数限制后显式重试保存成功 |
| parser 版本不匹配 | 同上：缓存 parserVersion=2，当前 parserVersion=1，固定 UTC 时钟 | cacheOnly 零 Source 请求且标记 stale；cacheFirst 先返回旧内容，再通过更新流收到一次远端刷新，保存当前版本。覆盖版本不匹配（包括应用回退），不把 parser 与 codec 兼容性混为一谈 |
| 清理后图片晚响应 | 补强 `test/data/media/persistent_image_repository_test.dart`，从直接 invalidate 改为真实 `LocalCacheManagement.clear()`；Completer 控制响应顺序 | 晚响应返回 Failure，图片索引保持空；此文件 11 项通过 |
| 正文晚响应与清理代际 | 复用 `test/data/cache/cache_policy_test.dart`、`test/data/repositories/novel_repository_test.dart` | 清理代际变化、最后调用者取消均阻止旧请求写入；调用者取消互相隔离 |
| 预取停止与有限失败 | 复用 `test/data/cache/reading_prefetch_test.dart` | 清理取消待办，显式恢复前不补写；429 暂停批次，普通图片失败不循环重试 |
| 文件写失败与损坏隔离 | 复用 `test/data/media/persistent_image_repository_test.dart` | staging 被文件阻挡时只返回 memoryOnly，并携带持久化失败；cacheOnly 不假报成功；校验和损坏、丢失图片局部处理 |
| 旧 progress 与重开 | 复用 `test/data/local/repositories_test.dart`、`progress_tracker_test.dart` | generation / sequence / 清历史 tombstone 拒绝旧写；事务回滚不推进序号；失败保留 unsaved，显式重试后重开保留最新进度 |
| 迁移失败、corruption、codec | 复用 `test/data/local/migrations/` 与 `repositories_test.dart`，详见 [DB-003](db-003.md) | schema 事务回滚、损坏文件保留、单项坏缓存隔离、不兼容 codec 不列为离线章节，缓存清理保留用户数据与原文件 |

## 本轮执行

- macOS，项目固定 Flutter 3.38.4 / Dart 3.10.3：完整离线测试 **388 项通过**（新增 2 项）；随后补强图片清理入口，该文件 **11 项通过**。
- `flutter analyze --no-pub`：无问题。
- Android ARM64 真机 BMH-AN10，Android 12 / API 31，Profile 探针构建和执行通过。独立入口 `integration_test/storage_clear_smoke.dart`，通过 path_provider 创建唯一临时根目录，所有数据库与原书哨兵均在其中，不访问生产数据库，也不注册在线 Source。
- 探针结果：seed、reopen、offline_listing、clear、clear_survives_reopen、bookshelf_preserved、progress_preserved、original_preserved 全部 PASS。验证连接关闭后重开；不声称本轮测了进程 kill 或系统备份恢复。
- 探针 finally 关闭资源并删除其临时目录；报告复制至主机后删除手机上的报告。验证后覆盖恢复原生产 Release APK（本轮没有生产代码变动）。该包沿用本机调试证书后备配置，不属于正式签名 RC。

日志位于忽略目录 `.tooling/evidence/`：`test002-tests.log`、`test002-image-tests.log`、`test002-analyze.log`、`test002-profile-build.log`、`test002-android-report.json`。

## 复现与边界

```sh
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter test --no-pub test/data/stability/storage_failure_test.dart test/data/media/persistent_image_repository_test.dart --reporter expanded
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter test --no-pub
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter analyze --no-pub
```

Android 构建沿用 [开发说明](../development.md) 的本机 JDK / SDK 设置，使用 `--profile --target-platform android-arm64 --no-pub --target integration_test/storage_clear_smoke.dart`。启动后读取应用 support 目录中的 `test002-report.json`；运行完恢复生产包。每次运行创建全新临时目录，哨兵与时钟固定，竞态使用 Completer / 更新流等待，不依赖真实网络时序。

SQLite 页数限制只制造测试数据库的 SQLITE_FULL，不写满设备文件系统；图片测试模拟文件系统写入失败，不声称实际 ENOSPC。用户先前决定跳过的系统备份恢复和整机磁盘写满继续不执行。Windows 本轮未运行；iOS 仅审查共享 Dart / Drift / path_provider 路径兼容性，未运行 iOS 探针，运行时验证仍归 IOS-005。性能验收属于 TEST-003，本轮不提供性能结论。
