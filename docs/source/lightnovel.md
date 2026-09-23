# 在线书源维护

当前生产 Source ID 为 `lightnovel`，实现位于 `lib/data/sources/lightnovel/`；站点协议只存在 data 层，应用自有 UI 使用中性「在线书源」文案。没有发现 / 推荐入口。

## 访问与证据边界

协议来自 2026-09-06 / 07 的正常页面观察、显式授权的直接 HTTP 样本与生产适配验证；**不是当前实时可用性保证**。普通样本当时未主动携带登录凭据，不意味着所有内容可匿名访问或已获再分发许可。

遇登录、付费、验证码、WAF 或明确拒绝，停止该路径并保留类型化失败，不猜测备用端点或绕过限制。真实请求需每次明确授权和预算，默认开发 / CI 使用离线样本。内容与品牌许可未确认，见[发布说明](../release/README.md)。

## 当前协议

前缀 `https://www.lightnovel.fun/api/pc-proxy`，以下均追加完整路径、POST JSON；成功样本为 HTTP 200、JSON `code=0`，业务值在 data。

| 操作 | 路径与规则 |
| --- | --- |
| 搜索 | `/api/bff/apk-search-result-v1`；q、page、pageSize=20、sort=relevance 和样本中的 filter；请求 page 从 0，响应 pagination.page 从 1 |
| 详情 | `/api/new-content-read/get-book-detail`；book_id、with_volumes=0 |
| 卷列表 | `/api/new-content-read/get-book-volumes`；book_id，page 从 1、pageSize=50 |
| 卷内章节 | `/api/new-content-read/get-volume-chapters`；book_id、volume_id，page 从 1、pageSize=50 |
| 正文 | `/api/new-content-read/get-chapter-detail`；book_id、chapter_id，只使用 body_snapshot |

请求借用全局 scheduler，禁止 redirect（maxRedirects=0），safeToRepeat=false，不自动重放 POST。401 / 403 映射 accessRestricted，429 服从同源冷却。未确认非零业务 code 不猜登录失效；错误 envelope、身份或类型返回封闭诊断，不暴露服务端 message。

## 搜索、目录与正文

游标是实例内不透明句柄，绑定正规化查询、下一页与已见 ID；最多 32 条续页状态、每链最多 5000 ID。不跨进程保存，重复消费、伪造、查询不匹配或已淘汰游标在请求前拒绝；失败 / 取消不消费有效游标，供显式重试。跨页重复 ID、重放页返回 repeatedPage，空页终止。

目录保留源顺序，聚合卷和章节后一次提交完整快照，不按 ID / 标题反转或推断续篇。聚合共享 45 秒 deadline，最多 100 次逻辑请求 / 5000 章；超限明确失败，不返回半份目录或自动续传。合成无卷和真实缺名卷分开表达。

正文只读取 body_snapshot：优先非空 body_html，缺失 / 空白时可用 snapshot.body_text。**render_preview 不能回退成全文**；即使某次样本长度相同，也不能推广为所有章节完整。锁定、登录表单、缺 snapshot 或无可读块均不冒充正文。段落 / 标题 / 图片顺序保留，常见 Ruby 保留为基字与结构化注音，复杂嵌套等写法降级为括注，原生不支持的装饰不进入领域。

## 媒体身份与重新定位

MediaRef 保存无 secret 的 locator，不持久化当次 URL、m/t、Header 或浏览器会话。cover:v1 从详情重新取得封面；image:v1 从所属章节 body_snapshot 按 origin + path 摘要重新匹配。缺失 / 冲突 / 锁定 / preview-only 明确失败，不猜签名、不盲试 host。

正文中的单张图片缺失地址、URI 格式错误或不符合媒体地址规则时，保留图片位置、alt / caption 和前后正文，使用 `unavailable:v1` 源内占位引用；该引用在媒体入口直接失败，不请求网络、不持久化异常 URL。媒体重新定位时跳过无效候选，仍校验目标身份及重复 locator 冲突，不让无关坏图阻断正常图。正文身份、锁定与 snapshot 校验仍作用于整章，不通过全局 catch 放过访问限制。

图片（包括封面）允许 HTTPS 的 lightnovel.fun 根域与以 .lightnovel.fun 结尾的子域，仍禁止非 443 端口、用户凭据与 fragment；API 仍只允许既定端点，重定向仍禁用。元数据与图片共用 45 秒 deadline。图片最多 20MiB 且服从调用方更小限制，接收超时 30 秒，限定已支持 MIME；MIME 通过不是图片解码通过，解码与 lease 见[缓存](../architecture.md)。

## 维护与复现

先用最小脱敏样本定位是网络、envelope、身份、分页、正文还是媒体问题，再更新解析和回归。测试样本保留结构、来源说明与 SHA-256，禁止提交整章版权内容、完整签名 URL、Cookie 或账号数据；LF 是哈希契约的一部分。

- [样本清单](../../test/fixtures/lightnovel/README.md)：原始结构与派生样本边界。
- [独立调查工具](../../tools/source_probe/README.md)：默认离线、显式 live 及预算。
- [生产在线探针](../../integration_test/live/README.md)：设备单次执行与请求计数。
- [网络约束](../architecture.md)：并发、重试、冷却与日志白名单。

第三方 `gholts/aidoku-source` 曾作为协议线索，不是运行依赖，也不替代直接证据；不沿用其 preview 回退等未经确认策略。

## 已有在线证据

2026-09-07 独立调查两轮合计 12 / 30 次 HTTP 尝试，图文链路成功；后续生产媒体跨两个 Windows Flutter test 进程重新定位并解码，共 10 / 10 次。Android MuMu 生产 Source HTTPS smoke 使用 10 / 12 次，无重试。请求均属于当次授权，不授权未来自动重跑。

历史媒体调查结果查 Git。Android ARM64 的合成适配器 / 离线恢复测试另计，不能据此声称最新设备上的真实站点链路已验证。访问异常 schema、长期 locator 稳定性和未来服务可用性仍以新证据为准。
