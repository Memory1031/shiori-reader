# MEDIA-001：最小内存 ImageRepository

CACHE-003（2026-09-07）现已增强生产组合：PersistentImageRepository 装饰本页内存实现，使用有界托管文件和独立租约，失败降级仍遵守原接口。Reader 使用有界解码 LRU，整卷预取只下载编码图，不整卷解码。下文“只在内存”描述 MEDIA-001 基线；当前持久策略、路径 / quota / clear 与 Android 冷进程证据见 [缓存](cache.md)。

2026-09-07，MEDIA-001 DONE。6 项媒体所有权 / 限额测试 + 1 项网络到 codec 组合测试通过；与 NET-001 / 002 一起，完整测试 112 项、静态分析、Android Debug 构建和 MuMu 组合探针通过。iOS Level A PASS，runtime DEFERRED_NO_MAC。

## 使用与资源所有权

`MemoryImageRepository(resolve: sourceMediaResolver)` 实现既有 ImageRepository，resolver 按 SourceId 返回借用的 SourceMedia。源的 URL、Header、session 和重定向不进入仓库；真实 SourceMedia 必须使用共享 NetworkClient / RequestScheduler，不能按图片 host 新建调度预算。本轮没有生产 Source 或应用全局注册；后续 READER-003 通过构造器注入本仓库。组合测试的 ProbeMediaSource 仅是测试桥，不是生产 Source。

相同 MediaRef 的 pending load 合并，每位消费者得到独立 MediaLease；取消只移除本人，最后一位退出才取消底层 SourceMedia。所有路径关闭获得的 body，包括未订阅、流失败、超限、超时、晚到 body 和仓库销毁。仓库借用的 SourceMedia 不由它关闭。调用方在替换图片 / dispose 时关闭自己的 lease；已关闭 lease 不应继续持有。仓库 close 取消进行中 / 排队工作，既有 lease 仍可读并由各自 owner 释放。

只有尚有租约的图片保留在 RAM，最后租约关闭就清除该版本。cacheOnly 只命中已有内存，不调用 resolver / Source；miss 返回 cacheMiss。cacheFirst 命中仍在用的图，否则发起读取；refresh 显式重新读取，同一 key 的刷新合并。刷新失败若旧图还在，返回新的独立旧图 lease，标记 stale / refreshFailure；后续命中继续带此观察，成功刷新才换新版本。旧版本的已有 lease 不被新版本释放或改写。

结果始终为 MemoryMedia / memoryOnly / persistenceFailure=null：没有尝试写盘，不代表写盘成功，没有 LocalMedia、TTL、磁盘 LRU、清理服务或离线重启承诺。CACHE-003 以后可增强同一接口。

## 限额与格式

默认单图编码数据最多 20 MiB，同时最多读取 2 项、pending key 最多 20；每项含排队的 deadline 45s。默认 64 MiB 是仓库保留的**编码数据及进行中读取预留额度**，不是进程总内存或解码预算；收集 / 只读复制和 transport 缓冲会暂时产生额外的有界副本。额度不足时等待 lease 释放，超时结束；不无限增长，也不强行释放别人的图片。

SourceMedia 的 MediaFormat 作为 MIME 边界信息，再校验 PNG / JPEG / GIF / WebP / AVIF 文件标记、实际累计长度和声明长度；unknown、空数据、不符或超限失败，不把截断内容作为成功图片。标记检查不等于完整图像合法性或像素预算验证；READER-003 负责正式 Flutter codec、目标解码尺寸、动态图策略和失败占位。本次仅用自制 64×64 PNG 通过实际 codec 验证组合路径。

## 证据与复验

```powershell
flutter test --no-pub test/data --reporter expanded
flutter run --target test/support/network_media_probe.dart -d 127.0.0.1:16384
```

测试覆盖共享进行中请求、独立租约、cacheOnly 零 Source、单消费者 / 最后消费者取消、迟到 body 关闭、未知格式 / 空数据 / 长度 / 超限 / terminal Failure / raw error、旧图刷新失败保留、RAM 预算 / 有界队列、Source 永不返回时截止和仓库销毁。组合测试用真实 Dio + fake adapter 模拟一次 503 后成功，证明仅两次尝试、共享媒体、codec 成功及引用归零。

MuMu 新包日志：`NETWORK_MEDIA_PASS attempts=2 sharedLeases=2 retainedBytes=0 codec=64x64`；截图在忽略目录 `.tooling/evidence/network-media.png`。没有访问小说网站，未宣称全部图片格式 / 大图 / ARM64 性能已经实测。Android 运行不等于 iOS 运行；iOS 的 ImageCodec / 内存 / 退出路径仍归 IOS-004。

READER-003 已将本仓库接入正式 Reader 的 SourceImage，按宽度 × DPR 与 400 万像素限制解码，并在卸载时释放引用。详见 [Reader 图片验收](reader.md)。未知尺寸重排或切换模式可能重新挂载并重新获取媒体；本轮没有增加常驻图片缓存或离线持久化。

## 近期图片复用（2026-09-07，用户反馈追加）

MemoryImageRepository 新增可选 maxIdleBytes，默认 0 保持旧租约即释放行为；生产 SourceServices 配置 **32 MiB 编码图片闲置 LRU**，与活动租约、进行中读取预留共用原 **64 MiB 总预算**。最后租约关闭后，当前版本可留在闲置队列；cacheOnly/cacheFirst 命中重新取得独立租约并提升最近使用位置。压力下先淘汰无人持有的旧图，不回收活动租约；refresh 替换时清除旧闲置版本，close 释放所有闲置数据。

SourceImage 的转圈指示延后 180ms，只在请求仍进行时显示，避免快速内存命中时闪过转圈。已有图在同一挂载实例的重新解码期间继续显示；切换视口后的重新挂载仍可能出现短暂占位。本轮不缓存 Flutter 解码图，不预取整章图片，不增加并发或请求重试。

新增 LRU 测试验证近期复用零新增 Source 请求、淘汰顺序、活动租约不可淘汰及 close 后独立释放。完整回归 276 PASS。该缓存仅驻留当前进程，不是磁盘缓存，不保证首次网络加载更快，不保证跨进程 / 重启离线。持久图片及配额、原子落盘仍由 CACHE-003 实施。
