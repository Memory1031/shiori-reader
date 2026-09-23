# 解析器参考来源

固定于 2026-09-08～09 的研究记录，仅对照相关模块和行为；未复制第三方实现、未新增生产依赖，未运行全部官方套件。不是最新版本调查或标准认证。当前行为见[支持矩阵](../local-import.md#解析支持矩阵)。

## Dart 与 Python EPUB 库

2026-09-09。对照官方发布归档 [epub_parser 3.0.1](https://pub.dev/packages/epub_parser/versions/3.0.1)，归档 SHA-256：`a620d67dd1de88ca91e732e95faece9b4c673b7875599359e76c966367158868`。MIT，Copyright (c) 2022 Tran Manh。只参考行为、独立实现，不复制上游代码，不新增依赖。

下列源码路径相对上游 `lib/src/`。

| 对照项 | 上游位置与行为 | Shiori 决定 |
| --- | --- | --- |
| OPF / manifest / spine | `readers/package_reader.dart:59,326,386` 按直属节点读取章节列表 | 修复跨层搜索误收扩展节点；限定 OPF 子节点及元数据范围，拒绝缺失/重复结构和空 ID/href。保留现有阅读顺序与身份算法 |
| nav / NCX | `readers/navigation_reader.dart` 按 EPUB 版本选择目录；nav properties 使用完整字符串匹配 | 保留 Shiori properties token 集合、嵌套及 fragment 块定位；补充合法前缀别名。独立兼容策略：nav 没有可用条目时再读 NCX；不吞掉读取/安全错误 |
| 章节顺序 | `readers/chapter_reader.dart` 从导航递归生成章节 | 保留 spine 阅读顺序，目录可独立排序，同文档多锚点不复制章节 |
| 资源 / WebP | `readers/content_reader.dart:97` 不把 WebP 分类进 Images，但二进制仍在 AllFiles | 不照搬 MIME 分类；保留实际字节识别 PNG/JPEG/GIF/WebP、摘要去重及图片限额 |
| 路径 | `utils/zip_path_utils.dart` 拼接路径，部分读取点 decodeFull / 忽略大小写 | 保留包内 POSIX 规范化、一次解码、精确大小写、根越界/反斜线/外部地址拒绝；不采用宿主路径 API |
| 错误与限额 | 上游主要抛通用异常，没有等同 Shiori 的归档/文本预算 | 保留现有 ZIP/XML/深度预算与 DRM/固定版式拒绝，不扩大支持范围 |

- epubx 4.0.0：MIT，Copyright (c) 2017 Colin Nelson；官方发布归档 SHA-256 `0ab9354efa177c4be52c46f857bc15bf83f83a92667fb673465c8f89fca26db3`。`lib/src/readers/package_reader.dart` 的 manifest/spine 与 epub_parser 对应实现高度相似；`navigation_reader.dart:203` 的宿主 `path.normalize` 不采用。`book_cover_reader.dart:16` 的 legacy cover 选择促成封面失败降级测试，但不采用其绑定 Images 分类和整张图片解码的做法。
- [EbookLib 0.20 源码](https://github.com/aerkalov/ebooklib/blob/v0.20/ebooklib/epub.py)：`_load_metadata:1483` 按命名空间归类、`_parse_ncx:1614` 限定 NCX 命名空间、`_load_spine:1699` 保留 linear、`_load_guide:1718` 保存 guide。借鉴行为检查点，未复制 AGPL 代码。它的 nav `@*='toc'` 选择不采用，Shiori 保留语义命名空间与 token 判断。
- fallback 遍历独立依据 EPUB 3.3 §3.5.1 实现；不把库仅保存 fallback 字段当作支持完整 fallback 渲染的证据。仅为不支持的 spine 类型寻找本地 XHTML/text-html 替代，拒绝遍历中的循环/断链；被选中 XHTML 的原有章节身份算法保持不变，原目标路径作为目录别名。不会为远程资源发起请求。

## 阅读引擎与规范工具

| 项目 | 已查关键入口 | 许可 | 对 Shiori 的结论 |
| --- | --- | --- | --- |
| Readium Swift | [OPF / manifest / fallback](https://github.com/readium/swift-toolkit/blob/dcca0e9c2b51ecfff178d9c87ba8c57705fbadd4/Sources/Streamer/Parser/EPUB/OPFParser.swift)；[nav → NCX 降级](https://github.com/readium/swift-toolkit/blob/dcca0e9c2b51ecfff178d9c87ba8c57705fbadd4/Sources/Streamer/Parser/EPUB/EPUBManifestParser.swift) | BSD-3-Clause | 拆开阅读顺序、资源和目录；可选目录读失败返回空集合。fallback 还服务图像阅读目标，不直接照搬到仅接受 XHTML 的 Shiori。 |
| Readium Kotlin | [readingOrder / fallback](https://github.com/readium/kotlin-toolkit/blob/fc5c2bb31053b551deb4e63e00fe6ad7484c2812/readium/streamer/src/main/java/org/readium/r2/streamer/parser/epub/ResourceAdapter.kt)；[导航层级与标签](https://github.com/readium/kotlin-toolkit/blob/fc5c2bb31053b551deb4e63e00fe6ad7484c2812/readium/streamer/src/main/java/org/readium/r2/streamer/parser/epub/NavigationDocumentParser.kt) | BSD-3-Clause | 区分 linear 与辅助资源，保留 fallback 链和目录层级；不引入远程资源容器，不把 DOM 定位直接作为原生块身份。 |
| epub.js | [manifest / spine / cover](https://github.com/futurepress/epub.js/blob/eee359d0790002115a1156a9833c54f4bcd44c1d/src/packaging.js)；[locations / CFI](https://github.com/futurepress/epub.js/blob/eee359d0790002115a1156a9833c54f4bcd44c1d/src/locations.js) | BSD-2-Clause | 包结构和浏览器排版分离；locations 按 linear section 的 DOM 文本生成 CFI，不是可直接复用的重解析进度迁移。检查的 manifest 映射没有保留 fallback 字段，不能将它当作所有功能的正确答案。 |
| foliate-js | [Resources / sections / nav](https://github.com/johnfactotum/foliate-js/blob/78914aef4466eb960965702401634c2cb348e9b1/epub.js)；[CFI](https://github.com/johnfactotum/foliate-js/blob/78914aef4466eb960965702401634c2cb348e9b1/epubcfi.js) | MIT | spine 构造 sections，nav/NCX 有局部降级；导航源码仍有非文本标签 TODO，证明成熟库也有遗漏。借鉴边界，不移植整套 DOM renderer。 |
| calibre | [manifest / spine / TOC](https://github.com/kovidgoyal/calibre/blob/2907fa931b22564cb0bdcf3656888c66515473fa/src/calibre/ebooks/oeb/reader.py)；[EPUB 输入与封面](https://github.com/kovidgoyal/calibre/blob/2907fa931b22564cb0bdcf3656888c66515473fa/src/calibre/ebooks/conversion/plugins/epub_input.py) | GPL-3.0（见仓库许可） | 容忍缺失资源、推断 MIME、补充链接文档等策略服务转换流程；封面处理还区分 for_viewer。不可照搬自动改阅读顺序、移除封面或猜测格式；只独立借鉴测试场景。 |
| EPUBCheck | [OPF 规则](https://github.com/w3c/epubcheck/blob/50a0a676aea41b7b9a5033a2a1cb93bf548ef023/src/main/java/com/adobe/epubcheck/opf/OPFChecker.java)；[导航 Schematron](https://github.com/w3c/epubcheck/blob/50a0a676aea41b7b9a5033a2a1cb93bf548ef023/src/main/resources/com/adobe/epubcheck/schema/30/epub-nav-30.sch) | BSD-3-Clause（固定提交根 LICENSE.md） | 验证出版物是否合法，不能替代阅读器容错策略；重复 spine 检查有 EPUB 2 版本条件，不能脱离分支解读。 |
| W3C epub-tests | [重复 spine 用例](https://github.com/w3c/epub-tests/blob/2d3b96756423189c0008eff95f0e98beda7cc5fe/tests/pkg-spine-duplicate-item-rendering/EPUB/package.opf)；[未声明资源用例](https://github.com/w3c/epub-tests/blob/2d3b96756423189c0008eff95f0e98beda7cc5fe/tests/pkg-manifest-unlisted-resource/EPUB/package.opf) | W3C Software and Document License（测试文档） | 按用例内版本、规范引用和实际断言逐条取证。当前网站入口版本不等于所有用例的适用版本；本轮没有执行官方套件。 |


## TXT 编码与结构参考

| 参考 / 固定版本 | 实际查阅模块与许可 | 维护 / 成本 / 选择 |
| --- | --- | --- |
| [calibre 2907fa9](https://github.com/kovidgoyal/calibre/blob/2907fa931b22564cb0bdcf3656888c66515473fa/src/calibre/ebooks/conversion/plugins/txt_input.py) | TXTInput、txt/processor.py 的 detect_paragraph_type、conversion/preprocess.py 的 DocAnalysis；GPLv3 | 成熟转换流程。参考分层分析和整书统计；不照搬硬换行合并、实体替换或 decode(...,'replace')，后者违反本项目不吞字原则。未复制实现 |
| [uchardet 用户提供镜像 bdfd611](https://github.com/fstudio/uchardet/blob/bdfd6116a965fd210ef563613763e724424728b7/src/nsUniversalDetector.cpp) | HandleData / DataEnd、uchardet.cpp；文件头 MPL1.1/GPL2+/LGPL2.1+ 选择许可 | 此镜像提交日期 2018-09-26，不能当作当前上游维护情况；官方站读取受阻。参考 BOM/候选评分分离，不集成 C++/FFI，不把最大分值当真值 |
| [ICU 2ebc705](https://github.com/unicode-org/icu/blob/2ebc7054cdfd593baf846c8e604bca5d1dd91bb6/icu4c/source/i18n/csdetect.cpp) | ucsdet.cpp / csdetect.cpp 的 detectAll；Unicode License V3（该提交 LICENSE） | 固定提交 2026-09-08；遍历识别器、保留非零匹配并排序。仅参考设计，避免跨平台原生库/包体成本；不移植整套语言统计模型 |
| [flutter_chardet 1.0.2](https://pub.dev/packages/flutter_chardet/versions/1.0.2) | lib/flutter_chardet.dart、native_detector 与 pubspec；MIT（原生材料另计） | detectAll / confidence + charset_converter。声明 Dart ^3.12.1、Flutter >=3.41.0，**不兼容当前 3.10.9/3.38.10**；未为 benchmark 升级或覆盖约束 |
| [flutter_charset_detector 6.0.0](https://pub.dev/packages/flutter_charset_detector/versions/6.0.0) | Dart 平台转发；Android 4.0.0 Kotlin 插件、Darwin 1.3.0 Swift 插件；主包 MPL2.0 | SDK 下限允许当前工具链；Android 用 juniversalchardet 2.5.0，Darwin 用 UniversalDetector/NSString，不能保证相同猜测/解码行为。未引入，也未声称已做双端运行 benchmark |
| [charset_codec 0.1.1](https://pub.dev/packages/charset_codec/versions/0.1.1) | codec/impl.dart、mbcs.dart 的严格 decodeMultibyte、增量 pending/close；MIT + CPython notices | Dart ^3.11.0，当前 SDK 不满足；含 native asset/Rust hook 依赖，但所查 GB18030 路径有 Dart 实现，不能笼统称全部原生解码。参考严格解码和结尾残字节检查，不升级依赖来测 |

所有包读取发布归档中的 pubspec/源码/许可证，未把 README 自报 benchmark 当作本项目证据。ICU 的[官方说明](https://unicode-org.github.io/icu/userguide/conversion/detection)明确探测依赖统计，不是编码证明。本轮没有需要 KOReader/FBReader/Librera 解决的特定剩余行为，因此未继续泛扫阅读器源码。

## 历史库对比

2026-09-08 Windows / Dart 3.10.3 AOT，可读取清单 31 项：Shiori 30/31、epubx 4.0.0 20/31、epub_parser 3.0.1 30/31。epubx 额外失败来自宿主路径生成反斜杠，不能外推为移动端成功率；epub_parser 的 WebP 留在 AllFiles，未归入 Images，不是资源丢失。三者拒绝的同一样本原因不同，不能都算作 DRM 检测。

原始历史结果可查 Git，复跑见[隔离工具](../../tool/epub_compare/README.md)。未验证设备渲染、fragment 跳转或修补后的第三方库；不按不同工作量的单次耗时排名。保留 Shiori 的身份、预算与阅读模型，暂不替换解析器。

规范参考：[EPUB 3.3](https://www.w3.org/TR/epub-33/)、[Reading Systems 3.3](https://www.w3.org/TR/epub-rs-33/)。库行为用于发现测试场景，不替代规范判断。
