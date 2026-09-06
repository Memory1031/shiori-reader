# LightNovel.fun 源站调查

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
