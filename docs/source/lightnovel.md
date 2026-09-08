# LightNovel.fun 源站调查

> iOS 状态更新（2026-09-08）：Mac / Simulator 已可用，当前证据见 [IOS-001 报告](../validation/ios-001.md)。本次未由代理执行 iOS 真实 Source 请求，历史 Windows / Android Source 证据不外推为 iOS 通过。下方带日期的 `DEFERRED_NO_MAC` 等结论是当次历史记录，不代表当前环境。

当前结果（2026-09-07）：**SRC-001..004 DONE；Phase 0 技术可行性 Gate = GO / PASS，可按依赖进入生产接入开发。** 这不表示生产 Source 已实现、媒体跨重启已验证或已获内容分发许可。前文保留历史快照；其中 UNKNOWN / 未执行和 SRC-003 报告的 NOT_EVALUATED_SRC004 均指当时状态，以文末 SRC-004 的结论、责任与后续门槛为准。

## SRC-001：访问边界与调查基线

- 状态：**DONE — 2026-09-06**，仅完成访问基线；SRC-002..004 未执行，生产 Source 可行性 Gate 尚未通过。
- 结论：在显示“登入/注册”的普通浏览器会话中，起始首页可达并展示内容。SRC-002 可以从该访客首页的正常 UI 入口开展有限调查；搜索、详情、目录、正文、插图请求及权限仍为 UNKNOWN。
- 本报告只证明 Windows 浏览器当次观察，不证明 Dart、Android 或 iOS 网络与运行行为。

### 环境与观察方法

| 项目 | 本次记录 |
| --- | --- |
| 日期 / 时间窗口 | 2026-09-06 23:15–23:18，Asia/Shanghai（UTC+08:00）；宿主时钟读取为 23:16:21、23:17:35 |
| 宿主 | Windows NT 10.0.26200.0；项目位于 Windows PC |
| 起始 URL | <https://www.lightnovel.fun/> |
| 第一会话 | Chrome，普通新任务标签；截图发现已有账号状态，不能作为匿名证据 |
| 有效访客会话 | 独立的应用内 Chromium 浏览器标签；首页明确显示“登入/注册”，没有进行登录或导入 Chrome 会话 |
| 浏览器精确版本 | UNKNOWN；本次工具只报告浏览器名称，未读取版本页 |
| 证据载体 | 本次工具返回的可访问性树、DOM 快照、当前 URL、Chrome 页面截图；下表是脱敏后的人工观察记录 |
| 网络层边界 | 未抓取 Network / HAR，未读取 Cookie、localStorage、token 或完整请求头；不能由访客 UI 推断零 Cookie / 零匿名 session |

本次只进行了 2 次顶层页面打开（同一起点，不同会话）和 4 次单次点击（Chrome 个人中心、访客会话三个页脚规则文字）。没有提交搜索、打开书籍、滚动加载更多或请求猜测端点；没有失败重试。页面自行加载的脚本、图片和数据请求未计数，因此 **6 次页面操作不是 6 次 HTTP 请求**，也不表示浏览器满足 App 的并发与请求间隔控制。

后续 SRC-001 复核预算：最多 6 次串行导航 / 点击，人工动作间隔至少 1 秒；不循环刷新、不预取、不打开多本书。若需要严格 HTTP 尝试计数，应在具备 Network 计数能力的 SRC-002 先记录加载基线，再开展调查；SRC-003 另执行计划中的 30 次总 HTTP 尝试硬预算。当前没有可验证的站点速率限制，不能把项目自设预算说成站点许可。

### 观察证据

全部条目观察日期为 **2026-09-06**，时间处于上表窗口；序号表示操作顺序，不是假设的 HTTP 顺序。

| Evidence | 操作 / 页面 | 直接观察 | 可支持的结论与限制 |
| --- | --- | --- | --- |
| E01 | Chrome 打开起始 URL | 最终地址仍为 `https://www.lightnovel.fun/`；标题为“轻之国度-专注分享的NACG社群”；有搜索框、好书推荐、书籍卡片、频道导航及页脚 | 该会话首页可达；不能仅凭首页可见宣称匿名可达 |
| E02 | Chrome 点击页面现有“个人中心”入口一次 | 地址仍停留首页；随后截图可见已有账号状态 | 此会话受已有登录状态影响，从匿名证据中排除；未进一步进入个人资料，未退出账号或修改用户会话；不把点击无变化解释为权限拒绝 |
| E03 | 独立应用内浏览器正常打开起始 URL | 最终地址仍为 `https://www.lightnovel.fun/`；同一页面标题；用户操作区明确显示“登入/注册”；首页有“好书推荐”、热门 / 最近更新选项、书籍卡片、搜索框 | **访客 UI 状态下首页可见**；没有看到强制登录、付费、验证码、WAF 或访问拒绝提示；不代表所有页面都可匿名读 |
| E04 | 读取 E03 首页页脚 DOM | “隐私政策”“分级规定”“LK站规”均为 `span`，自身及直接父元素无 `href`；页脚有版权保留文字 | 这些文字存在；没有据此获得政策正文或可跟随的说明 URL |
| E05 | 在 E03 会话依次单击“LK站规”“隐私政策”“分级规定”，各一次 | 每次点击后当前地址仍为首页，DOM 快照没有展示规则正文或对话框 | 通过所见入口未取得公开规则内容；不据此断言站点没有规则，也不猜测备用 URL |

页面标题是站点自称，未核验其主体归属。地址栏起止相同只说明最终落点；**中间 HTTP 重定向链、响应状态码及缓存来源仍 UNKNOWN**，不可写成“HTTP 200 / 无重定向”。原始 Chrome 截图含已有账号信息，未复制到仓库；本文不保留账号名、消息状态、Cookie、完整 HTML、小说正文或插图资产。

### 已知 / UNKNOWN 矩阵

| 问题 | 当前状态 | 证据 / 下一责任 Task |
| --- | --- | --- |
| 正常浏览器起始地址和最终可见落点 | OBSERVED：均为 `https://www.lightnovel.fun/` | E01 / E03；HTTP 层有效 Base URL 由 SRC-002 核实 |
| 首页访客可见性 | OBSERVED：显示登入入口的会话可见首页内容 | E03；不是受保护内容的授权证明 |
| 首页展示能力 | OBSERVED：推荐区、书籍卡片、搜索入口、分类、热门 / 最近更新选项可见 | E03；未操作这些功能，数据接口、排序及分页语义归 SRC-002 |
| 搜索 → 详情 → 目录 → 正文 → 插图 | UNKNOWN | 未执行；SRC-002 正常 UI 逐步观察，SRC-003 验证自动化可行性 |
| 公开访问说明 / 站规 / 分级 / 隐私正文 | UNKNOWN：入口文字存在，点击未展示正文 | E04 / E05；SRC-002 若发现正常公开说明链接，再读取并记录 |
| 内容使用、fixture 保存和再分发许可 | UNKNOWN | 首页可读及版权文字不能关闭许可问题；后续采样前评估，发布归 RELEASE-001 |
| Cookie / token / security_key 的必要性和生命周期 | UNKNOWN | 未读取会话秘密；登入按钮不等于无匿名 Cookie，SRC-002..005 |
| HTTP 方法、端点、响应结构、ID、Header、图片 host / Referer | UNKNOWN | 未做 Network 观察；SRC-002，不照抄历史第三方资料 |
| 实际速率限制、WAF、失败码与全站匿名边界 | UNKNOWN | 本次首页未看到拦截不证明站点不存在限制；SRC-002 仅记录自然出现的现象 |
| Android / iOS App 可用性 | NOT_RUNTIME_VERIFIED | 本轮无 App 网络实现；Android 后续 TEST-001，iOS IOS-002 / DEFERRED_NO_MAC |

### SRC-002 的可继续范围与停止条件

可以从显示“登入/注册”的访客首页开始，先观察一次页面加载的 Network 基线，再通过页面提供的搜索框显式提交计划中的查询，沿正常返回的书籍、目录、章节与插图入口逐步调查。只采集实现所需的最小脱敏证据，并先确认样本使用边界；不默认复制全文或完整 HAR。每个阶段都要重新确认访客状态和可读边界，不能把前一页的可达性外推。

| 路径 / 条件 | 后续行为 |
| --- | --- |
| 本次已观察的访客首页入口 | 允许作为 SRC-002 调查起点；这不是 SRC-004 的生产接入 Go |
| 既有 Chrome 登录会话、个人中心、消息、收藏、发帖、登录 / 注册 | 不用于匿名链路；不借用用户凭据或访问账号内容；这些功能不属于 Shiori MVP |
| 路径要求登录、收费、验证码、WAF 或明确拒绝 | 当场停止该路径，记录 URL、日期、非敏感提示及受阻 operation；不重试绕过或寻找替代受限入口 |
| 公开说明入口无内容或无法确认许可 | 保留 UNKNOWN，不伪造“无禁止条款”或“已获授权”；受影响的样本保存 / 分发留待证据确认 |
| 无正常访客方式取得正文或插图 | 记录 SRC-002 下游阻断；不加入账号实现、Android WebView、隐藏端点或历史镜像作为绕过方案 |

### SRC-001 验收

- [x] 记录日期、宿主、会话差异、起止 URL、访问证据及预算计数边界。
- [x] 排除已有登录会话的匿名性结论；访客首页证据来自明确显示登入入口的独立会话。
- [x] 检查所见公开规则入口，未获得的说明保持 UNKNOWN。
- [x] 给出可继续调查范围与遇限制必须停止的规则；本次未发现需绕过的首页限制。
- [x] 没有业务实现、真实 fixture、API 猜测或伪通过测试；SRC-002..004 保持未执行。

复核方式：重读本次浏览器工具记录并与 E01..E05 对照，检查文档未保存账号标识、会话秘密、小说正文及图片。没有为文档添加自动化测试，也没有为验收重复请求源站。

## 第三方实现参考：gholts/aidoku-source

查阅日期：**2026-09-06**；用户指定参考。状态为 **REFERENCE_CODE_OBSERVED / LIVE_UNVERIFIED**。这次只读 GitHub 源码与元数据，没有运行 Rust / WASM、安装源包或请求下列小说站 API；不改变 SRC-002..004 未执行及生产 Gate 未通过的状态。

固定版本：[`fb9d3997f4a40450ede38b560af8311e387fc38e`](https://github.com/gholts/aidoku-source/commit/fb9d3997f4a40450ede38b560af8311e387fc38e)，提交日期 2026-08-24 13:35:10 UTC。核心文件为 [`sources/zh.lightnovelfun/src/lib.rs`](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/sources/zh.lightnovelfun/src/lib.rs)。[源清单](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/sources/zh.lightnovelfun/res/source.json) 声明源 ID `zh.lightnovelfun`、源版本 2、最低 Aidoku 0.8.3；这不是 Shiori 的依赖或兼容证明。

### 候选请求流程（仅代码线索）

实现中的公共前缀为 `https://www.lightnovel.fun/api/pc-proxy`，以下路径均拼接到该前缀，使用 POST JSON。不能把路径中的 `/api/` 省略，也不能在未确认正常网页行为前直接调用它们。

| Operation | 实现使用的路径后缀 | 实现中的输入 / 行为；SRC-002 核查点 |
| --- | --- | --- |
| 首页 / 空查询 | `/api/bff/home-feed-v1` | page 至少 1，同时传 `page_size` 与 `pageSize` 为 20，以及三个 `all` filter；核查字段必要性与首页能力 |
| 搜索 | `/api/bff/apk-search-result-v1` | `q`、`pageSize=20`、`sort=relevance` 及多个空 filter 字段；Aidoku 页码减 1 后发送；核查实际起点、返回 `pagination.page/page_count` 与末页判定 |
| 详情 | `/api/new-content-read/get-book-detail` | `book_id`、`with_volumes=0`；核查标题、作者、简介、封面与状态字段 |
| 卷列表 | `/api/new-content-read/get-book-volumes` | `book_id`、从 1 开始的 page、`pageSize=50`；按返回 page_count 遍历 |
| 卷内章节 | `/api/new-content-read/get-volume-chapters` | 加入 `volume_id`，page 从 1 开始、`pageSize=50`；核查卷章顺序及空卷 / 分页缺口 |
| 章节内容 | `/api/new-content-read/get-chapter-detail` | `book_id`、`chapter_id`；检查 `locked`，读取 body_snapshot 或 render_preview；核查正文完整性 |

依据：[搜索及详情入口 L28](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/sources/zh.lightnovelfun/src/lib.rs#L28)、[公共请求 L164](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/sources/zh.lightnovelfun/src/lib.rs#L164)、[卷章遍历 L187](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/sources/zh.lightnovelfun/src/lib.rs#L187)。这些都是第三方实现事实，**不是本项目已验证的源站协议**。

### 对 Shiori 有用的线索及必须验证的差异

- 请求：实现显式设置 Accept、Content-Type、Origin、Referer，要求 HTTP 2xx 且 JSON `code == 0` 后读取 `data`。没有在该文件显式注入 Cookie、token 或 security_key；底层 Aidoku 网络环境是否持有匿名 session 仍未知，不能由此删除会话调查或照搬全部 Header。
- 身份：实现将数值 `book_id` / `volume_id` / `chapter_id` 转为字符串，用书籍和章节 ID 构建 `/book/{id}`、`/reader/{book}/{chapter}`。Shiori 仍需验证 ID 稳定性及作用域，不能将字段缺失时的默认 0 当有效身份。
- 锁定：目录跳过 locked 项，正文 locked 时返回错误。Shiori 应保留受限状态与目录缺口的可解释性；不得因过滤而误报“完整目录”，也不得改成尝试绕过。
- 顺序：实现遍历所有卷章后执行 `chapters.reverse()`，并合并卷标题与章标题以适配 Aidoku。Shiori 应根据网页证据保持卷、章独立及正确源顺序，不能复制反转和展示标题拼接作为 Domain 规则。
- 正文：实现优先 `body_snapshot.body_html`，否则使用 `render_preview.body_html`，转换后空文本再尝试对应 body_text。**字段名含 preview 的回退必须核查是否为截断预览**；不能把能显示一段文字视为完整匿名阅读成功。
- 渲染：它把 HTML 转为 Markdown，最终返回单个文本 Page；处理图片 src / 相对地址、标题和基础文本样式，并跳过 script/style。Shiori 直接从实证 HTML 解析语义 ContentBlock，保持 Paragraph 和 ImageBlock 顺序，不引入 Markdown 中转或 Aidoku Manga/Page 模型。
- 图片：源码将图片 URL 嵌入文本，没有提供本项目所需的图片字节获取、解码及离线证明。懒加载属性、图片 host / Referer、失败及访问边界仍由 SRC-002 / SRC-003 验证。
- 预算：实现调用 `set_rate_limit(12, 10, Seconds)`，且目录会遍历全部分页和卷。此数值是插件配置，不是网站认可的限速；本项目继续使用第 14–15 节及调查任务预算，不直接运行它的全目录请求循环。

内容解析依据：[章节内容 L100](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/sources/zh.lightnovelfun/src/lib.rs#L100)、[HTML 转换 L322](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/sources/zh.lightnovelfun/src/lib.rs#L322)。这是可帮助缩小调查范围的实现参考；仅查到代码不能证明其编译、当前可用性或稳定性。

### 纳入下一次调查的方式

SRC-002 先从正常访客页面收集实际 Network 证据，再对照上述路径、分页及字段；不扫描第三方代码列出的端点。如果页面行为不同，以当前网页证据为准，并记录参考与实测差异。尤其核查搜索页码、受限章、预览与完整正文、卷章排序、图片字节及会话需求。SRC-003 在这些证据具备后才写最小 Dart 调查链路。

仓库 [LICENSE](https://github.com/gholts/aidoku-source/blob/fb9d3997f4a40450ede38b560af8311e387fc38e/LICENSE) 为 Apache-2.0。本次只记录实现分析和固定链接，没有把其代码复制进 App；后续若移植代码须另行保留相应许可与归属信息。代码许可证不能代替 LightNovel 内容或 fixture 的使用许可。用户提供的 Aidoku 本体安装渠道与 star 数不影响本次 Source 技术结论，本轮未核验这些产品信息。

## SRC-002：请求、身份与最小样本矩阵

状态：**DONE — 2026-09-06**。已完成目标小说搜索 → 详情 → 四卷目录 → 一项长正文 / 插图的浏览器对照，并用独立、无凭据 HTTP 请求验证核心 JSON 协议；搜索首两页和无结果均有对照。尚未运行 Dart 自动化链路，不授予 Phase 0 Go。这里的 DONE 表示本次调查及缺口记录完成，不意味着未知会话寿命、所有异常样本或各平台 runtime 已验证。

### 证据等级、环境与请求预算

- Windows PC；普通应用内浏览器访客会话，页面显示“登入/注册”；独立 HTTP 使用 PowerShell 7.6.5 `Invoke-WebRequest`。日期 2026-09-06，时区 Asia/Shanghai；期间时钟读数 23:42:52，自动采集样本时间 23:45:41–23:48:11，浏览器动作先于该自动样本窗口开始。
- **BROWSER_UI / RESOURCE_URL**：页面显示值、href、正文 DOM 结构、图片 naturalWidth / naturalHeight，以及 `pageAssets` 资源清单中的 `fetch` URL。工具不提供 method、body、Header、状态码、响应 JSON、完整重定向链；资源清单会聚合 URL，也可能包含 SSR / 预取影响，不能当精确请求次数或时序。
- **DIRECT_HTTP**：只对已经正常访问的页面、或浏览器已观察到的业务资源 URL，使用 Aidoku 参数线索做独立只读检查。其输入和响应是实际 HTTP 证据，**不是截获浏览器请求**，不声称与浏览器 payload 完全相同。每次使用独立客户端，不导入浏览器 Cookie，不发送 Authorization、Cookie 或 security_key，不跟随 redirect；不是绕过访问限制。
- 浏览器进行了 12 次成功的顶层打开 / 搜索提交 / 链接或卷切换 / 返回操作，另有 1 次不可见控件定位失败（未点击）；输入框编辑另计。独立 HTTP 实际 **13 次**：1 次页面 GET + 12 次 JSON POST；全部 200，无 redirect 跟随或失败重试。一次 PowerShell 语法错误在请求前发生，不计 HTTP 尝试。浏览器自动资源总尝试数未知，**不能把这 13 次说成整轮总请求量**。
- 已取得所需代表样本后停止访问，没有尝试耗尽 67 页、枚举所有书籍、探测受限内容或执行参考代码的全目录遍历。未来 SRC-003 严格执行其独立的 30 次 HTTP 尝试硬预算。

### 页面操作与请求对照

| 顺序 | 正常页面操作 / 结果 | 观察到的业务 URL / HTTP 补充 |
| --- | --- | --- |
| B1 | 首页访客可见 | 浏览器资源含 auth-session-v1、book-rank-list-v1、home-recent-updates-feed-v1；未独立调用这些辅助端点 |
| B2 | 显式搜索“玩乐关系”：1 项，标题“桌游咖（玩乐关系/玩玩的戀愛關係）”、作者“葵关南”、href `/book/31607` | 新见 apk-search-taxonomy-v1、apk-search-result-v1；独立搜索 POST 返回同一 book_id / 标题 / 作者 |
| B3 | 点击该身份明确的结果，打开详情新标签：4 个卷选择项，总计 10 章 | 初始客户端资源中没有详情业务 fetch；独立页面 GET 为 200 `text/html; charset=utf-8`，有 Nuxt SSR JSON 标记。只推断存在 SSR，不猜测服务端请求链 |
| B4–B5 | 切换“2 特典”，再返回“正文” | 资源清单新增 get-volume-chapters；独立目录 POST 与页面 ID / 顺序相符 |
| B6 | 打开 `/reader/31607/309555`：长正文、后记标签、注音和 14 张正文图片可见 | 新见 get-book-detail、get-book-volumes、get-chapter-detail、**get-chapter-paragraphs**；最后一个不在参考实现的请求流程中，其 body / 作用仍 UNKNOWN |
| B7–B9 | 搜索“恋爱”，点击第 2 页，再搜索特设无结果词 | 网页第 1 / 2 页各 20 个 ID；独立 POST 的 page=0 / 1 顺序完全一致。无结果页面明确显示“没有找到匹配作品” |
| B10–B12 | 返回详情，检查第 3 / 4 卷；访客按钮仍在 | 第 3 卷单项“全卷”；第 4 卷含 6 项（含“彩页”），与独立目录样本全部相符 |

源站页面自动加载了评论相关资源；本轮没有主动访问用户主页、发送评论或保留评论 / 用户信息。图片统计限定 `.reader-text`，排除了头像、勋章和评论图片。

### 已验证核心协议（DIRECT_HTTP，不冒充 Browser Network payload）

公共前缀：`https://www.lightnovel.fun/api/pc-proxy`。下表路径均追加于该前缀。全部为 POST JSON，成功响应 200、`application/json; charset=UTF-8`、`code=0`，业务值在 `data`。未验证非零 code、HTTP 拒绝或 WAF 响应格式，不能构造“真实失败样本”。

| Operation / 后缀 | 成功请求的输入 | 验证结果 |
| --- | --- | --- |
| Search `/api/bff/apk-search-result-v1` | `q`、`page`、`pageSize=20`、`sort=relevance`；其余空 filter 字段见 fixture | 请求 page **0 起算**，响应 `pagination.page` **1 起算**。page=0/1/2 分别返回 1/2/3；前两页逐项匹配 UI，第三页只属 HTTP 样本 |
| Detail `/api/new-content-read/get-book-detail` | `book_id="31607"`、`with_volumes=0` | 同书身份；默认 volume_id=44117、chapter_id=309555，4 卷 / 10 章 |
| Volumes `/api/new-content-read/get-book-volumes` | book_id、`page=1`、`pageSize=50` | 有序返回 4 卷，pagination total=4 / page_count=1 |
| Chapters `/api/new-content-read/get-volume-chapters` | book_id、volume_id、`page=1`、`pageSize=50` | 四卷分别 2 / 1 / 1 / 6 项，返回 locked 均为 0；不反转，不依赖标题提取 ID |
| Chapter `/api/new-content-read/get-chapter-detail` | book_id、`chapter_id="309555"` | locked=0；body_snapshot 与 render_preview 均有 HTML / text，结构统计见下文 |

成功组合显式发送 `Accept: application/json`、`Content-Type: application/json`、Origin / Referer 为站点根地址。**只证明这组 Header 与参数有效，未证明每个字段必需**；没有通过多次删参试错判断必要性。响应若含 Set-Cookie，本轮未记录其值或作用；不声称站点不发 Cookie。13 次独立请求的成功说明这些样本不依赖提前导入用户登录凭据，不能外推所有书籍、端点和未来时间。

搜索“恋爱”当时 total=1321、page_count=67；第一页与第二页 20 个 ID 无交集。空查询结果样本（非空但不存在的关键词）是 `list=[]`、`has_next=0`、`total=0`，**page_count 仍为 1**。分页结束不能只判断 page_count=0；结合 `has_next`、响应页数、空列表、重复 ID / 页保护。第 67 页没有实际请求；catalog 多页终止尚未实测，本书各卷均只有一页。

### 身份、顺序与内容证据

| 网页卷标签 | volume_id | chapter_id（源顺序） | 覆盖意义 |
| --- | --- | --- | --- |
| 正文 | 44117 | 309555、309556 | 每项可包含整卷长文本，不能按短章估计大小 |
| 2 特典 | 9918 | 208472 | 特典命名；只核对目录，未额外读取全文 |
| 3 （玩乐关系/玩玩的戀愛關係）【已完本含实体特典】 | 9919 | 208477 | 章名“全卷”与卷名独立 |
| 第4卷 | 46122 | 317939、317940、317941、317959、323103、323197 | 制作信息、彩页及拆分文本章节 |

book_id / volume_id / chapter_id 在独立 JSON 中为数值，页面 href 的 book / chapter 对应相同值；请求字符串 ID 可成功。Shiori 仍应按计划在 Source 边界转换为字符串并带 source scope。当前只证明当次跨 operation 一致性；跨会话重启 / 长期稳定性未测，不能证明 ID 全站唯一。字段名是 `sort_index`（未保存取值），不是 `sort_order`；本次有序 list 与 UI 一致，禁止凭数值 ID 大小或倒序适配规则重排。

章节 309555：API `body_snapshot.body_html` 256,358 字符、4,084 个 p 标签、14 个 img 标签；body_text 139,470 字符。render_preview 的上述长度与计数相同，**只验证这一项，未证明 preview 在所有章节都是全文**。网页 `.reader-text` 的 p / img 数同样为 4,084 / 14，另有 17 个 ruby；textContent 138,806 字符，与 API body_text 的计算口径不同。出现后记标签，但没有与出版原版逐字核对完整性。

正文子标签观察到 P / STRONG / RUBY / RT / A / IMG。其开头出现外部下载链接、访问口令和群信息，不属于 Source 所需数据，已全部排除。网页正文的最长单个 p 为 178 字符，本轮**没有真实极长单段样本**；整项长正文与极长单段必须分开测试。

14 张正文图片均 `complete=true` 且 natural dimensions > 0，证明浏览器已解码，不仅是找到 URL。代表图片 path `/upload-files/images/250524/2ffb192e695743321ebab6c443b0b652.jpg`，host `api.lightnovel.fun`，解码尺寸 2048×829。图片 URL 含 `m` / `t` 查询字段，值未写入文件；其签名 / 过期语义尚未验证，不自行计算或去掉参数访问。图片 Referer / Cookie 必要性、HTTP MIME、独立 Dart 字节解码仍 UNKNOWN；不能由扩展名断言响应 MIME。Media 的候选稳定键只能在后续验证后决定，禁止把本次临时查询串直接当长期身份。

### 样本、缺口与后续输入

样本清单在 [`test/fixtures/lightnovel/manifest.json`](../../test/fixtures/lightnovel/manifest.json)，使用说明见同目录 README。真实记录只保存必要身份 / 目录 / 分页元数据或结构统计；并非完整响应。人工转录、自动投影、纯合成三种 provenance 分开标注，不把结构统计文件用作生产 JSON Parser 的完整输入。

正文明确有未经允许禁止转载提示。未保存小说原文、原始 HTML、完整 HAR 或原图；正文结构 fixture 和 2×2 PNG 是自行生成的合成资产。许可仍不因此关闭。没有源站代码复制、App 业务实现、生产 Parser 或独立 Dart probe。

| 项目 | 状态 / 责任 |
| --- | --- |
| 目标书搜索 / 详情 / 四卷目录 / 一项正文 / 浏览器图片 | OBSERVED；当次身份、顺序、文本与图片结构已有证据 |
| 搜索第一页 / 下一页 / 无结果 | OBSERVED；API 与 UI 对照，catalog 多页及搜索末页仍为覆盖缺口 |
| 无卷 / 缺标题 / 重复编号 / locked / HTTP error / 极长单段 | 本次代表书未遇到，未枚举网站寻找；合成设计样本明确不是真实 API 返回 |
| get-chapter-paragraphs、辅助首页接口 | 仅浏览器资源 URL；method / payload / 响应 / 必要性 UNKNOWN，不能由参考代码补造 |
| 会话重启、自然失效、图片 m/t 生命周期 | UNKNOWN；后续 SRC-003 / SRC-005 / SRC-010 根据正常访问证据处理 |
| Browser Network 精确 payload / Header / redirect / 全部请求计数 | 当前工具能力不足；已有独立 HTTP 证据可支撑 SRC-003 起步，后续如需声称浏览器等价，应补实际 Network 记录 |
| 内容 / fixture 分发许可 | 未关闭；现有交付仅元数据、结构统计和自制资产，不等于授权转载原文 |
| Android / iOS 网络、图片、存储 runtime | 未测；SRC-002 不改 TEST-001 或 IOS-002 状态 |

下一步 SRC-003：以本书 31607、默认卷 44117、章 309555 为身份断言；使用已验证的搜索 0 起算 / 目录 1 起算和 POST 组合建立独立 Dart 调查包。默认离线，只在 opt-in 下低频 live；字节 / 图片解码、重定向与预算必须由该包真正验证。需要额外捕获字段时先取得最小脱敏样本，不扩大成全书采集。

本次验收：网页标题 / 作者 / 四卷十章顺序人工对照；搜索两页 ID 与 HTTP 样本逐项一致；正文 p / img 计数一致；全部 JSON 可解析、manifest 文件和哈希一致、无重复章节 ID；检查 fixture 无实际会话秘密、签名 query、原文、用户链接 / 头像和外部下载口令。没有为文档任务重复跑 Flutter analyze / test / build。

## SRC-003：独立 Dart 图文链路（2026-09-07）

**Status：DONE。** 工具与复跑命令见 [`tools/source_probe/README.md`](../../tools/source_probe/README.md)。独立 pubspec / lockfile / 分析配置，运行于 Windows、Dart 3.10.3；没有引入生产 Source，没有改主 Flutter 依赖。新增 `html` 用于结构统计，`image` 用于纯 Dart 字节解码，`crypto` 用于哈希，版本及官方 API 依据见工具 README。

### 当次实际结果

首次本地时间 2026-09-07 00:05:37–00:05:58，最终复核 00:14:32–00:14:50（报告时间为 UTC）。先完成离线预检，再执行 live，不改查询、不追加其他小说。首次记录：[`live-20260907.json`](../../tools/source_probe/reports/live-20260907.json)；最终验收：[`live-final-20260907.json`](../../tools/source_probe/reports/live-final-20260907.json)。两轮下表结果和图片哈希一致。

| 阶段 | 结果与身份断言 | HTTP 尝试 |
| --- | --- | --- |
| Search | 玩乐关系 → book_id=31607，标题与作者精确匹配；不依赖第一项位置 | 1 POST，200 |
| Detail | 重复验证书身份，默认卷 44117 / 章 309555 一致 | 1 POST，200 |
| Volumes | 4 卷，单页总数一致，选定卷存在且唯一 | 1 POST，200 |
| Chapters | 所选卷 2 章，目标章与书 / 卷归属一致，locked=0 | 1 POST，200 |
| Chapter text | body_snapshot 非空；139,470 UTF-16 code units、405,531 UTF-8 字节；4,084 个 p、4,070 个非空文本 p、14 个 img、17 个 ruby | 1 POST，200 |
| Illustration | 正文第 1 张图：MIME=image/jpeg，310,858 字节，纯 Dart 解码 2048×829 | 1 GET，200 |

每轮 6 次，SRC-003 总计 **12 / 30 次 HTTP 尝试**（第二轮预算设为剩余 24），每次后续尝试前等待至少 1 秒；没有重定向、没有自动重试。没有主动发送 Cookie / Authorization / security_key 或导入浏览器会话，每次请求使用独立 HttpClient。图片保留当次正文 URL 的 m/t 参数进行正常请求，报告不保留其值，也不记录完整图片 URL。解码尺寸与 SRC-002 浏览器 natural dimensions 一致，证明收到有效字节并解码，未把 URL 存在视为成功。

图片 SHA-256：`a3d6ec3df6afbcdba871ceefb3e6902f75c8c711fde8d03803310c8a11dde2fa`。哈希仅描述当次字节，不是签名 URL 或生产 Media 的稳定主键。原图、正文和 HTML 未写入仓库；body 的长度和结构计数与 SRC-002 样本一致，但仍未与出版原版逐字核对。

### 离线、预算与失败验收

[`offline-20260907.json`](../../tools/source_probe/reports/offline-20260907.json) 通过全部 5 个阶段，**0 次 HTTP**：15 个文件的 manifest 哈希、身份 / 分页 / 四卷十章元数据、合成 HTML 与自制 PNG。原始 SRC-002 fixtures 保留不改，结构摘要没有伪装成完整响应输入。

工具默认只执行这些离线阶段；显式 `--live` 才启用网络。预算只允许 1–30，尝试发出前计数，失败和重定向也占用；API 跳转停止，媒体最多允许 3 个经验证的同站 HTTPS 跳转；耗尽即记录 `budget_exhausted`，不发送下一请求、不继续后续阶段。受限 HTTP / 非零 code / 身份不符 / locked / preview-only / 缺正文图均终止；没有使用 WebView、认证信息、解锁或备用端点。

每次请求总超时 30 秒、连接 15 秒、响应上限 16 MiB；图像 MIME 与格式必须相符，先验证单帧及 2,000 万像素上限再解码。报告按白名单输出统计和常量失败码，不输出响应体、原始异常和签名值。测试中使用内存传输与秘密哨兵验证失败报告、预算和脱敏；这些是假响应，不是新捕获的站点异常样本。

边界测试发现 image 4.9.2 的 JPEG `startDecode/readInfo` 会在返回尺寸前分配系数缓冲，原保护位置过晚，导致超大合成 JPEG 测试被中止。修复为先检查 JPEG 帧头 / PNG IHDR，再进入库解码；本工具只启用 JPEG/PNG。**23 项离线测试通过，最终静态分析通过。** 新预检改变实际图片准入条件，因此在剩余预算内做第二轮 live 验证；未保留或覆盖第一轮报告。

### 平台与仍存缺口

- 本次实际证明 Windows 独立 Dart 请求与图像解码；不能替代 Android Flutter codec / 真机网络验证（TEST-001 / ANDROID-002），iOS 仍为 IOS-002 / DEFERRED_NO_MAC。
- 仅解码一张正文插图；其余 13 张继续只有 SRC-002 浏览器解码证据。Header 组合有效不等于逐项必要性已知。
- 不同客户端及本次两轮匿名成功没有证明全站匿名边界、Cookie / token 寿命、m/t 的过期语义或长期身份稳定性。没有故意制造过期、访问限制或限流。
- catalog 多页、真实失败 schema、平台会话恢复、内容/fixture 许可及生产契约仍待后续任务。SRC-003 通过不等于 Phase 0 Go；下一步 **SRC-004** 审查现有证据和 Source 准入，不应无故重复访问源站。

## SRC-004：Source 可行性 Gate 与契约审查

**审查日期：2026-09-07，Asia/Shanghai；审查者：Codex（本轮 Principal Engineer / Technical Lead）。Task Status：DONE；Gate：GO；Phase 0：PASS（当次技术可行性）。**

准入范围是基于已验证普通访问路径开发 Pure Dart Source。目标查询、书籍身份、正文和真实图片解码链路均已通过；当前没有证据要求登录或平台 WebView 才能完成该样本。Domain / NovelSource / SourceMedia 草案可以承载已观察内容，无须增加站点 Header、签名或 HTML 字段。未观察的会话寿命、媒体长期定位和生产质量仍按下表设置独立完成门槛，不能由本次 GO 越过。没有证据支持全站访问承诺或内容分发许可结论。

### 证据核对与 fixture secret review

- 审查对象为**工作区最终文件**：SRC-001..003 分层记录、15 项 manifest 样本、manifest / README、3 份调查报告及调查包的请求、报告与测试边界；不是只审暂存区快照。SRC-003 两次 live 各 6 次 HTTP，合计 12 / 30；最终报告的逐次记录、阶段计数及汇总一致。离线报告 0 次 HTTP、5 阶段通过；最终 live 共 11 阶段通过。
- 目标仍为玩乐关系 → 31607 / 44117 / 309555，标题、作者和归属均断言。两轮正文统计、JPEG 字节数、哈希和 2048×829 尺寸相同。四卷十章的覆盖来自 SRC-002 目录样本；SRC-003 live 只读取所选卷的两章目录及一项正文，不能说每次都抓取了全部卷正文。
- 15 项 SHA-256 全部匹配；fixtures 与 reports 两目录共 **20 个文件：17 JSON、1 Markdown、1 HTML、1 PNG**，JSON 均可解析。PNG 是 manifest 标明的自制 2×2 资产。哈希证明本次审查输入一致，不证明网站真实性或许可。
- 检查 JSON 字段和值、URL、正文摘要及图片资产：未发现 Cookie / Set-Cookie / Authorization / token / security_key 的实际值、签名查询值、账号 / 评论 / 用户链接、原文、原始 HTML、HAR、原图或下载口令。关键字命中是字段名、false 标记和脱敏说明；例如 `dataKeys` 内的 `poster_user` 只是结构名称，没有对应用户值。标题 / 作者 / 目录 ID 为目标识别元数据，自制 HTML 有合成标记。
- 真实投影、人工转录、结构统计、合成场景的 provenance 明确。现有 fixture **不够直接充当完整生产 Parser 响应集**；不因哈希通过而补造真实正文样本。后续使用有标记的合成 envelope / 内容及现有真实元数据做回归，新增真实样本仍须最小化及审查保存依据。
- 核对 SRC-003 的秘密哨兵与停止测试、默认离线入口、重定向计数和 JPEG 文件头预检；采用其已通过的 23 项离线测试记录。本任务只做只读核查和文档修改，**新增源站 HTTP = 0**，没有无故重复 Flutter build 或 live 测试。

审查输入指纹（SHA-256）：最终 live 报告 `a02538a6b5fefa69a34b3440d98b9af9ed3d40c94fde048d8eb7419ee3358eac`；SRC-002 manifest `f134be6a291ba1781bb28bfe83906340c93a791e752315308d07620423297b2f`。报告和 fixture 保持原样，历史 `NOT_EVALUATED_SRC004` 不回写成新结论。

### 契约决策与 Phase 2 输入

| 决策 / 输入 | 已有依据与生产要求 | 责任 |
| --- | --- | --- |
| 稳定身份 | App 的 SourceId 固定为 `lightnovel`；远端数字书 / 章 ID 在 Source 边界转为不透明字符串，分别进入 NovelKey / ChapterKey；卷 ID 作为 Source 私有真实 groupId，不能用标题或顺序替代。fixture 中 `sourceIdForFutureAdapter=lightnovel.fun` 是调查候选标签，不是已发布领域键 | CORE-002 / CORE-003 / SRC-005 |
| 请求基线 | 只采用 SRC-002 已验证表中的五个 POST、JSON envelope 和成功 Header 组合；不宣称 Header 逐项必要。无证据需要会话时 ensureSession 为 no-op，不添加 auth-session 请求、CookieJar 或强制初始化 | SRC-005 |
| Search / Discover | Search 请求页 0 起算，响应页 1 起算；cursor 绑定查询和源。空结果 page_count=1，不靠单字段猜终止；生产加入重复页 / ID 保护。首页仅有资源 URL，初始 supportsDiscover=false，discover 返回 unsupported | SRC-006 |
| 详情与目录 | 详情缺可选字段按 unknown 处理，响应 `status=1` 的业务含义未证实，不推断完结。卷章保留源 list 顺序；聚合局部失败不返回“完整目录”。probe 的固定默认 ID 和单页断言是样本验收条件，不是所有小说的生产规则 | SRC-007 / SRC-008 |
| 正文模型 | 已见 p / img / ruby / rt / strong / a；保持段落与图片顺序。Ruby 初始降级为基字加括注，强调保留文字；暂不启用复杂 runs / 新 AST。段内未知可见文本不丢失，链接只保留文本。整卷长章不等于极长单段，切块仍只在 presentation | CORE-002 / SRC-009 / READER-001 |
| 正文准入 | 使用已验证 body_snapshot；render_preview 或缺字段不能自动视为全文。受限响应映射标准失败，不另试端点。probe 的非空文本 + 图是本次样本条件，生产合法纯文本章 / 图片章分别有效；访问受限章不应通过删目录或反转章节顺序掩盖 | SRC-008 / SRC-009 |
| MediaRef / SourceMedia | 继续保持 opaque mediaId + Source 私有定位；m/t、Header 和当前 URL 不进入 Domain / cache key。可调查“所属章节 + 无 secret 资产 locator → 正常重新读取章节取得当前 URL”的恢复方案，但**本次不认定该方案或 path 长期稳定**。图片哈希只描述字节 | SRC-010 |
| 媒体资源边界 | 传输字节预算与解码内存预算分开；JPEG 的尺寸预检必须在有分配行为的 readInfo 前。调查包 image 依赖和仅 JPEG/PNG 的限制不直接成为 Flutter codec / 产品格式承诺 | NET-001 / MEDIA-001 / ANDROID-002 |

### 保留问题、完成门槛与影响

| OQ / 待项 | 当前结论 | 后续责任 / 未关闭的影响 |
| --- | --- | --- |
| OQ-01 / OQ-12：访问范围、公开规则、接入及分发依据 | 只证实样本普通访问；secret review 通过不等于授权转载。政策正文和许可仍 UNKNOWN | SRC-005 遇正常访问限制即停；RELEASE-001 在公开分发前核对规则、许可和资产。不把许可标关闭，不把本次技术 GO 当发布许可 |
| OQ-02：未验证操作 / 失败形态 / 多页 | 五类 POST 已验证；auth-session、首页、taxonomy、get-chapter-paragraphs 不进入已验证表；真实异常 schema、catalog 多页、搜索末页仍缺 | SRC-005..009 用有标记的合成输入验证停止与分页规则；新操作须先有正常访问证据，否则保持 unsupported。阻止相应能力完成声明，不阻止已验证操作的开发 |
| OQ-03：会话生命周期 | 干净独立 HttpClient 可读取样本；不是匿名 session 不存在的证明 | SRC-005 保持 no-op 基线，只有自然出现且能确认的过期才实现有界恢复；不凭 403 猜过期。会话实现及恢复验收不能跳过 |
| OQ-04：MediaRef 跨重启 | 当次身份一致；稳定定位、m/t 生命周期、Referer 必要性未验证 | **SRC-010 的硬验收项**：清空内存、重新进程后能从已保存且无 secret 的 MediaRef / locator 恢复正常请求；若做不到，SRC-010 标 BLOCKED，TEST-001 及真实媒体链路不能宣告完成；Fixture / Domain 独立任务可继续 |
| OQ-05：正文结构 / 边界 | p / img / ruby 等和整卷长正文已观察；空行、br、真实极长段、图片章和异常样本不足 | SRC-009 以合成样本验证语义保留并明确 provenance；不靠截图统计假装 Parser 已通过。READER-001 验证长章与段落布局，不改语义身份 |
| OQ-11：验收书 / 限流 | 样本选择与图文可达问题已关闭；真实限流规则仍 UNKNOWN | NET-002 / TEST-001 使用客户端保守预算；遇自然 429 尊重限制，不压测，不宣称 30 次是站点允许值 |
| OQ-14：WebView 与平台 | 当前观察路径无需 WebView；不推断未来永久不需要 | SRC-005 / TEST-001 若发现正常访问必须平台能力，先更新 ADR / iOS impact 并重开 Source gate，不引入 Android-only Source。Android 生产 codec 待 TEST-001 / ANDROID-002，iOS 待 IOS-002，无 Mac 不阻塞本次技术 GO |

下一项可领取的 Foundation 工作是 **CORE-002**（CORE-001 已完成）。Source 侧下一项为 SRC-005，但它还依赖 **NET-002、DB-002**；按原依赖先完成相关 Foundation 任务，不能仅凭 SRC-004 DONE 跳过前置。本次不自动领取后续任务。

## SRC-005：生产请求与无会话分支（2026-09-07）

状态：**DONE（请求基础层）**。实现位于 `lib/data/sources/lightnovel/`，采用 SRC-004 已决定的 no-op 会话基线。本轮新增源站 HTTP **0**；以下均为既有访问证据上的实现和合成响应回归，不是对网站当前可达性的重新证明。

- `LightNovelSource` 实现 NovelSource 的装配骨架，固定 SourceId=`lightnovel`，构造器借用应用共享 RequestScheduler 并拥有私有 API / transport。创建对象、描述信息和 no-op ensureSession 均无 I/O。业务解析尚未进入本项：search / detail / catalog / chapter 暂时返回 unsupported，后续 SRC-006..009 接线；discover 保持 unsupported，分页能力也暂不声明已实现。没有自动替换 App 的 fixture 或宣称在线阅读已可用。
- `LightNovelApi` 只接受枚举中的五个已验证 POST 端点，policy 精确匹配 URI；不开放任意 host / path、auth-session、taxonomy 或备用接口。采用已观察成功的 Accept / Content-Type / Origin / Referer 组合。payload 和响应 envelope 只留 data 层，具体字段构造与解析属于后续操作任务。
- ensureSession 显式 no-op，无状态、无网络初始化，自然不存在并发重复初始化；不引入 CookieJar、AppPaths 会话文件或凭据持久化。Set-Cookie 被忽略，重建实例也不携带 Cookie / Authorization / security_key。损坏会话清理为 N/A，因为当前没有会话存储；不删除任何本地库或其他源数据。
- 401 / 403 直接映射 accessRestricted，429 沿用同源冷却。所有本源 POST 的 safeToRepeat=false，不叠加恢复重试。未观察且不能确认的非零业务 code 返回 unsupported，缺失 / 错误 envelope 返回 parse / invalidContent；不猜登录失效码、不暴露服务端 message。真实异常 schema 仍 UNKNOWN。
- API 请求不跟随重定向，包括同 origin 的其他已验证端点。为表达这一限制，NetworkRequest 增加有界 maxRedirects（默认仍为 5，本源设为 0），原网络行为保持默认值。接收上限沿用 8 MiB，调用 deadline 不延长 NetworkClient 的 45 秒总预算；排队、取消及限流沿用同一个 scheduler。
- 数值远端 ID 在 Source 边界验证为正十进制字符串，构造 NovelKey / ChapterKey；缺失、0、负值、浮点、URL 等输入不能自动变为合法身份。没有从标题、顺序或试验固定 ID 生成生产标识。
- composition root 负责先等待 Repository 结束，再 close Source，最后关闭共享 scheduler。Source.close 幂等并中断自己的 transport，不关闭其他源借用的 scheduler。

验收：新增 **10 项**离线测试，完整工程 **187 项 PASS**；真实 Dio + TestAdapter 验证五端点、请求 Header、重建实例无 Cookie、错误响应、无自动恢复 / 重放、同域重定向停止、过期 deadline / 取消 / close、ID 及日志秘密哨兵。响应全部合成，没有保存真实失败正文或新小说内容。本机完整测试记录 `.tooling/evidence/src005-tests.txt`。

iOS Level A：共享 Dart / 既有 Dio，无平台分支、新插件、会话磁盘或最低系统变化。Android 新包运行、真实 TLS、OS 重启均未在本轮验证；实例重建测试不冒充进程重启。生产真实链路归 TEST-001，iOS runtime 仍 **DEFERRED_NO_MAC / IOS-002**。未来只有自然出现并能确认的会话需求才能改变 no-op 决策并补恢复验收；本项不关闭 OQ-03 的长期访问假设。
最终全项目 analyze：No issues found。

## SRC-006：搜索解析与分页（2026-09-07）

状态：**DONE**。LightNovelSource.search 已接入 SRC-005 的受限 API；supportsSearchPaging=true。discover 仍返回 unsupported、supportsDiscover=false，不请求仅观察过资源 URL 的首页接口。详情 / 目录 / 正文仍留 SRC-007..009，当前 App 未自动切换到生产源。

- 搜索在 Source 内 trim 查询；空白查询直接返回空终页，不发送请求。非空查询以 UTF-8 JSON 传递，保留中文和特殊字符；沿用 SRC-002 的完整空 filter 字段、pageSize=20、sort=relevance，请求 page 从0开始。
- 严格解析 list、book_id、非空 title 和 pagination；author_name 缺失 / 空值时保留空作者列表，错误类型拒绝。NovelSummary 使用固定 lightnovel 身份，保留源顺序。封面暂为 null：MediaRef 定位及跨重启准入属于 SRC-010，不把响应中的临时 URL 写入领域模型。
- 响应 page 必须为请求 page+1；page_count / total / page_size 校验，存在的 has_next / 顶层 total 必须与 pagination 一致。合法空结果 total=0、page_count=1 是终页；缺失关键结构、矛盾分页或不完整空页返回 parse。has_next 允许缺失，由 pagination 判定（早期已记录投影没有保留此字段）。
- 游标是实例内随机句柄，绑定 trim 后的查询、下一请求页及已见 ID；不含查询、URL、签名或凭据。不同 query / source、并发重复消费、伪造、已成功消费及已淘汰游标均返回 invalidCursor，且不发请求。跨页 / 页内重复 ID、响应重复页返回 repeatedPage；失败和取消不消费有效游标，允许用户明确重试。
- 每个实例最多保留32条续页状态，超限按最早发放淘汰；每链最多5000个 ID，超限返回 tooLarge，不静默截断。游标不跨进程保存，重建 Source 或失效后需从首页重搜。close 清理状态并关闭既有 API。没有自动遍历、预取、增加网络重试或更改全局调度预算。

验收：新增 **9项**搜索测试；完整 **196项离线测试 PASS**，全项目 analyze **No issues found**。覆盖首 / 后 / 末页、空白及实际空结果投影、中文请求编码、查询绑定、取消、重复 ID / 页、破坏字段、游标淘汰、目标标题作者和发现 unsupported。本机记录 `.tooling/evidence/src006-tests.txt`。

fixture 来源：保留原 manifest / captured 文件不改；测试直接读取三页真实 ID / 分页投影，并在测试内明确添加 Synthetic 标题以构造解析输入。目标标题 / 作者沿用 initial-http-observations 的已记录元数据；末页、错误结构及容量场景均为合成，不宣称新捕获或已访问真实末页。本轮新增源站 HTTP=0。

iOS Level A：共享 Dart 解析及既有 Dio，未增加依赖或平台分支。Android / iOS runtime 和真实在线搜索本轮未执行；生产链路仍由 TEST-001 验证，iOS runtime DEFERRED_NO_MAC。SRC-005 的访问假设与 SRC-010 媒体门槛继续保留。

## SRC-007：小说详情（2026-09-07）

状态：**DONE**。getNovelDetail 已通过 LightNovelDetail 请求 book_id / with_volumes=0，校验 source 和返回书籍身份；标题必须为非空字符串，缺作者、简介、标签或封面仍可成功。未知 status（包括历史1）继续 unknown，未确认时区的 updated_at 不转换为伪精确 UTC。

本轮按用户明确授权补做 **1 次**详情 POST：无 Cookie / Authorization、无重试、禁止 redirect，响应200 / code0，book_id 与31607一致。只输出并记录字段结构，未保存简介、标签值、账号数据或完整封面地址。确认 summary_short 为字符串（31字符、当次无HTML）、tags / visible_tags 为字符串数组、cover_url 为 api.lightnovel.fun 的 HTTPS 绝对地址且有查询参数。最小结构记录为 `test/fixtures/lightnovel/src007/detail-structure.json`；这是本轮工具结果的人工投影，不改原 SRC-002 manifest 或旧快照。此请求是宿主 HttpClient 补证，不能冒充生产 Source 端到端运行。

- 简介目前映射已证实的 summary_short，不猜测 description / intro 或未观察到的完整简介接口。使用 HTML parser 提取文字，丢弃 script / style / form / iframe / template / object 等节点；保留段落和换行，解码实体，不执行脚本或加载外部资源。tags 字符串逐项转为文本、去空去重；字段存在但类型异常返回 parse，而不是无声丢字段。
- 封面解析只允许站点 www / api 两个 HTTPS host、默认443、无用户信息和 fragment。相对地址按站点根解析；相对输入只有合成边界测试证据，不宣称实站本次返回了相对 URL。领域 MediaRef 为 `cover:v1:<bookId>`，表达该书的封面角色，不含 URL / path / 签名。当前不持久保存 URL，也不下载封面；SRC-010 必须通过重新读取详情定位当前封面并验证跨重启，完成前不得宣称该 MediaRef 已可离线或实际加载。
- 必要字段缺失、身份错误、登录 HTML、非法 UTF-8 和可选字段错误类型通过标准 Failure 返回；权限码仍由 SRC-005 映射，不为访问限制增加恢复或备用请求。

新增 **7项**详情测试，完整 **203项离线测试 PASS**，analyze **No issues found**；本机 `.tooling/evidence/src007-tests.txt`。测试复用已记录详情元数据，HTML、相对封面、签名变化及异常输入均明确为合成；真实补证只验证结构，不保存或复用原文。

依赖：固定 `html 0.15.7`，新增传递 `csslib 1.0.2`，均为 Dart 包，无原生插件。用于正确处理实体及 HTML 结构，避免正则剥标签；[官方版本列表](https://pub.dev/packages/html/versions) 声明该版本最低 Dart3.6，与固定 Dart3.10.3 相容，包声明 Android / iOS 支持。没有升级其他既有依赖、改最低 OS 或原生配置。iOS Level A PASS，runtime 仍 DEFERRED_NO_MAC；Android 新包运行与真实生产请求链仍未验收，后续 TEST-001。
最终 Android Debug 构建（lib/main_dev.dart）PASS；未安装或执行模拟器新包，不替代设备 runtime 验证。

## SRC-008：卷章节目录与顺序（2026-09-07）

状态：**DONE（已验证的卷→章节协议）**。LightNovelSource.getCatalog 已接入目录聚合；先串行读取全部卷页，再按原顺序逐卷读取章节页。请求仅使用 SRC-005 的 volumes / chapters，page=1 起算、pageSize=50，不反转、不按数字或标题排序，也不初始化额外会话。

- 卷 ID 为真实 groupId，缺卷名保留 null，空卷保留；章 ID 与 NovelKey 组合保证跨小说隔离，ordinal 在整份目录中连续递增。重复卷 ID、同页 / 跨页 / 跨卷重复章 ID 均失败；章的 book_id / volume_id 必须匹配当前请求。标题重复但 ID 不同可保留，不把重复显示名当重复章节。
- 每页验证 page / page_count / total / page_size，分页中的总数或页数变化、重复页、提前空页、最终数量不足都返回 parse；卷声明 chapter_count 时必须与实际聚合一致。任何卷或页失败只返回 Failure，不交付已取到的部分 Catalog，也不提前写入 Repository 记录。
- locked=1 的章节保留，不过滤或改顺序。现有 Chapter 是身份 / 标题 / 顺序模型，没有访问状态字段，因此目录存在不代表可读；实际正文访问须在 SRC-009 拒绝受限响应，不据此宣布已具备 UI 锁定标识。
- 空卷列表映射为空的 synthetic group（groupId=ungrouped），不请求猜测的 volume_id=0。**无卷但实际有章的源站协议尚未验证**，本项不支持臆造该分支，也不宣称覆盖了真实无卷有章样本；后续若遇到该结构须补正常访问证据，再接入同一 Catalog 层级。当前空分组只表达已返回的空列表。
- 单次聚合共享45秒总 deadline，最多100次逻辑请求、最多5000章；分页元信息超限立即 tooLarge，绝不静默截断或返回半份目录。沿用全局调度器500ms同源间隔、取消和源请求禁止自动重放的规则；取消在页面和卷之间检查。达到预算可由用户明确重试，尚未实现大目录续传。
- 复用 Catalog.flatChapters 与既有 revision 计算；相同目录重复读取 revision 相同，卷名或顺序等语义变化产生新 revision。没有改变领域契约、目录 codec、数据库 schema、页面展开状态或导航 UI。

验收：新增 **8项**目录测试，完整 **211项离线测试 PASS**，analyze **No issues found**。复用现有四卷十章投影与卷元数据，验证原顺序、连续 ordinal 和稳定 revision；合成多页、缺名、空目录、受限行、跨小说同章 ID、重复 ID、冲突归属、分页变化、超限、后续卷403与中途取消。合成测试不冒充真实多页 / 限流 / 无卷证据，原 fixture 与 manifest 保持不变。本机日志 `.tooling/evidence/src008-tests.txt`。

本轮新增源站 HTTP=0，未复用 SRC-007 的单次授权追加访问。Android / iOS runtime 未执行，无新增依赖或原生配置；iOS Level A PASS，runtime 仍 DEFERRED_NO_MAC。生产目录网络链与设备行为仍归 TEST-001；下一项 SRC-009 正文解析。

## SRC-009：正文 ContentBlock Parser（2026-09-07）

状态：**DONE（正文结构化解析）**。LightNovelSource.getChapter 已通过已验证端点请求 book_id / chapter_id，校验归属、非空标题和 locked；locked=1 返回 accessRestricted，未知锁定类型 / 值返回 parse，不删除目录项或尝试解锁。

- 正文只从 body_snapshot 获取。非空 body_html 按 HTML 解析；HTML 缺失 / 空白时允许 snapshot.body_text 按换行转换为段落；render_preview 单独存在永远不能作为全文。错误身份、缺 snapshot、仅空白或无可读文字 / 图片均失败。HTML 登录 form / 密码输入不误判为正文。
- 输出 ParagraphBlock、ImageBlock、HeadingBlock、DividerBlock；保留源图文次序、段落边界、br 行内换行、显式空 p、中文全角空格语义缩进（最多8 em），段内强调和链接降级为文字。Ruby 基字保留、rt 转括注、rp 丢弃以免重复括号。未知普通标签遍历其可见文字，script / style / iframe / object / template 等非正文节点丢弃；不执行 JS 或加载 WebView。
- HTML 排版用的 ASCII 空白按普通流折叠；没有逐像素复刻网页 CSS、pre 空白布局或任意 text-indent 样式。极长语义段仍一个 ParagraphBlock，不输出 RenderChunk；段内插图按文本 / 图片 / 文本拆出，确保文字没有被图替代。
- img 优先非空 data-src，再 data-original，最后 src；惰性属性与 figure / figcaption 是合成兼容场景，不声称 Phase 0 实站已观察到这些属性。图片 alt / 正整数尺寸与 figure caption 被保留；纯图片章可成功，缺定位或未允许 URL 不静默跳图。
- 图片只接受站点 www / api 的 HTTPS、默认443、无凭据和 fragment，相对 URI 按站点根解析。MediaRef 为书 / 章身份加 origin+path 的摘要，不携带实际 URL 或 query；查询签名变化不改变语义引用。**path 的长期稳定性和从此摘要恢复当前图片请求尚未验证**，必须由 SRC-010 重读正文、匹配 locator 并完成真实跨重启验证；本项只生成引用，未实现 SourceMedia 或下载图片，不能宣称图文链路已经完成。
- 复用 ChapterContent 的 occurrence / blockKey / contentRevision 和 JSON 验证；同语义重复段有独立 occurrence，尺寸不影响已有图片语义 identity。HTML 深度限制128，按边界检查语义块上限20000，沿用8 MiB网络接收上限，不引入领域 AST 或依赖变更。

验收：新增 **8项**测试；复用既有明确标注 SYNTHETIC 的 chapter-shape.html，其他长段、图片章、懒加载、caption、空行、坏结构和访问限制均为合成输入。验证超长段完整往返 ChapterContent JSON、重复段身份、revision稳定、签名变化不进入序列化；正式 Repository + in-memory SQLite 集成验证坏正文刷新保留旧缓存。原始小说正文及图片均未新增到仓库，既有 fixture / manifest 保持不变。

本轮新增源站 HTTP=0；无新增依赖、原生代码或平台配置。iOS Level A PASS；Android / iOS runtime、生产原文兼容度和实际取图未在本轮验证，iOS runtime 仍 DEFERRED_NO_MAC。下一项 SRC-010 是媒体准入硬门槛，未自动执行。
最终验证：完整219项离线测试 PASS（.tooling/evidence/src009-tests.txt），全项目 analyze No issues found；未构建或安装新包。

## SRC-010：MediaRef 解析与图片访问（2026-09-07，待真实硬验收）

状态：**IMPLEMENTED / PENDING_LIVE_VALIDATION**，不标 DONE。LightNovelSource 同时实现 SourceMedia，通过 LightNovelMedia 完成封面 / 正文插图定位和受限下载；OQ-04 的真实跨进程证据仍待用户批准 live 请求后执行。

- 每次 openMedia 从新的受限元数据请求恢复定位：cover:v1 重新读取详情 cover_url；image:v1 重新读取所属章节 body_snapshot，按相同 origin+path 摘要匹配。拒绝跨源 / 非法引用、锁定章、preview-only、缺失或冲突 locator。没有使用过期 URL、签名推算、盲试其他 host 或备用端点；locator 无匹配返回 notFound，保留失败供用户重试。
- 仅允许 www.lightnovel.fun / api.lightnovel.fun HTTPS / 443、无用户名密码 / fragment。请求目标按当前元数据解析，相对 URI 按站点根；媒体 transport 的 policy 精确限定本次 URI，maxRedirects=0，所有跳转停止。无 Cookie / Authorization；Referer 为已验证站点根组合，不声称逐字段必要性已证明。
- 元数据与图片借用同一应用调度器及45秒总 deadline；没有新增自动重试或媒体缓存文件。图片最多20 MiB且服从调用者更低 maxBytes，receive timeout30秒，限定 JPEG / PNG / WebP / GIF / AVIF MIME。MediaInfo 格式来自 HTTP MIME，不冒充完整解码验证；实际显示继续由 SourceImage 的解码边界执行。
- 沿用 NetworkTransport 有界缓冲：openMedia 成功前已接收完整且受限 bytes，关闭当次 transport；交付后按64KiB块提供只读列表，单消费者，取消发一个终止 Failure，close 幂等释放持有 bytes。此接口不是零拷贝网络流，图片磁盘缓存仍属于 CACHE-003。
- Source 拥有媒体 transport，close 取消正在进行的定位和下载；借用的全局 scheduler 不被关闭。成功交付 body 后由消费者负责关闭，清理异常只形成脱敏日志，不输出 URI / Header / body / 原始异常。

离线验收：新增 **6项**媒体测试，完整 **225项 PASS**；最终清理改动后媒体6项再次通过，analyze **No issues found**。覆盖序列化引用在新 Source 实例恢复、当前签名变化、真实自制PNG的Flutter解码、host变化 / 相对URL、锁定 / 缺locator、MIME / bytes / redirect / 取消 / 重复close。实例重建不是 OS 进程重启，合成签名变化不证明真实签名寿命。日志 `.tooling/evidence/src010-tests.txt`。

默认关闭的 `test/support/source_media_live_probe.dart` 已准备：seed 进程最多6次（详情、正文、封面重定位+GET、插图重定位+GET），restore 新进程最多4次；合计最多10次，source间隔1秒，无重试、遇任何失败即停。仅将两份无secret MediaRef保存到忽略的 `.tooling/evidence/src010-refs.json`，图片与正文只在内存使用；解码采用已有 decodeSourceImage，输出尺寸与字节统计。必须显式 SRC010_LIVE=true 和 phase 才执行，普通测试不访问源站。

本轮截至记录新增源站 HTTP=0；10次请求的异步授权问题仍待用户回答，未复用 SRC-007 的单次授权。SRC-010 / OQ-04 / TEST-001 不能仅凭离线通过解除硬门槛。iOS Level A：既有 Dart / Dio / html，无新依赖或平台分支；Android真实 codec / HTTPS设备证据归 ANDROID-002，iOS runtime DEFERRED_NO_MAC / IOS-002。

### SRC-010：真实跨进程验收补齐（2026-09-07）

用户随后明确允许原定最多10次请求；已按预算完成，Task Status 更新为 **DONE**。前述等待授权状态保留为历史记录，不代表仍未执行。

Windows 宿主分别启动两次独立 Flutter test 进程，使用正式 LightNovelSource / SourceMedia 与 decodeSourceImage。seed进程6次请求：详情、正文、封面重新定位与GET、首图重新定位与GET；成功解码后仅保存两份无secret MediaRef。seed退出后启动restore进程，读取序列化引用，没有继承任何内存映射，再用4次请求重新定位并解码。两进程分别输出 SRC010_PASS，**总计10/10次，无重试或追加访问**，同源请求启动间隔至少1秒。

| 内容 | seed | restore | 解码结果 |
| --- | --- | --- | --- |
| 封面 | 532541 bytes | 532541 bytes | 两轮固有尺寸1443×2048，实际解码成功 |
| 首张正文插图 | 310858 bytes | 310858 bytes | 两轮固有尺寸2048×829，实际解码成功 |

解码复用正式缩略图 / 像素预算，targetWidth=1024；表中尺寸为原图固有尺寸，不冒充输出缩略图大小。未将图片、正文、签名URL或用户凭据保存到磁盘。脱敏结果见 [结构化验收记录](../validation/src010-live.json)；本机日志 `.tooling/evidence/src010-live-seed.txt` 与 `src010-live-restore.txt`。现有225项离线测试和静态分析证据继续有效，本轮只运行2项显式live检查，不将其混入离线计数。

**OQ-04 本次样本的跨重启定位硬门槛 PASS**：旧无secret引用可经当前元数据恢复请求，真实图片可解码。此证据不证明所有书籍 / 图片、path永久稳定或签名实际过期后的行为；未故意等到过期或探测权限边界，host/path改变仍按失败策略停止。源站允许的长期速率和内容分发依据仍未关闭。

这是 Windows Flutter引擎与真实HTTPS的生产实现证据，不是Android模拟器/真机或iOS验证。ANDROID-002 / IOS-002继续各自验收；SRC-010对TEST-001的媒体前置现已解除，但TEST-001本身尚未执行。

## TEST-001：Android 生产 Source 端到端 Smoke（2026-09-07）

状态：**DONE / Android emulator PASS**。新增显式 SourceServices 装配，拥有共享调度器、LightNovelSource、注册表、DefaultNovelRepository 与 MemoryImageRepository；借用 CacheDatabase，构造不发请求，close 按消费者到源的顺序释放。它是可注入的生产服务工厂，没有自动替换普通开发 fixture 或宣称用户页面已接线。

经用户另行授权最多12次请求，在 MuMu 127.0.0.1:16416 执行独立 live APK。使用生产数据实现、真实 HTTPS、正式图片解码器和独立内存 SQLite；无浏览器会话、调查客户端或替代解析器。一次运行锁在网络前写入，防止重启自动重复；遇失败即停。本次 **10/12次请求，无重试**，源请求至少间隔1秒，剩余2次未使用。

| 阶段 | 实际结果 | 累计请求 |
| --- | --- | --- |
| Search | 精确匹配书31607、目标标题与作者 | 1 |
| Detail | remote详情、正确书籍身份 | 2 |
| Catalog | 四卷十章，目标章属于卷44117 | 7 |
| Chapter | 正确章309555、非空正文、4084块与14张图片引用 | 8 |
| Illustration | 首图经ImageRepository与SourceMedia重新定位，Android真实解码，固有尺寸2048×829 | 10 |
| cacheOnly复读 | 正式SQLite记录返回相同contentRevision，origin=local，零额外请求 | 10 |

截图和日志均确认 TEST001_PASS，结果见 [结构化报告](../validation/test001-android.json)；本机 `.tooling/evidence/test001-android-log.txt` / `test001-pass.png`。正文、原图和签名URL没有保存，SQLite只在内存运行，未导出或修改用户数据库。此次证明内存SQLite规范化记录读写，不补记此前MuMu磁盘重开/恢复缺口通过。

验证入口 `integration_test/live/source_smoke.dart` 默认禁用，开启命令和一次运行锁见同目录README。新增1项离线装配/所有权测试；全项目 **226项离线测试 PASS**、analyze PASS。live Debug APK 构建/安装/运行 PASS；随后普通 lib/main_dev.dart Debug 构建、安装、冷启动和开发菜单显示均通过，模拟器已恢复普通开发入口。

Phase 2生产数据链路本次样本 Gate PASS；这不代表所有书籍、真实ARM64手机性能、产品页面、离线持久图片或发布准备完成。正式搜索/详情/目录UI按相应任务实施。iOS Level A：共享Dart与既有跨平台依赖；iOS runtime保持 DEFERRED_NO_MAC / IOS-002，不能由本次Android成功替代。

搜索封面接线补正（2026-09-07）：SRC-006 当时暂不提供 cover 的限制现由已完成的 SRC-010 媒体恢复协议解除。搜索摘要按合法 bookId 提供稳定 cover:v1 引用，图片消费方按既有详情端点取得当前定位；搜索本身不增加详情请求，不从未验证的搜索封面字段推断 URL。缺失封面沿用媒体 notFound / UI失败占位处理。本轮离线验证，无新实站字段证据。
