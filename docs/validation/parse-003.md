# PARSE-003：TXT 编码、结构与身份

日期：2026-09-09。完成 003-A～D；不以自动命中率为目标，不新增生产依赖，不改变 16MiB 导入上限。

## A：参考矩阵与基线

| 参考 / 固定版本 | 实际查阅模块与许可 | 维护 / 成本 / 选择 |
| --- | --- | --- |
| [calibre 2907fa9](https://github.com/kovidgoyal/calibre/blob/2907fa931b22564cb0bdcf3656888c66515473fa/src/calibre/ebooks/conversion/plugins/txt_input.py) | TXTInput、txt/processor.py 的 detect_paragraph_type、conversion/preprocess.py 的 DocAnalysis；GPLv3 | 成熟转换流程。参考分层分析和整书统计；不照搬硬换行合并、实体替换或 decode(...,'replace')，后者违反本项目不吞字原则。未复制实现 |
| [uchardet 用户提供镜像 bdfd611](https://github.com/fstudio/uchardet/blob/bdfd6116a965fd210ef563613763e724424728b7/src/nsUniversalDetector.cpp) | HandleData / DataEnd、uchardet.cpp；文件头 MPL1.1/GPL2+/LGPL2.1+ 选择许可 | 此镜像提交日期 2018-09-26，不能当作当前上游维护情况；官方站读取受阻。参考 BOM/候选评分分离，不集成 C++/FFI，不把最大分值当真值 |
| [ICU 2ebc705](https://github.com/unicode-org/icu/blob/2ebc7054cdfd593baf846c8e604bca5d1dd91bb6/icu4c/source/i18n/csdetect.cpp) | ucsdet.cpp / csdetect.cpp 的 detectAll；Unicode License V3（该提交 LICENSE） | 固定提交 2026-09-08；遍历识别器、保留非零匹配并排序。仅参考设计，避免跨平台原生库/包体成本；不移植整套语言统计模型 |
| [flutter_chardet 1.0.2](https://pub.dev/packages/flutter_chardet/versions/1.0.2) | lib/flutter_chardet.dart、native_detector 与 pubspec；MIT（原生材料另计） | detectAll / confidence + charset_converter。声明 Dart ^3.12.1、Flutter >=3.41.0，**不兼容当前 3.10.3/3.38.4**；未为 benchmark 升级或覆盖约束 |
| [flutter_charset_detector 6.0.0](https://pub.dev/packages/flutter_charset_detector/versions/6.0.0) | Dart 平台转发；Android 4.0.0 Kotlin 插件、Darwin 1.3.0 Swift 插件；主包 MPL2.0 | SDK 下限允许当前工具链；Android 用 juniversalchardet 2.5.0，Darwin 用 UniversalDetector/NSString，不能保证相同猜测/解码行为。未引入，也未声称已做双端运行 benchmark |
| [charset_codec 0.1.1](https://pub.dev/packages/charset_codec/versions/0.1.1) | codec/impl.dart、mbcs.dart 的严格 decodeMultibyte、增量 pending/close；MIT + CPython notices | Dart ^3.11.0，当前 SDK 不满足；含 native asset/Rust hook 依赖，但所查 GB18030 路径有 Dart 实现，不能笼统称全部原生解码。参考严格解码和结尾残字节检查，不升级依赖来测 |

所有包读取发布归档中的 pubspec/源码/许可证，未把 README 自报 benchmark 当作本项目证据。ICU 的[官方说明](https://unicode-org.github.io/icu/userguide/conversion/detection)明确探测依赖统计，不是编码证明。本轮没有需要 KOReader/FBReader/Librera 解决的特定剩余行为，因此未继续泛扫阅读器源码。

现有基线已具备严格 UTF-8/UTF-16/GB18030、用户编码预览、code point offset 和保留原文行。真正缺口是仅头部预览、无 BOM UTF-16 入口、过宽标题尾部识别；不是需要替换整个 decoder。

## B：编码与预览

- BOM 优先；完整输入严格解码后才出现候选。UTF-8/GB18030 结果不同时仍要确认；不以首部相同或单次 detector guess 自动导入。
- 无 BOM UTF-16 只在有限前缀有明显零字节偏向时增加 LE/BE 候选，之后全量严格验证，仍需确认。无此证据的纯中文 UTF-16 可手动选择，不为了覆盖率把所有偶数字节都猜成 UTF-16。非法 surrogate/尾部残字节仍失败。
- 600 code points 以内原样预览；更长文本取头/中/尾各 198 code points，以换行省略号分隔，总计 600 code points。不切断 emoji/扩展汉字，不把预览采样回写正文。当前不额外采标题附近，头中尾已解决 ASCII 前缀遮蔽歧义问题。
- 预览面板去除八行截断，使用已有滚动容器完整展示有界样本。没有新翻译文案；编码 override、失败重试与确认流程保持原合同。
- intake 不再一概拦截 NUL；二进制判定由严格解码负责，纯 NUL 数据仍拒绝且不发布书籍。

## C：保守章节候选

独立 txt_headings.dart 逐行扫描；记录 UTF-16 起止索引仅用于 substring，绝不作为持久身份。只对 <=110 code units 的行执行标题模式，trim 后上限 100，避免长行正则。

候选按编号/命名标题两类处理，支持中/日数字与章/话/卷，以及序章、特典、间章、幕间和英文 Chapter/Part/Volume/Prologue/Epilogue。带正文标点或句子尾部的行拒绝；明确标题（无尾部或有分隔符）可独立成立，保留合法短章、单章和重复编号。

无分隔符的附加标题仅在前后空行、同类重复出现及候选密度足够低时采纳，否则留作正文。没有把编号递进当硬条件：已有 fixture 包含重复及非单调编号。没有新增置信度 UI，也不承诺识别所有无标点句子。所有未采纳标题仍是原文，不删除内容。

扫描、候选统计和最终建模分开，每阶段线性/有界；100000 行、10000 章限制保留。文件中间 BOM、空行及行末字符不被结构分析吞掉。

## D：身份与性能

章节身份继续使用去文件头 BOM 后、换行规范化前的 `original.runes.length` 累计值。新增混合 emoji、扩展汉字、CRLF 与 UTF-16 测试验证偏移。输出 Domain 仍按既有合同规范化换行；原始身份计数不改。修改文件字节或新的启发式切分可能改变章键，旧导入不自动重解析，迁移仍归 PARSE-005。

[基准工具](../../tool/txt_benchmark/README.md)在改动前后分别执行，实际 Dart 3.10.3、macOS 26.3.1 arm64、VM JIT，独立进程；纯 Dart 运行绕过无关 native hooks。没有借此改 SDK 或依赖。完整数据见 [JSON](txt/benchmark.json)。预算在基线之后、实现前固定：每阶段 <=5s、进程峰值 <=512MiB。

| 样本 | 改前 decode/probe/parse ms | 改后 decode/probe/parse ms | 改后峰值 bytes |
| --- | --- | --- | --- |
| 1MiB 分行 | 32 / 40 / 53 | 32 / 55 / 54 | 208715776 |
| 10MiB 分行 | 350 / 901 / 326 | 311 / 782 / 260 | 276103168 |
| 16MiB 分行 | 700 / 1079 / 407 | 497 / 1243 / 419 | 324321280 |
| 1MiB 单行 | 30 / 37 / 33 | 30 / 51 / 33 | 208060416 |
| 10MiB 单行 | 287 / 338 / 206 | 427 / 783 / 211 | 260554752 |
| 16MiB 单行 | 477 / 1008 / 308 | 468 / 1197 / 327 | 292978688 |

全部在预算内。parse 含再次解码；峰值包含 VM/JIT/输入生成，不是手机、单阶段或整个 UI 导入峰值。数据为单次观测，不宣称提速；多位置预览允许有限额外扫描。编码正确性用中文/GB18030/UTF-16 fixtures 验证，表内性能样本为精确字节大小的 ASCII。超限与取消沿用生产回归，不支持 50MiB。

## 验证结果与边界

2026-09-09：`flutter test test/data/local test/data/sources test/widgets test/features/import --reporter expanded`，393 项全部通过。修正三处静态风格提示后，`flutter analyze` 无问题；修正仅涉及空值集合语法、花括号和基准工具 stdout 输出。

新测试覆盖预览后部歧义、无 BOM LE/BE、正文假标题、密集低置信度候选、中日英短章、附加标题上下文、supplementary Unicode 身份、完整导入确认和二进制拒绝；原有严格编码、GB18030、多换行、超长单行、取消及编码重试测试继续运行。

未执行真机、模拟器、第三方插件 Android/iOS benchmark；SDK 不兼容候选未强制安装。没有声称低置信度判断消除所有误识别，也没有修改旧导入内容。
