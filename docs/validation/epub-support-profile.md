# Shiori EPUB Support Profile v1

更新：2026-09-09。根据用户提供的审计 prompt 补充全链路差距分析；采用适用建议，不照搬其另建四份文档、只读任务或完整框架要求。本文集中维护支持矩阵、剩余缺口与建议任务，避免与主计划重复。

## 成熟度与架构

当前是有合成测试和真实样本证据的轻小说流式 EPUB 阅读实现，结构基础较稳定，语义保真为受限支持；不是通用 EPUB SDK、浏览器 CSS 引擎或标准认证实现。此前 PARSE-001 的“完成”仅表示当轮结构对照收口，不表示不存在其他缺口。

数据流已经是 `book_decoder.dart → EpubZip → container → OPF manifest/spine → XHTML → ChapterContent/ContentBlock → ManagedLocalBooks → LocalSource → Reader`，不是扫描所有 HTML。导航独立于阅读顺序，同 XHTML 的多个 fragment 可以指向不同块；内部章节以 spine 文档为单位，不声称与文学章节一一对应，也不强行把 nav 分组映射成真实卷。

已检查 `epub_parser.dart`、`epub_zip.dart`、`epub_text_styles.dart`、`epub_presentation.dart`、`book_decoder.dart`、`managed_local_books.dart` 的导入/特殊页派生，以及 ContentIdentity 和本地读取/Reader 回归。普通正文由用户设置控制；特殊短页已有受限静态 HTML，这是产品已经验证过的功能，不因为参考 prompt 的“纯原生”假设将它删除。

## 支持矩阵

证据：S = epub_structure_test；B = epub_boundary_test；C = epub_compatibility_test；P = epub_presentation_test；T = epub_stylesheet_test；Z = parsers_test（均位于 test/data/local）。状态仅针对列出的行为。

| Feature | Current | Expected / Notes | Evidence | Priority |
| --- | --- | --- | --- | --- |
| ZIP / container / OPF / spine | SUPPORTED | 包内路径、CRC、限额、顺序；多 rootfile 选择首个匹配项，不提供多版本选择器 | Z/S/B | 保持 |
| EPUB2 NCX / guide / cover meta | SUPPORTED | 嵌套目录、锚点及 guide 位图/XHTML 封面 | Z/B | 保持 |
| EPUB3 nav / properties / cover-image | PARTIAL | token、前缀、空 nav 降级；读取错误不会一律静默吞掉 | S/B | 保持 |
| XHTML 文学章节映射 | PARTIAL | spine 文档为存储单元，nav 为显示层级；不合并跨文档文学章节 | Z/S | 不改身份 |
| href / fragment | SUPPORTED | 相对路径、Unicode/百分号一次解码、精确大小写、缺锚点回章首 | Z/S/B | 保持 |
| base / xml:base 变体 | NOT IMPLEMENTED | 当前以所在文档为基准；是否容忍具体变体需区分规范与兼容输入 | 源码检查 | P2 |
| p / headings / br / pre / ruby | PARTIAL | 普通段落、标题、换行、pre、基字+括注；强调/上下标仅保留文字，列表无完整编号样式 | C/P | P1 |
| semantic CSS | PARTIAL | 对齐、em 缩进、display、受限选择器及 important；非完整 cascade | C/P/T | P1 |
| 样式表媒体 / 顺序 | SUPPORTED（子集） | 本轮修复；空 media、screen、all，按 DOM 顺序；不启用 alternate/disabled，复杂条件不猜测 | T | 已修 |
| white-space / visibility | PARTIAL | PARSE-002 支持文本保留/折叠、继承与可见子节点；原生不保留隐藏元素几何占位 | epub_prose_semantics_test | 已实现子集 |
| PNG/JPEG/GIF/WebP、SVG image 包装 | SUPPORTED（解析） | 实际字节识别、缺图占位；不意味着所有图像字节都能被设备 codec 解码 | C/S/B | 保持 |
| srcset-only / picture source | PARTIAL | picture 内常规 img src 可走已有路径，PARSE-006 已支持候选，按确定性顺序选择包内栅格图，不实现 viewport/sizes 选图 | 源码检查 | P1 |
| 特殊短页 | PARTIAL | 安全静态 HTML、外部 URL/脚本受限，SVG 回原生位图；不是完整出版方布局 | C/P | 保持 |
| 进度与重解析 | PARTIAL | 当前 manifest 稳定读取；重解析迁移未实现 | local_reading / domain identity | PARSE-005 |
| 诊断信息 | PARTIAL | PARSE-007 已有有界原因码快照；不持久化、无 UI，非完整资源诊断 | book_decoder / parser | P2 |
| DRM / 固定版式 / 脚本互动 / SMIL | OUT OF SCOPE | 拒绝或静态降级，不新增播放器或浏览器阅读架构 | Z/C/P | 不做 |

## 本轮已修复：EPUB-GAP-001

P1 / CSS / S：样式表先读所有 link 再读 style，破坏同优先级源顺序；忽略元素 media 可能把打印专用隐藏规则应用到屏幕。影响使用打印样式或交错外链/内联样式的 EPUB，正文可能被隐藏，居中/缩进可能错误。

独立实现 `epubDocumentStylesheets`，供原生正文与受限特殊页共用，保留文档顺序并筛选屏幕样式；识别 rel token，跳过 alternate/disabled。没有扩展 Domain 或改变用户字体、页边距设置。5 项合成测试修复前全部失败，修复后通过。

## 剩余优先缺口与可领取任务

以下为代码可见的缺口，不声称已经在用户书籍上发生；无复現样本的复杂行为先补测试再实施。不把所有问题列为 High。

| ID / Task | Problem / Affected EPUBs | Suggested fix & tests | Depends / Files / Complexity |
| --- | --- | --- | --- |
| EPUB-GAP-002 / SEMANTIC-SPACE | P1 Medium：CSS white-space 尚未参与正文缓冲，带 pre-wrap/pre-line 的诗歌、短信段落可能被折叠；visibility 与 display 也不等价 | 先定义 normal/pre/pre-wrap/pre-line 的文本规则和继承；测试换行、全角空格、跨 span、br、隐藏父/可见子；验证块身份变化，不实现完整 CSS | PARSE-002 行为对照；text_styles/parser/tests；M |
| EPUB-GAP-003 / IMAGE-CANDIDATES | P1 Medium：仅 srcset/source 的插图没有候选选择 | 只选包内受支持图片，明确 src 优先/候选顺序；测试相对路径、密度/宽度描述符、逗号、缺失候选、远程/越界拒绝；保持局部占位 | parser/presentation/tests；M |
| EPUB-GAP-004 / POSITION-MIGRATION | P1 High：重解析可能改变 blockKey，旧导入不自动获得修复 | 保留原件/旧结果/进度，按章节、文本与比例迁移，失败原子回退；图片、重复段落、拆并块及晚写必测 | 复用 PARSE-005，不另造迁移；managed_local_books/progress/tests；L |
| EPUB-GAP-005 / BASE-RESOLUTION | P2 Medium：base/xml:base 不参与资源解析，带这些变体的书可能缺图/目录错位 | 先核实各 EPUB 版本规范与真实需要，不全局拼 base；如采纳，统一 native/presentation/nav/CSS，覆盖嵌套、远程、逃逸与同文档 fragment | 资源策略设计；parser/presentation/tests；M |
| EPUB-GAP-006 / DIAGNOSTICS | P2 Low：无法汇总缺锚点/缺图/不支持格式等降级原因 | data 层有界诊断，不记录正文、凭据或本机路径；区分规格无效/可容忍/安全拒绝；避免一发现问题就改存储合同 | book_decoder/parser/tests；M |

优先建议先做 PARSE-002 的语义对照，把 SEMANTIC-SPACE 作为明确的后续增强目标；不要在抽取共享代码时无意改变 EPUB 与在线两侧行为。扩展审阅建议优先完成 GAP-007/008/009 的局部修复；详情及 GAP-010～012 见 [第三方复核](epub-reference-audit.md)。以上为建议，未启动这些任务。

## 规范、容忍与安全

- 严格拒绝：包外访问、根越界、CRC/归档结构错误、预算超限、受保护内容；不为了与其他 Reader 一致降低安全边界。
- 可容忍：无 TOC 生成 spine 目录、缺 fragment 回章首、缺图保留占位、封面按声明降级。mimetype 打包容忍已有专门测试。
- 不猜：不随意把任意二进制 MIME 当 XHTML，不把第一张图片无条件当封面，不声称错误元数据必然能恢复。
- 未发现可证实的任意文件读取/脚本执行漏洞；这不是安全认证。继续关注累计解析预算、CSS 选择器复杂度、图像解码内存与特殊页边界，不能仅凭本轮 UT 声称排除资源耗尽。

扩展审阅还发现非文本导航标签、可选目录错误恢复、元数据空白及重复 spine 身份等缺口，见第三方复核。无数据支持对这些问题估计发生率。

## CFI 与 Domain 决策

当前 blockKey/fraction 足以承载已保存内容的续读；重新解析改变文字、对齐/缩进或块划分时，语义摘要可能变化，不能保证位置精确恢复。CFI 提供基于 EPUB DOM 的定位，无法独自解决 DOM 重组与原生块降级映射。

现在不引入 CFI：需要长期维护原始节点/偏移到 ContentBlock 的映射、兼容旧进度、处理清理前后 DOM 差异，并验证双向转换。先完成 PARSE-005。未来有跨阅读器导入书签需求时，可作为 EPUB data 层定位信息，不泄漏到通用 Reader。

当前 ContentBlock 无需为本轮修复改变。强调、原生 ruby 等富文本能力只有在在线与本地都需要时另做共享语义设计；OPF、href、CSS selector 留在 data 层。

## 参考与证据边界

2026-09-09 已补齐 Readium Swift/Kotlin、epub.js、foliate-js、calibre、EPUBCheck 规则及 W3C 选取用例的定向审阅；固定提交、源码链接、许可、采纳边界及新增 GAP-007～012 见 [第三方复核](epub-reference-audit.md)。epub_parser / epubx / EbookLib 的既有证据见 [PARSE-001](parse-001.md)。覆盖所有列出项目的相关模块，不代表逐行审计全部仓库或运行官方套件。

上一轮代码修复验证：`flutter test test/data/local test/data/sources test/widgets/reader --reporter expanded` **236 项通过**；`flutter analyze` 无问题。本次扩展审阅仅更新文档，没有重跑这些检查或设备验收；新增缺口尚未修复。未重扫真实样本，未启动下一开发任务，暂存区保持原样。

### 后续局部修复状态

GAP-007/008/009 已实现并完成 242 项相关离线回归和静态分析，见[局部验收](epub-reference-audit.md#局部修复验收gap-007--008--009)。新增代码不改变正文块身份，不自动重解析旧导入；设备验收未执行，条目级诊断汇总仍待 GAP-006。

PARSE-002 已完成 GAP-002 的受限语义增强，详细差异与身份边界见[正文语义报告](parse-002.md)。后续执行以主计划为准。

PARSE-006 已完成图片候选支持与路径策略决策，详见[资源策略报告](parse-006.md)。GAP-005 的 base 解释仍未实现；GAP-011 明确保留未声明包内图片容忍，不声称符合该官方建议。

PARSE-007 已完成固定原因码与每次 100 条上限的 data 层诊断快照，生命周期及明确未覆盖项见[诊断报告](parse-007.md)。不持久化、不改变正文身份，未新增诊断 UI。
