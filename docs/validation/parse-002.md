# PARSE-002：共同正文语义与 EPUB 空白

日期：2026-09-09。

## 行为对照与取舍

| 行为 | EPUB | 在线 | 本轮处理 |
| --- | --- | --- | --- |
| 普通源空白、显式 br | 折叠源空白，保留 br | 同类规则 | 共用 ProseTextBuffer，源空白与显式换行分开处理 |
| 标题识别 | h1–h6，带 EPUB 对齐 | h1–h6，站点文本提取 | 共用级别识别，保留两端属性/文本适配 |
| pre | 保留空白 | 原先当普通文本折叠 | 两端统一保留，增加同 HTML 的块身份对照 |
| CSS white-space / visibility | 原先未支持 | 不导入出版物样式 | EPUB 新增受限属性，在线不获得 EPUB 样式或包资源能力 |
| 缩进 | 保留正文全角空格，CSS em 转 leadingIndent | 将前导全角空格转 leadingIndent | 保持明确差异，不强制统一导致历史身份变化 |
| 空段落 | 忽略纯空白段 | 保留已确认空 p | 保持原策略 |
| 图片/锚点/特殊页 | 包内资源、fragment、受限静态页 | 域名白名单、lazy src、图注 | 留在各自适配器，不抽成跨源资源解析器 |
| 遍历边界 | 容器、表格行、目录锚点及 EPUB 样式 | 站点排除标签、图注及源限额 | 两端回调复杂度不同，保留遍历器，仅抽取真实共同的文本缓冲与标题识别，避免制造泛化 DOM 框架 |

共享模块 `lib/data/html/prose_semantics.dart` 无 Flutter、网络、存储依赖。Domain/Reader 合同不变；没有重写渲染器或新增依赖。

## GAP-002 语义增强

- normal/nowrap 折叠 HTML 源空白；pre/pre-wrap 保留空格和换行；pre-line 折叠水平空白但保留换行，处理跨 span 的空白边界。
- white-space 按祖先继承，pre 标签提供默认预格式化，显式 normal 可以覆盖；保留 NBSP、全角空格。无效新属性值不覆盖此前有效声明。
- visibility 隐藏文字/媒体，子元素 visible 可以恢复；display:none、hidden 属性仍跳过子树。原生块模型不保留不可见元素的几何占位，collapse 按隐藏处理，不声称完整表格 CSS 布局。
- 用户字体、字号、页边距及段落间距仍由 Reader 设置负责；pre-wrap 与 pre 的差异在本轮仅为相同的文本保留语义，原生阅读器继续按可用宽度排版。

## 验证与进度边界

新增 EPUB 语义测试覆盖预格式化、pre-line 跨节点、br、继承覆盖、可见子节点、隐藏图片、NBSP/全角空格和无效声明；在线测试通过完整离线 API 适配器比较相同 HTML 的块身份。既有在线媒体白名单、EPUB 路径安全、段落/图文及 Reader 回归同时运行。

普通既有样本回归保持通过；新修正的 pre、white-space、visibility 内容可能改变文本或块身份，这是行为增强，不承诺重解析身份不变。旧托管 EPUB 不自动重解析，保留进度升级仍由 PARSE-005 负责。在线 pre 再抓取可出现修正后的内容身份；没有做存储迁移。

未执行模拟器、真机、真实书源请求或官方 EPUB 套件。

最终相关离线回归：`flutter test test/data/local test/data/sources test/widgets/reader --reporter expanded` **251 项通过**。`flutter analyze` 无问题；`git diff --check` 通过。
