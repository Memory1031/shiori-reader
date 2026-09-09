# PARSE-006：EPUB 图片候选与资源策略

日期：2026-09-09。承接 GAP-003/005/011，未更改 Domain、阅读进度合同或依赖。

## 图片候选（GAP-003）

原生正文、guide XHTML 封面与特殊页共用 `epubImageCandidates`：

1. picture 内位于 img 前的 source，按文档顺序尝试；接受空 type 或 PNG/JPEG/GIF/WebP，media 仅接受空值或 all/screen。不猜测 viewport 条件，不尝试 AVIF/SVG 等未支持格式。
2. img 现有 src（以及原有 SVG image href/xlink:href 路径）。
3. img srcset，按声明顺序尝试有效候选。

同一列表按声明顺序选首个存在且字节签名受支持的包内文件。w/x 用于验证正数描述符，不根据屏幕密度或 sizes 选图；这是确定性的离线兼容策略，不是完整响应式图片算法。缺失、远程或不支持格式继续尝试；越界仍拒绝。保留 URL 内逗号及一次百分号解码，支持无描述符、正整数 w 和正数 x；复合/无效描述符跳过。

每个 srcset 最多 64KiB、解析 128 次候选；每个图片消费者最多尝试 128 个候选。超过范围停止候选处理，仍受原有归档和媒体预算约束。无可用图片时原生保留占位及后文。特殊页先决定候选，再清除 source/srcset，嵌入选定字节，防止 WebView 再选图；缺失图保留 alt。两侧共享栅格字节类型识别，非标准扩展名不再令特殊页漏掉原生可识别的图片。

签名识别不是完整设备解码验收。特殊页仍有独立的 8MiB 资源预算，不承诺所有原生大图都能嵌入特殊页。

## 路径策略（GAP-005）

查阅 [EPUB 3.3 固定版本](https://www.w3.org/TR/2026/REC-epub-33-20260113/#sec-xhtml-deviations-discouraged)及 [Reading Systems 3.3](https://www.w3.org/TR/epub-rs-33/)：HTML base 属于不推荐使用的构造，并非禁止；Reading Systems 3.3 修订记录移除了必须作为 xml:base 处理器的要求。不能因此声称忽略所有 base 就完全符合各版本。

本轮决定**不新增 base/xml:base 解析**。现有 OPF、nav/NCX、图片及 CSS 继续按所在文件计算相对路径；特殊页不保留 base，也不会保留原始远程地址。依赖 base 改写才能定位的 EPUB 仍可能缺图/缺目录，这是明确限制。EPUB 2 变体也沿用该产品策略，不承诺完整 XML Base 兼容。

包根 `/OPS/...` 与宿主机绝对路径在概念上不同；当前实现统一拒绝这种绝对路径形式。本轮保持此严格限制并补拒绝测试，不误称所有包根 URL 都违反 EPUB 规范。不放宽根越界、反斜线、解码后逃逸、scheme/authority 等原有边界。

GAP-005 在本任务中完成规则核实与策略决策，**能力仍未实现**；未来若改变策略，必须同时设计 nav、原生、CSS、特殊页的基准 URL 传播及安全测试，不能仅给图片拼一个 base。

## 未声明资源（GAP-011）

保留包内存在但未列入 manifest 的图片读取，作为兼容容忍策略。与 [W3C 未声明资源测试的建议](https://github.com/w3c/epub-tests/blob/2d3b96756423189c0008eff95f0e98beda7cc5fe/tests/pkg-manifest-unlisted-resource/EPUB/package.opf)存在明确偏差，不标记官方通过。容忍只适用于受限包内资源，不扩展到外部文件或网络。

## 验证

`epub_resources_test.dart` 新增 11 项测试：密度/宽度候选、picture 过滤与优先级、缺文件回退、非标准扩展名/未声明图片、逗号、远程候选、缺图占位、绝对/越界拒绝、base 不解释、候选限额和 guide 封面。合成图片用于字节选择测试，不视为设备 codec 验证。

未运行模拟器、真机、官方 EPUB 套件或真实书源请求。旧导入不会自动重解析；获取新候选结果仍依赖后续 PARSE-005 的保留进度重解析。

最终 `flutter test test/data/local test/data/sources test/widgets/reader --reporter expanded` **262 项通过**；`flutter analyze` 无问题；`git diff --check` 通过。
