# EPUB 第三方源码与规则复核

日期：2026-09-09。范围：补齐用户提供清单的相关关键模块，回查 Shiori 实现，形成后续任务依据。**这是定向源码审阅与测试断言对照，不是逐行审计所有仓库，也不是官方兼容性认证。** 本轮只更新文档，不改生产代码、不重复扫描用户真实书籍、不启动模拟器。

## 固定参考版本及采纳边界

此前 epub_parser 3.0.1、epubx 4.0.0、EbookLib 0.20 的源码位置、许可及测试证据沿用 [PARSE-001](parse-001.md)，不声称本轮重新审计这三个项目的最新版本。它们与下表共同覆盖用户清单。未复制第三方实现、未新增依赖；若以后复制代码，需按具体文件与依赖重新核验许可。

| 项目 | 已查关键入口 | 许可 | 对 Shiori 的结论 |
| --- | --- | --- | --- |
| Readium Swift | [OPF / manifest / fallback](https://github.com/readium/swift-toolkit/blob/dcca0e9c2b51ecfff178d9c87ba8c57705fbadd4/Sources/Streamer/Parser/EPUB/OPFParser.swift)；[nav → NCX 降级](https://github.com/readium/swift-toolkit/blob/dcca0e9c2b51ecfff178d9c87ba8c57705fbadd4/Sources/Streamer/Parser/EPUB/EPUBManifestParser.swift) | BSD-3-Clause | 拆开阅读顺序、资源和目录；可选目录读失败返回空集合。fallback 还服务图像阅读目标，不直接照搬到仅接受 XHTML 的 Shiori。 |
| Readium Kotlin | [readingOrder / fallback](https://github.com/readium/kotlin-toolkit/blob/fc5c2bb31053b551deb4e63e00fe6ad7484c2812/readium/streamer/src/main/java/org/readium/r2/streamer/parser/epub/ResourceAdapter.kt)；[导航层级与标签](https://github.com/readium/kotlin-toolkit/blob/fc5c2bb31053b551deb4e63e00fe6ad7484c2812/readium/streamer/src/main/java/org/readium/r2/streamer/parser/epub/NavigationDocumentParser.kt) | BSD-3-Clause | 区分 linear 与辅助资源，保留 fallback 链和目录层级；不引入远程资源容器，不把 DOM 定位直接作为原生块身份。 |
| epub.js | [manifest / spine / cover](https://github.com/futurepress/epub.js/blob/eee359d0790002115a1156a9833c54f4bcd44c1d/src/packaging.js)；[locations / CFI](https://github.com/futurepress/epub.js/blob/eee359d0790002115a1156a9833c54f4bcd44c1d/src/locations.js) | BSD-2-Clause | 包结构和浏览器排版分离；locations 按 linear section 的 DOM 文本生成 CFI，不是可直接复用的重解析进度迁移。检查的 manifest 映射没有保留 fallback 字段，不能将它当作所有功能的正确答案。 |
| foliate-js | [Resources / sections / nav](https://github.com/johnfactotum/foliate-js/blob/78914aef4466eb960965702401634c2cb348e9b1/epub.js)；[CFI](https://github.com/johnfactotum/foliate-js/blob/78914aef4466eb960965702401634c2cb348e9b1/epubcfi.js) | MIT | spine 构造 sections，nav/NCX 有局部降级；导航源码仍有非文本标签 TODO，证明成熟库也有遗漏。借鉴边界，不移植整套 DOM renderer。 |
| calibre | [manifest / spine / TOC](https://github.com/kovidgoyal/calibre/blob/2907fa931b22564cb0bdcf3656888c66515473fa/src/calibre/ebooks/oeb/reader.py)；[EPUB 输入与封面](https://github.com/kovidgoyal/calibre/blob/2907fa931b22564cb0bdcf3656888c66515473fa/src/calibre/ebooks/conversion/plugins/epub_input.py) | GPL-3.0（见仓库许可） | 容忍缺失资源、推断 MIME、补充链接文档等策略服务转换流程；封面处理还区分 for_viewer。不可照搬自动改阅读顺序、移除封面或猜测格式；只独立借鉴测试场景。 |
| EPUBCheck | [OPF 规则](https://github.com/w3c/epubcheck/blob/50a0a676aea41b7b9a5033a2a1cb93bf548ef023/src/main/java/com/adobe/epubcheck/opf/OPFChecker.java)；[导航 Schematron](https://github.com/w3c/epubcheck/blob/50a0a676aea41b7b9a5033a2a1cb93bf548ef023/src/main/resources/com/adobe/epubcheck/schema/30/epub-nav-30.sch) | BSD-3-Clause（固定提交根 LICENSE.md） | 验证出版物是否合法，不能替代阅读器容错策略；重复 spine 检查有 EPUB 2 版本条件，不能脱离分支解读。 |
| W3C epub-tests | [重复 spine 用例](https://github.com/w3c/epub-tests/blob/2d3b96756423189c0008eff95f0e98beda7cc5fe/tests/pkg-spine-duplicate-item-rendering/EPUB/package.opf)；[未声明资源用例](https://github.com/w3c/epub-tests/blob/2d3b96756423189c0008eff95f0e98beda7cc5fe/tests/pkg-manifest-unlisted-resource/EPUB/package.opf) | W3C Software and Document License（测试文档） | 按用例内版本、规范引用和实际断言逐条取证。当前网站入口版本不等于所有用例的适用版本；本轮没有执行官方套件。 |

固定提交（链接均使用该提交，不用移动分支）：

- `readium/swift-toolkit`：`dcca0e9c2b51ecfff178d9c87ba8c57705fbadd4`。
- `readium/kotlin-toolkit`：`fc5c2bb31053b551deb4e63e00fe6ad7484c2812`。
- `futurepress/epub.js`：`eee359d0790002115a1156a9833c54f4bcd44c1d`。
- `johnfactotum/foliate-js`：`78914aef4466eb960965702401634c2cb348e9b1`。
- `kovidgoyal/calibre`：`2907fa931b22564cb0bdcf3656888c66515473fa`。
- `w3c/epubcheck`：`50a0a676aea41b7b9a5033a2a1cb93bf548ef023`。
- `w3c/epub-tests`：`2d3b96756423189c0008eff95f0e98beda7cc5fe`。

## 全链路结论

| 环节 | 对照后的判断 | 处理方向 |
| --- | --- | --- |
| 容器 / OPF | 现有结构读取、路径限制和预算不是主要短板；calibre 的修复策略远宽于本项目需要 | 保持明确入口，不扫描任意 OPF/HTML 猜书，不复制转换器修书策略 |
| manifest / fallback | 外来格式回退已有独立测试；重复引用被统一拒绝过于严格 | EPUB 3 重复 spine 需单独设计 occurrence 身份，不能只删除去重校验 |
| nav / NCX | 空目录降级已做，但缺文件/解析异常仍可能使整本失败；非文本标签只取 text 会丢 alt 信息 | 优先补可选导航局部恢复与标签规范化，安全/预算异常仍传播 |
| linear / 内部链接 | 保留辅助内容不等于支持点击进入辅助内容；当前普通正文没有完整链接交互语义 | 将连续阅读顺序、目录跳转、正文链接激活分开验收 |
| 元数据 | title/creator 只 trim，内部换行/连续空白未规范化；更丰富语言/角色等也不是完整支持 | 优先修显示字段空白；暂不扩展完整出版物元数据模型 |
| HTML / CSS / 图片 | 原生正文与浏览器方案能力不同；white-space、visibility、srcset 仍是明确缺口 | 延续 GAP-002/003；不能以成熟库用浏览器就要求重写 Reader |
| 定位 | Readium positions 可按资源长度估算；epub.js/foliate CFI 依赖 DOM 节点和偏移 | 均不能直接保证重解析后续读准确，先做 PARSE-005 的迁移与回退 |
| 诊断 / 安全 | validator 的无效输入与 reader 的可容忍输入不相同 | 记录降级原因；不为容错吞掉归档越界、超限、受保护内容错误 |

CFI 补充依据：Readium Swift `EPUBPositionsService.recommended` 使用 archive entry length / 1024 的位置策略；epub.js `Locations.generate` 遍历 linear sections，CFI 的 fromRange/toRange 依赖 DOM。位置列表、视觉页码、原生 blockKey 是不同概念。没有证据支持现在以 CFI 替换现有进度模型。

## W3C 用例断言映射

下表是读取固定版本测试源后的**静态评估**；没有将官方 EPUB 运行于 Shiori，也没有官方 pass/fail 结果。18 个选取场景覆盖导航、包结构、资源、XML 和网络；脚本测试本身对本项目不适用，但可参考其等价路径边界。

| 上游用例 ID | 断言 / 对现状的判断 | 后续 |
| --- | --- | --- |
| nav-activation | 目录激活应到达对应内容；已有目录/fragment 测试，但不等于本官方用例通过 | 复用合成用例补齐跳转边界 |
| nav-non-text_img / nav-non-text_img_title | 非文本目录仍需可理解标签；目前 `.text` 不读取 img alt，会退到章节名 | GAP-007 |
| nav-spine_in-spine-hidden-toc-css | 原生目录保留隐藏条目，正文中的目录遵守隐藏规则；现有两条路径方向一致 | 补明确双路径断言 |
| ocf-package_multiple | 默认选择首个 rendition；已有 container 选择测试 | 不新增多版本选择 UI |
| ocf-url_parse-leaking-relative / ocf-url_parse-path-absolute | 原用例用脚本检查 URL；本项目不支持脚本，根相对 URL 也不能简单等同宿主绝对路径 | 原用例 N/A；保持当前策略并在 GAP-005 设计时区分包根与宿主根 |
| pkg-manifest-unlisted-resource | 用例建议不显示未列入 manifest 的图；当前可按包内路径读取 | GAP-011：明确“容忍未声明包内图片”是支持策略偏差，非规范通过 |
| pkg-meta-whitespace | 元数据首尾及内部空白规范化 | GAP-009 |
| pkg-spine-duplicate-item-rendering | EPUB 3 同一资源出现三次应呈现三次；本项目目前拒绝重复路径 | GAP-010；用例标记 3.3，EPUBCheck 的重复拒绝只针对 EPUB 2，无规则冲突 |
| pkg-spine-nonlinear-activation | 点击正文链接进入辅助文档；仅把 linear=no 放在连续顺序不等价 | GAP-012 |
| pkg-spine-order | 按 spine 顺序，不按文件名排序 | 现有测试覆盖同类行为 |
| pkg-title-order | 多个标题时采用首个；现有实现方向一致 | 元数据测试补充首个非空/多标题策略 |
| pub-foreign_bad-fallback / pub-foreign_json-spine | 外来 spine 资源需可用回退；无可用内容不可伪装成功 | 现有链/循环/缺失测试；不声称官方通过 |
| pub-xml-external-id | 不解析外部实体；当前拒绝 ENTITY 输入是更严格策略 | 保持安全，不把拒绝当作完整 XML 兼容 |
| pub-xml-non-validating_unclosed | 用例要求报告 XML 错误；当前 XHTML 采用容错 HTML 解析 | 记录容错偏差，避免突然拒绝已兼容的书 |
| sec-untrusted-consent_network | 未获同意不访问远程资源；本地导入目前禁止远程取资源 | 静态边界一致，未执行网络行为验收 |

## 新增任务（未实施）

| ID | 优先级 / 影响 | 实施与验收要求 |
| --- | --- | --- |
| EPUB-GAP-007 / NAV-LABELS | P1 / 图片目录标题丢失或被章名替代 | 规范化标签空白，按明确语义提取 alt/可访问标签，避免文本重复；覆盖混合文本、纯图片、空标签和分组。不要把任意 title 属性一律覆盖可见文字 |
| EPUB-GAP-008 / OPTIONAL-NAV | P1 / 正文有效却被损坏的可选目录阻断 | 缺 nav 文件/无法解析的 NCX 可降级到后备目录或 spine；只恢复指定错误，预算/路径安全错误不吞；保留有界诊断 |
| EPUB-GAP-009 / METADATA-SPACE | P2 / 书名、作者含排版换行和重复空白 | 按元数据规则折叠空白，不将正文全角空格规则混入；测试跨 XML 文本节点、多标题、多作者 |
| EPUB-GAP-010 / SPINE-OCCURRENCE | P1 / 合法 EPUB 3 重复资源被拒 | 分离资源身份与阅读顺序 occurrence；定义目录指向哪次出现、续读/重解析映射，保留 EPUB 2 版本规则；依赖 PARSE-005 身份设计，不做快速去重或简单删校验 |
| EPUB-GAP-011 / MANIFEST-POLICY | P2 / 容忍未声明图片与规范测试建议不同 | 先明确保留容忍还是严格声明；原生与特殊页一致，补包内未声明图片测试。不以此推断能访问宿主文件 |
| EPUB-GAP-012 / AUXILIARY-LINKS | P2 / 正文脚注及辅助页面链接不能等同目录跳转 | 与 Domain/Reader 合同一起设计内部链接、返回位置和非线性顺序；先做失败用例，不因本轮审计直接扩展模型 |

建议先处理 GAP-007/008/009（局部且可独立验证），然后推进已规划的共享语义及 GAP-002/003；GAP-010 与 PARSE-005 联合设计。GAP-005/011 是策略决策，GAP-012 是交互语义，不能混在解析重构中悄悄修改。

## 验证边界

本轮只核查源码、规则、测试断言和本地实现，检查文档差异及引用路径；未重新运行 Flutter 测试、未运行 EPUBCheck/W3C 官方套件、未做 Android/iOS 运行验收。此前 236 项测试及 analyze 证据仍属于上一轮修复，不覆盖这里新发现的缺口。没有修改或提交暂存区。

## 局部修复验收：GAP-007 / 008 / 009

2026-09-09 用户授权后完成：

- 导航标签支持混合文本、img alt、aria-label 和换行空白；不重复拼入被可访问标签替代的子文本，不以 title 属性覆盖正文标签。保持目录层级与 fragment。
- 非 spine 的可选 nav 文件缺失可继续 NCX；NCX 缺失、XML 格式错误或非 NCX 根可退到 spine。HTML nav 沿用容错解析，空目录仍走原有降级。ZIP 校验、实体声明、路径越界与预算错误不捕获。作为 spine 正文的文件仍是必需内容。
- title / creator 折叠 XML 空白，保留全角空格等非 XML 空白；正文、块身份与 synopsis 不变。

新增 `epub_navigation_recovery_test.dart` 6 项测试覆盖替代标签、缺文件、坏 XML、实体与越界拒绝、深度预算及正文身份不变。`flutter test test/data/local test/data/sources test/widgets/reader --reporter expanded` **242 项通过**；`flutter analyze` 无问题，`git diff --check` 通过。未运行模拟器、真机或官方套件。

条目级诊断汇总仍归 GAP-006，当前没有新增诊断持久化合同。旧导入不自动重解析，本轮不会迁移旧阅读记录；保留进度重解析仍待 PARSE-005。GAP-010～012 及其余后续任务未启动。
