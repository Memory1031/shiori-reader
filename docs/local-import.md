# 本地导入与 EPUB 兼容

## 用户流程

文件选择、系统「打开」或分享只接收文件；应用内确认后才发布到书库。导入会保存托管副本、加入书架，并用完整文件 SHA-256 去重。同名不同内容是不同书籍，相同字节重复导入不重复建书。

本地书从书架或详情移除，与本地文件管理中的删除使用同一流程；确认后删除应用内原件和解析资源，不提供撤销。单独清缓存不删除用户托管文件。删除操作清理该书托管数据、书架和进度，并失效旧会话晚写；外部原文件不动。

本地书使用 `SourceId('local')`，所有读取模式均走本地，不经过在线 Source、在线预取或可淘汰正文缓存。

## 文件与事务

`users/books/<hash>/` 保存 `original`、codec v1 的 `manifest.json` 和按内容哈希命名的媒体。暂存在 `users/import-staging/`：复制 / 哈希 → 解析与资源落盘 → 原子改名 → 数据库事务发布。失败不发布半本书；启动回收只处理确认未被用户库索引的暂存，不能把数据库读取失败当成空书库。

`LocalImportSession` 拥有暂存，`LocalBookStore` 管理文件，`LocalBookManagement` 管理删除。已发布文件损坏时保留并报错，不自动删除用户数据。存储与迁移见[数据库](database.md)。

身份不包含外部路径或临时 URI。TXT 章节以去 BOM 后、归一化前的原始 code point 起点派生；EPUB 章节以规范 spine href 派生。目录条目可附 fragment 定位 blockKey，目录层级与物理章节文件不是同一概念。

## 平台接收

| 平台 | 机制 |
| --- | --- |
| Android | ACTION_OPEN_DOCUMENT、VIEW、单文件 SEND；content URI 临时授权期间复制到 no-backup inbox，不请求所有文件权限 |
| iOS | UIDocumentPicker、安全作用域协调读取；ShareExtension 在 NSItemProvider 临时资源有效期内复制到共享 inbox |

原生入口限制单文件 128MiB、一个待确认文件；working → pending 与回执保证幂等，不覆盖已有待确认项。恢复通过 inbox 实际状态和应用恢复前台检查，不只依赖一次事件通知。

iOS Runner / ShareExtension 必须使用同一 App Group 配置（`SHIORI_IMPORT_GROUP`）及兼容签名。扩展只复制文件，不解析整本、不写 SQLite，使用跨进程锁协调；用户回到主应用确认。临时权限和共享容器能力需要真实平台配置，见[开发说明](development.md)。

## TXT

支持严格 UTF-8（有 / 无 BOM）、带 BOM 的 UTF-16 LE / BE、GB18030 / GBK。存在编码歧义时提供预览确认，不用 replacement character 静默吞错。换行归一化，保留正文空白；保守识别章节标题，无可信标题则整文件作为正文。

WHATWG 编码映射与许可保留在工程，生成工具位于 `tool/encoding/`；不通过在线猜测编码。TXT 输入上限 16MiB，最多 100000 块、10000 章。

## EPUB 普通正文

支持无 DRM 的流式 EPUB 2/3，以 OPF manifest / spine 为阅读顺序；不支持的 spine 格式可沿包内 fallback 选择 XHTML 替代，循环/断链拒绝；不按 nav / NCX 重排正文。目录可嵌套、可指向同文件 fragment，保留 `linear=no` 条目，不能把「一个文件」或「一个目录标题」直接当作用户卷数。

原生正文支持段落、标题、分隔线、换行、pre 文本、基础对齐与 em 缩进；普通 HTML 块去除源码边缘可折叠空白，保留 NBSP / 全角空格与 pre，不用源码缩进抵消正文缩进。支持 PNG / JPEG / GIF / WebP，SVG 包裹的位图可提取（支持 href 与带命名空间的 xlink:href），纯 SVG 不在兼容范围。图片缺失显示占位，不丢失前后正文。

章节开头最高级标题可提升为章节级显示，解决原书使用 h4 而未命中标题优化的问题。原生标题样式见[阅读器](reader.md)。

## EPUB 特殊短页

对实际应用了浮动、定位、变换或竖排等样式、且文本不超过 2000 字符的短页，提供受限静态 HTML 展示，适配扉页与标题设计。普通长正文仍走原生分页，不承诺完整 CSS / 固定版式支持。

- 仅允许安全元素和样式，移除脚本、表单与 iframe，关闭 JavaScript，使用严格 CSP，禁止外部请求。
- 本地图片、字体内嵌；字体单项上限 8MiB、单文档生成 HTML 上限 16MiB。
- 已导入书可从保留原件按哈希校验后派生，不要求重新导入，不改写原件；派生缓存有界。
- 通过 `LocalPagePresentationRepository` 提供可选呈现，与 `LocalNavigationRepository` 的目录能力分开；标准阅读进度继续使用本地章节身份。

## 输入边界

EPUB 输入上限 64MiB。ZIP 限制 4096 项、单项解压 16MiB、总解压 256MiB，以及膨胀比 `(压缩字节 + 1024) × 200`；校验目录 / 本地头、CRC，拒绝分卷 ZIP、ZIP64、符号链接和越界路径。合法相对 href 可在书内解析，解码一次后仍必须留在根目录。

XML 单项 4MiB、文本累计 12Mi UTF-16 单元，DOM 100000 节点 / 深度 128；目录 10000 项 / 深度 32，单章最多 100000 块，去重图片累计 128MiB。拒绝 DRM、固定版式、内部 DTD / ENTITY，不解析外部实体。

存储层另有限额：原件 128MiB、单媒体 32MiB、媒体总量 512MiB、manifest 32MiB、媒体写入 4096 项。解析限制和存储限制独立生效，不能用 ZIP 文件体积代表最终内存成本。

平台与文件样本的实际覆盖见[验收摘要](validation/README.md)，不将上述支持列表解释为所有发行商 EPUB 都已验证。

已有导入记录保存解析结果；解析器修复不会自动重写旧 manifest，相同文件再次导入也会命中去重。保留进度的重新解析已纳入 PARSE-005，尚未实现；不要将删除重导作为自动迁移方案，删除会清阅读进度。

本轮已修复空章节、自闭合脚本吞正文、SVG 特殊页位图回退、隐藏内容、受限 CSS important 与注音降级等问题。35 个文件中 34 个解析成功，1 个因加密声明继续拒绝；逐文件结果、支持边界和未做的设备验证见[兼容性核查](validation/epub-compatibility.md)，不将样本通过理解为完整兼容。

2026-09-09 结构核查新增命名空间隔离、XML 深度预算、目录分组修复与封面降级（cover-image / legacy meta / guide），231 项相关离线回归通过，详见[结构对照与支持矩阵](validation/parse-001.md)。

样式表按文档顺序加载，原生正文与特殊短页共用屏幕筛选规则（空 media / screen / all），不启用打印、alternate 或 disabled 样式；复杂媒体条件不猜测。正文语义保真与 CFI 的剩余边界见[支持范围](validation/epub-support-profile.md)。

### 图片候选与 base 边界

EPUB 支持包内 picture/source 与 srcset 候选，按固定顺序选择可用栅格图片；不根据 viewport/sizes 进行响应式选图。原生正文、guide 封面与特殊页共用候选规则。未声明在 manifest 的包内图片继续容忍；base/xml:base 仍不解释，包根绝对路径形式仍拒绝。完整规则和证据见[PARSE-006](validation/parse-006.md)。

### 解析诊断

EPUB 解析结果在 data 层附带最多 100 条固定原因码及截断标记。BookDecoder 可由调用方注入独立诊断 slot，读取最近成功解析报告；默认不保留，不写书籍文件或进度，不包含路径/正文。详见[PARSE-007](validation/parse-007.md)。
