# NET-001 / NET-002：受限网络与诊断

2026-09-07。NET-001 / NET-002 DONE；网络层合计 14 项离线测试通过，完整工程 112 项通过，静态分析无问题；Android 组合探针安装 / 冷启动 / 执行通过。没有访问真实 Source。MEDIA-001 的所有权与内存边界见 [媒体说明](media.md)。

NET-001：Source 各自拥有 NetworkTransport / Dio，注入允许的 HTTPS URI 和私有 Header / 响应接收策略；自动 redirect 关闭。响应通过流逐块计数，解压后元数据最多 8 MiB、媒体最多 20 MiB；MIME 不符、声明 / 实际长度异常及超限均不返回成功正文。connect / send 10s，receive 默认 20s（媒体可指定 30s），绝对 deadline 覆盖等待响应及流读取。取消绑定 Dio abort 和响应订阅取消；没有重写 Domain 契约。

AppLogger 只接受类型化摘要字段，内存最多 200 条；Release 不保存成功请求明细。不接收 URL / body / Header / exception / 自由文本。opaque SourceId 用 SHA-256 标识，requestId 为本地随机 ID；取消不产生错误事件。Source 原始响应只留在 data 层，状态与 Dio 异常映射为既有 AppFailure。

依赖：精确锁定 Dio 5.11.1，官方 [包元数据](https://pub.dev/api/packages/dio/versions/5.11.1) 与本机下载包均声明 Dart >=2.18.0 <4.0.0，满足本项目 Dart 3.10.3；使用默认 IO adapter，未增移动平台插件、修改最低 OS 或放宽 TLS 校验。fake_async 1.3.3 从既有传递依赖提升为直接 dev 依赖。iOS TLS runtime 仍归 IOS-002，文档与源码兼容不代表真机验证。

离线复验：`flutter test --no-pub test/data/network --reporter expanded`。NET-001 用 FakeAdapter 和秘密哨兵检查字节 / MIME / 长度、超时、取消、错误映射与日志；未以 fake 宣称真实网站 HTTPS / 会话有效。

NET-002：应用组装层拥有共享 RequestScheduler，每个 Source 的 NetworkClient 借用它与独立 transport。默认全局 2 在途、Source 2 在途、后台 1，Source 启动间隔 500ms、队列 20；前台等待时不启动新后台，满队列可取消尚未启动的后台为前台让位。取消 / 过期排队立即移除；已启动工作收到取消后仍占槽直到底层退出，不用逻辑完成伪造空闲连接。

逻辑 send 的队列、退避、最多一次额外 safe-read 重试及最多 5 次重定向共享 45s deadline。safeToRepeat 默认 false，包括 POST；仅 Source 有证据明确声明后才能自动重复。502 / 503 / 504、连接 / 超时可参与，其他状态不自动重试。429 在释放调度槽前冻结同 Source 排队请求，合法 Retry-After 按秒或 HTTP 日期处理，缺失 / 无效使用 60s；没有自动到期重放，需用户再次发起。

逐跳重新调用 Source policy；拒绝降级、未允许 URI、循环及超跳数。301 / 302 的 POST、303 非 HEAD 改 GET 并丢弃 body；307 / 308 保留方法。跨 origin 移除 Authorization / Cookie / Referer 以及自定义请求头，仅保留 representation 类头；有 body 的跨域 POST 保持型重定向拒绝。Cookie 接收钩子属于私有 Source，当前不引入 cookie_jar 或会话恢复策略；未来恢复调用仍须经过此 scheduler，并禁止叠加通用 retry。

时间测试使用 fake_async 与确定性 attempt 替身隔离 Dio 拦截器 Future 的时间域；另以真实 Dio + FakeAdapter 验证响应处理、取消和 redirect method / Header，不将二者混为真实 TLS 测试。

## 装配和所有权

应用组装者创建一份 RequestScheduler；每个 Source 创建 SourceNetworkPolicy、NetworkTransport，并把二者和同一 scheduler 注入 NetworkClient。Source 私有适配器构造 NetworkRequest，显式声明 MIME / 编码后的 body / 可重放性；UI 不使用这些 data 类型。owner 退出时关闭自己的 transport，应用退出时关闭 scheduler；NetworkClient 不擅自关闭借用对象。后续 Source 初始化 / 恢复应沿用同一个绝对 deadline，并以 safeToRepeat=false 禁止恢复与通用 retry 叠加。本轮没有 Cookie / Source session 实现。

Transport.attempt 是内部“单次 HTTP 尝试”边界：3xx / 4xx / 5xx 可作为 NetworkResponse 交给 NetworkClient 处理，不是业务成功；业务读取应使用 client.send，由它处理 redirect / 429 / retry / status failure。响应 Header 含敏感数据，仅供 Source 私有策略，不传入 Domain 或 Logger。每次连接在响应流读取期间持有调度槽；当前按上限缓冲完整 bytes，未实现跨层零拷贝流。调用取消会立即 abort，原始 adapter 清理异常不会透出。

## 最终验收

- 新增 14 项网络测试：秘密哨兵、Release 日志与环形容量、MIME / bytes / 声明长度、stalled adapter 截止 / 流取消、status 映射；并发 / 源间隔 / 后台上限 / 前台优先 / 队列挤出 / 过期、重试次数与 jitter、429 同源跨 host 冷却、重定向方法 / Header / body / 环路 / 5 跳预算、总 deadline。使用保守项目预算，不宣称这些是站点限流事实。
- MuMu `127.0.0.1:16384`：`test/support/network_media_probe.dart` APK 安装 Success、COLD 启动 Status ok。实际日志 `NETWORK_MEDIA_PASS attempts=2 sharedLeases=2 retainedBytes=0 codec=64x64`，截图确认 PASS 和自制棋盘 PNG。这个探针组合真实 Dio 处理链与 fake adapter、共享 scheduler、SourceMedia 测试桥和正式 MemoryImageRepository；证明 Android 执行 / 解码，未发出外部 HTTP 请求。
- 完整 112 项测试、静态分析、Debug 构建通过。MuMu 不代替 ARM64 真机性能和真实 TLS；线上限流、会话、站点协议在 SRC / TEST / ANDROID 后续任务验证。iOS Level A：默认 IO adapter、Dart HttpDate、无 Native 插件 / 平台分支 / OS 下限变化；TLS / CocoaPods 最终链接 / iPhone runtime 仍 DEFERRED_NO_MAC。

非 2xx 响应只接收状态与 Header，关闭错误正文；已覆盖 429 超大且停滞正文，确保不绕过冷却。最后增补该回归后完整测试为 112 项。

最终版本组合探针已再次安装 / 冷启动并输出同一 PASS。随后恢复已验证的 typography 常规开发包到 MuMu；普通 `lib/main.dart` 最终 APK 构建通过（4.4s），未覆盖安装。探针包保留在忽略的 `build/app/outputs/flutter-apk/network-media-probe-debug.apk`，普通包为 `app-debug.apk`。

SRC-005：NetworkRequest 新增 maxRedirects（0..5，默认5），Source 可收紧但不能扩大 NET-002 上限；LightNovel JSON API 设为0，同域跳转也停止。该源 POST 不自动重放、不恢复未确认会话，仍借用全局 scheduler / deadline。新增源测试与既有网络回归通过，完整187项测试 PASS；本轮没有 Android 或真实源请求验证。
