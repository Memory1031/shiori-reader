# CACHE-001..005：缓存与预取实施记录

2026-09-07。五项功能已实现，310 项完整离线回归通过。**CACHE-004 的 ARM64 真机验收仍待设备；iOS runtime 保持 DEFERRED_NO_MAC。** MuMu 结果不替代真机验收。本轮没有生产 Source 请求，也没有执行 LOCAL 或整书下载。

## 产品行为

首页更多菜单 →「缓存与离线阅读」展示正文 / 图片容量、书名、文章和有效图片数量。点击文章强制 cacheOnly，缺目录仍能读正文；图片重试也不联网。按书或全部清理有确认，保留书架、阅读进度、偏好及后续目标。

阅读器更多菜单 →「阅读缓存」提供当前图片 / 后续文章两个开关、暂停、继续 / 重试和「接下来阅读」。候选保留源分组及完整标题，用户只选择一篇；更换 / 取消不切章、不改变阅读进度。当前 Source 没有可靠续篇关系，不按 ordinal 推断下一卷，也不递归整个系列。

## 策略

| 对象 | 已实现策略 |
| --- | --- |
| 详情 / 目录 | 24h / 1h TTL，cacheFirst 先本地后刷新 stale；v1 空 expires_at 按 fetched_at 应用 TTL |
| 正文 | 无硬 TTL，显式刷新；当前 Reader 快照不被后台替换 |
| 正文 / 元数据 | 64 MiB payload LRU，超额回收至 80%，当前正文 pin；用户库不参与 |
| 图片文件 | 192 MiB payload LRU，独立活动租约保护；预取最多保留 5 个近邻文件租约 |
| 后台批次 | 应用进程内共享 64 MiB 响应体 / 200 HTTP 尝试，切章和前后台切换不重置 |
| HTTP | 复用全局 2 / 后台 1 / 同源 500ms，定位、重定向、重试都记账；共享任务可前台提升 |
| 解码 | 近邻页挂载、单图最多 400 万像素；Reader 串行解码，LRU 最多 5 项 / 24 MiB，独立 ui.Image clone，离开释放 |

预算不等于物理 DB / RAM / 总磁盘大小。活动租约可暂缓回收，释放后维护。后台图片写入将超额时暂停，防止淘汰后循环重下。每批记录已尝试项；普通失败继续其他图，429 / 权限 / 会话错误停止，用户明确继续才重开额度。网络额度触发后的已接收越界 chunk 不进入有效响应，也不继续后续尝试。

当前文章 ready 后先准备接下来 4 张及前 1 张，再准备其余图片；然后才处理一篇选定目标正文及图片。目标存在用户库，与进度分开；目录到达后验证存在性，失效则取消。后台、离开 Reader、改选、清理均取消旧消费者，不取消仍有前台消费者的共享请求。

正文复用已有 in-flight 合并和页面活动快照，没有新增无界正文内存缓存。last_access 至多每键每分钟写一次；辅助更新失败不隐藏可读正文。图片仍复用既有有界编码内存层，整卷落盘不等于整卷解码入 RAM。

## 文件和清理

PersistentImageRepository 装饰已有 MemoryImageRepository，复用 SourceMedia / HTTP / MIME / 单资源 20 MiB 限制。文件身份由稳定 MediaRef 与内容 checksum 构成，索引保存相对文件名、稳定引用、长度、类型和时间；image_owners 记录书籍归属，不保存临时 URL / Cookie / token。

生产装配校验尺寸和首帧后，写同文件系统 staging、flush、原子 rename，再发布索引。刷新不覆盖活动旧版本。读取检查路径、长度、checksum；损坏 / 缺失只失效本项，损坏闲置文件允许重新获取后修复。写入失败返回 memoryOnly + persistenceFailure，不计入有效离线数量，预取暂停。

维护每批最多扫描 128 项，保留游标继续清理 staging / 无索引文件；启动及租约释放后执行。clear 同步递增 generation，取消小说刷新 / 预取、清空编码图片内存查找，再串行删记录和索引；旧回调不能回填。活动图租约 close 前有效，新读取立即看到缺失。跨书共享图保留其他所有者，不操作用户库。

OQ-09 技术选择关闭：采用既有媒体协议上的有限持久装饰层，不增加缓存依赖。沿用 TASK_PLAN 包备选评估；通用包仍需适配稳定引用、共享调度、额度、租约与 generation，当前替换不足以减少边界代码。保持 ImageRepository 可替换，不把未实测包或平台描述为已验证。

## 验证证据

- 最终 `flutter analyze --no-pub` 无问题；正常入口 `lib/main.dart` Android debug APK 构建成功并 `adb install -r` 安装到 MuMu，保留应用数据。SHA-256：`B48F6D82180C88F00A474AF1A0505C42065FA1E79E67CCD4E6773741E4BD061C`。安装后未主动启动生产书源验证；探针仅在独立开发数据目录运行。

- 310 项离线回归：TTL、LRU/pin、清理晚写、文件重开、checksum 修复、缺失、并发租约、非法路径、提交失败、无效图、超过 128 项孤儿、跨书共享、两库 v1→v2；目标恢复 / 移除、禁止 ordinal 推断、关闭 / 暂停 / 清理 / 重试、额度、近邻、429、失败无循环、HTTP 字节及排队提升；中英文数量、离线点击、清理确认。
- `integration_test/cache_smoke.dart`：独立 phase6-cache-probe 开发目录，自制 PNG / 文字。MuMu API 32 保存 19/20 图，第 20 张 cacheOnly miss；冷进程 registry 为空、Source 调用为 0，真正 BookReaderScreen 的 RawImage 挂载解码图片。
- 首轮 `CACHE_PREPARED_19_OF_20_PASS` / `CACHE_READER_IMAGE_MOUNT_PASS`。飞行模式值为 1 时 PID 16805、16968 均报告 `CACHE_COLD_19_OF_20_ZERO_SOURCE_PASS` / `CACHE_COLD_READER_IMAGE_MOUNT_PASS`；测试后恢复原值 0。截图 `.tooling/cache-phase6.png` 不入版本控制。
- 不代表生产 Source 新验收、ARM64 手机、profile 性能或 iOS runtime 通过。ARM64 从书架 / 最近阅读冷启动和真实磁盘压力待设备补测；iOS 文件备份排除与运行验收留 IOS-005。
- 整书 / 系列下载保持 BACKLOG；当前是可淘汰的阅读预取，无下载中心、永久离线保留或平台后台服务。
