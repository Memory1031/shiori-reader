# 请求预算与诊断

请求作用域 BackgroundWork（Dart Zone 传递元数据，不是全局服务定位器）。进程所有者共享 BackgroundBudget，Source 定位 / 重定向 / 重试和流式响应体均记账。Scheduler 保存提交时 Zone，避免延迟执行继承其他请求上下文；共享后台资源遇前台消费者立即提升排队优先级，HTTP 单次大小 / deadline / 同源间隔保持不变。详见 [缓存](cache.md)。

Source 各自拥有 NetworkTransport / Dio，注入允许的 HTTPS URI 和私有 Header / 响应接收策略；自动 redirect 关闭。响应通过流逐块计数，解压后元数据最多 8 MiB、媒体最多 20 MiB；MIME 不符、声明 / 实际长度异常及超限均不返回成功正文。connect / send 10s，receive 默认 20s（媒体可指定 30s），绝对 deadline 覆盖等待响应及流读取。取消绑定 Dio abort 和响应订阅取消；没有重写 Domain 契约。

AppLogger 只接受类型化摘要字段，内存最多 200 条；Release 不保存成功请求明细。不接收 URL / body / Header / exception / 自由文本。opaque SourceId 用 SHA-256 标识，requestId 为本地随机 ID；取消不产生错误事件。Source 原始响应只留在 data 层，状态与 Dio 异常映射为既有 AppFailure。

依赖：精确锁定 Dio 5.11.1，官方 [包元数据](https://pub.dev/api/packages/dio/versions/5.11.1) 与本机下载包均声明 Dart >=2.18.0 <4.0.0，满足本项目 Dart 3.10.3；使用默认 IO adapter，未增移动平台插件、修改最低 OS 或放宽 TLS 校验。fake_async 1.3.3 从既有传递依赖提升为直接 dev 依赖。iOS TLS 运行边界见[验收摘要](validation/README.md)。

离线复验：`fvm flutter test --no-pub test/data/network --reporter expanded`。使用 FakeAdapter 和秘密哨兵检查字节 / MIME / 长度、超时、取消、错误映射与日志；未以 fake 宣称真实网站 HTTPS / 会话有效。

应用组装层拥有共享 RequestScheduler，每个 Source 的 NetworkClient 借用它与独立 transport。默认全局 2 在途、Source 2 在途、后台 1，Source 启动间隔 500ms、队列 20；前台等待时不启动新后台，满队列可取消尚未启动的后台为前台让位。取消 / 过期排队立即移除；已启动工作收到取消后仍占槽直到底层退出，不用逻辑完成伪造空闲连接。

逻辑 send 的队列、退避、最多一次额外 safe-read 重试及最多 5 次重定向共享 45s deadline。safeToRepeat 默认 false，包括 POST；仅 Source 有证据明确声明后才能自动重复。502 / 503 / 504、连接 / 超时可参与，其他状态不自动重试。429 在释放调度槽前冻结同 Source 排队请求，合法 Retry-After 按秒或 HTTP 日期处理，缺失 / 无效使用 60s；没有自动到期重放，需用户再次发起。

逐跳重新调用 Source policy；拒绝降级、未允许 URI、循环及超跳数。301 / 302 的 POST、303 非 HEAD 改 GET 并丢弃 body；307 / 308 保留方法。跨 origin 移除 Authorization / Cookie / Referer 以及自定义请求头，仅保留 representation 类头；有 body 的跨域 POST 保持型重定向拒绝。Cookie 接收钩子属于私有 Source，当前不引入 cookie_jar 或会话恢复策略；未来恢复调用仍须经过此 scheduler，并禁止叠加通用 retry。

时间测试使用 fake_async 与确定性 attempt 替身隔离 Dio 拦截器 Future 的时间域；另以真实 Dio + FakeAdapter 验证响应处理、取消和 redirect method / Header，不将二者混为真实 TLS 测试。

## 装配和所有权

应用组装者创建一份 RequestScheduler；每个 Source 创建 SourceNetworkPolicy、NetworkTransport，并把二者和同一 scheduler 注入 NetworkClient。Source 私有适配器构造 NetworkRequest，显式声明 MIME / 编码后的 body / 可重放性；UI 不使用这些 data 类型。owner 退出时关闭自己的 transport，应用退出时关闭 scheduler；NetworkClient 不擅自关闭借用对象。后续 Source 初始化 / 恢复应沿用同一个绝对 deadline，并以 safeToRepeat=false 禁止恢复与通用 retry 叠加。当前 Source 使用无会话分支，不自动恢复登录。

Transport.attempt 是内部“单次 HTTP 尝试”边界：3xx / 4xx / 5xx 可作为 NetworkResponse 交给 NetworkClient 处理，不是业务成功；业务读取应使用 client.send，由它处理 redirect / 429 / retry / status failure。响应 Header 含敏感数据，仅供 Source 私有策略，不传入 Domain 或 Logger。每次连接在响应流读取期间持有调度槽；当前按上限缓冲完整 bytes，未实现跨层零拷贝流。调用取消会立即 abort，原始 adapter 清理异常不会透出。


## Source 收紧规则

NetworkRequest.maxRedirects 为 0..5，Source 可以收紧。当前 LightNovel JSON API 设为 0，POST 不自动重放、不恢复未经确认的会话。网络替身测试不等于真实 TLS 或实时书源可用性，证据见[验收摘要](validation/README.md)。
