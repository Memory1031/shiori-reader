# CORE-005：通用小说 Repository（2026-09-07）

`DefaultNovelRepository` 实现既有 `NovelRepository`，通过 `SourceRegistry` 与 `NovelRecordStore` 连接源契约和规范化 SQLite 记录。没有站点协议、URL、selector、会话初始化或新的依赖；没有替换开发 fixture 或自动接入生产应用。真实 Source 客户端仍由 SRC-005 开始实施。

## 装配与所有权

使用 `createNovelRepository(sources: registry, cache: databases.cache)`，可注入时钟和 AppLogger；测试也可直接注入记录 store。SourceRegistry 复制并固定注册关系，重复 SourceId 在装配时拒绝；描述信息与订阅均不触发 I/O。注册表和 Repository 不拥有 Source、transport 或数据库，composition root 必须先 `await repository.close()`，再关闭借入的资源。

close 取消查询和后台刷新，等待已开始的查询、读取、写入结束；已取消的晚结果不发布。通知流以数据事件表达预期失败，关闭流不等待已暂停的订阅恢复，订阅者仍须自行取消。Source 必须遵守取消契约和 NET-002 deadline；仓库不为不合作的 Source 制造无限重试或假完成。

## 读取行为

- discover / search 仅转发到指定 Source，查询字符串及 opaque cursor 原样传递。拒绝跨源 cursor，不支持发现返回 unsupported；Source 缺失返回 sourceUnavailable / sourceMissing。
- detail / catalog / chapter 校验返回身份后写入对应 SQLite 记录，保留完整复合 key。错误源或章的结果不会污染缓存。
- cacheOnly 只读本地：缺失返回 cacheMiss，损坏返回 invalidContent；不调用 Source、不刷新。
- cacheFirst 命中有效记录直接返回；已有 expiresAt 到期或 parserVersion 不兼容时先返回 stale，再启动一次去重刷新；未命中才请求 Source。
- refresh 等待远端；失败且存在旧记录时返回原 value / fetchedAt，加 stale 与 refreshFailure；无旧记录返回 Failure。取消不转成旧数据上的刷新错误。
- 远端成功后本地写失败仍返回可读的 remote 结果，AppLogger 只记录封闭失败字段；origin 不承诺持久化成功，后续 cacheOnly 仍以数据库实际内容为准。

当前只保留在途工作，不新增内容内存缓存。新记录 parserVersion=1、expiresAt=null，代表当前规范化解析基线且尚无 TTL；已有显式到期值按注入时钟判断。具体 Source parser 版本失效策略、TTL、容量及淘汰仍归 CACHE-001 / CACHE-002，不把本项当成完整缓存政策。

## 并发与通知

同一类型和完整 key 的远端读取合并成一个在途任务；每个前台调用者独立取消，最后一个前台退出且没有后台所有者时才取消源请求。stale 的后台刷新由仓库生命周期持有，不因触发它的页面取消而终止。取消的旧任务完全结束后才允许同 key 新任务进入，避免晚写覆盖新结果。

三个 updates 接口均为广播、无初始事件、订阅不读取数据库。实际刷新完成只发一次当前结果；取消结果不发失败事件。通知不承担媒体租约传递，也不实现缓存清理代次（清理接口尚未进入本项）。

## 验收

新增 13 项测试使用 in-memory Drift SQLite 与可控 fake Source，覆盖三个记录类型、发现 / 搜索、cacheOnly 零源调用、缺源本地读取、跨源 ID 隔离、响应身份错误、缓存损坏修复、写失败降级、过期刷新去重、取消隔离、旧请求晚到、通知和关闭时资源等待。

本轮不访问真实源，不执行 Android / iOS 运行验证。iOS Level A：共享 Dart 编排与既有 Drift 存储，没有 Flutter UI / 平台分支、新插件或最低系统变化；iOS runtime 仍 DEFERRED_NO_MAC。UI-002 的 MuMu 数据库打开失败与滚动恢复补验缺口保持原记录，离线 Repository 测试不替代它。

最终结果：新增 **13 项 PASS**，完整离线 Flutter 测试 **177 项 PASS**（本机 `.tooling/evidence/core005-tests.txt`）；全项目 analyze **No issues found**。本轮未构建或安装新 Android APK，现有模拟器仍为 UI-002 开发包。
