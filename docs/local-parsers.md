# LOCAL-003 / LOCAL-004：TXT 与 EPUB 解析

本轮在 LOCAL-002 的接收副本、确认、取消和提交流程中接入 `BookDecoder`。两种格式共用 `LocalBookStore` 的原文件摘要去重、事务发布、失败回滚和媒体所有权。解析成功后已入库；加入书架、立即阅读、目录点击与阅读进度闭环属于 LOCAL-005，本轮没有自动执行。

## TXT

- 严格支持 UTF-8（有 / 无 BOM）、UTF-16 LE / BE BOM、GB18030（包括常见 GBK）。非法或截断序列、孤立 surrogate、矛盾 BOM 明确失败；绝不通过 `allowMalformed` 或丢弃字节生成可提交正文。原文件本来就有 U+FFFD 时原样保留，不误判为解码器替换。
- BOM 优先；无 BOM 时完整尝试 UTF-8 / GB18030。两者完整文本相同（例如 ASCII），或只有 UTF-8 合法时可自动继续。遗留编码或两种结果不同必须展示预览并由用户选择。比较完整结果，不以预览的前 600 个 code point 代替判定；预览相同但尾部不同仍需确认。
- 确认前可手动指定编码；手动选择同样先做全文件严格校验，再展示预览。失败保留接收副本，可以换编码重试。预览等待支持取消和退出，不能提前发布半本书。已有摘要直接返回既有内容，不改变其原有编码解释和进度。
- 统一 CRLF / CR / LF 为 LF；每个原始行（包括行尾、空白行、行首空格）形成语义块，不 trim 正文、不合并空白。拼接所有 Paragraph / Heading 的 text 等于去掉 BOM 后的规范化原文。长单段不按渲染分页或 chunk 拆分。
- 保守识别短行的中文“第…章 / 节 / 卷 / 回 / 话”等标题，含中文、全角、重复和非连续编号，以及基本英文 Chapter / Part / Volume、序章等。未识别时保留整篇；标题自身仍在正文中。单纯标题的章节使用 Paragraph 保留原文，以满足现有 ChapterContent 的可读内容契约。
- 默认书名来自文件名。章节定位符固定为 `txt:<offset>`：offset 是去掉 BOM 后、**换行规范化之前**的章节起点 code-point 偏移；CRLF 计两个 code point，补充平面字符计一个。首章前导空白归首章，因此首章 offset 为 0。重复标题不会产生重复 ChapterKey。

GB18030 采用 [WHATWG 解码算法](https://encoding.spec.whatwg.org/#gb18030-decoder) 和固定的官方二字节 / 四字节映射表。数据源为 [index-gb18030](https://encoding.spec.whatwg.org/index-gb18030.txt) 与 [ranges](https://encoding.spec.whatwg.org/index-gb18030-ranges.txt)，生成文件保留 SHA-256，`tool/encoding/generate.py` 接收本地输入，无自动网络更新。二字节表以 little-endian Uint16 / Base64 保存，首次使用时解码；不依赖平台 iconv 或安装新的原生插件。遵循 WHATWG 的兼容映射，不宣称不同 GB18030 历史版本的所有 PUA 字形都相同。上游许可在 `tool/encoding/LICENSE`，应用中分发 BSD 许可并注册 Flutter LicenseRegistry。

## EPUB

- 支持普通、无 DRM 的 EPUB 2 / 3 流式图文。读取 mimetype、container、OPF 的标题 / 作者 / 简介、manifest、spine；先按 spine 生成唯一章序，nav / NCX 不反过来重排正文。spine 中的辅助 `linear=no` 条目也保留在显式章序中。
- `ChapterKey` 定位符为 `epub:<规范化包内路径>`，不含临时目录、标题和 fragment。多个目录项可以指向同一章。EPUB 3 nav 与 EPUB 2 NCX 保留嵌套结构，无有效目录时按 spine 生成。
- `LocalBookContent.navigation` 独立于 Catalog，保存 `LocalNavigationEntry(title, chapterKey, blockKey?, children)`。fragment 对应最终语义块的 blockKey，行内锚点落到所在段；缺失 fragment 明确回退章首（null），不伪造页码。无链接的分组标题继承首个有效子项目标。包外 / 非 spine 目标不当作可读章节。
- XHTML 转 Heading / Paragraph / Divider / Image；`br` 保留换行，`pre` 保留空白。粗体、斜体、链接、列表、表格等按现有块模型降为文字 / 段落，CSS、自定义字体、交互、动画、音视频和数学排版不实现。导入确认面板提供中英文支持范围说明。
- 保留 OPF `cover-image` / EPUB 2 cover meta 和正文的包内 PNG / JPEG / GIF / WebP 图片；SVG 包裹的 raster image 可按包内引用提取，纯 SVG 绘图不渲染。内容哈希生成 MediaRef，主 isolate 通过 session.writeMedia 提交，实际 hash 必须与工作 isolate 生成的引用一致。
- 缺图片、包外图片或不支持的图片格式只留下 `[alt]` / `[▧]` 占位，不阻止其余正文导入。图片文件损坏的原生解码失败仍交给现有图片失败展示；本轮探针另验证真实 PNG codec。
- 不运行 WebView、脚本或外部请求；script、iframe、object 等不进入正文。外部 XML DTD 声明只移除、不解析或下载，内部 DTD / ENTITY 声明拒绝。已识别的字体混淆可忽略（不使用书内字体）；其他加密与固定版式明确拒绝。

包结构参考 [W3C EPUB 3.3](https://www.w3.org/TR/epub-33/)；ZIP header 字段依据 [PKWARE APPNOTE](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)。这是受限导入器，不是 EPUBCheck，也不宣称支持所有 EPUB 扩展。

## 执行、限制与生命周期

输入流仍由数据层持有。工作 isolate 只接收有界字节和不可变参数，不持有 LocalImportSession、数据库或平台权限。CPU 解码 / DOM 转换 / 内容身份计算在工作 isolate，取消杀掉该 isolate 并等待退出，再回滚 session；单次 CPU 工作 45 秒硬超时。媒体写入继续由存储 owner 串行完成。较大的 manifest 校验、摘要计算和 JSON 编码也移到工作 isolate，发布事务仍由原存储 owner 执行。

| 边界 | 当前限额 |
| --- | --- |
| 系统接收副本 / 存储原文件 | 沿用 128 MiB；不意味着所有格式都能解析到这个大小 |
| TXT 解析输入 | 16 MiB |
| EPUB 压缩输入 | 64 MiB |
| TXT 行 / 块；章节 | 100,000；10,000 |
| ZIP 条目数 | 4,096 |
| ZIP 单项 / 所有声明展开大小 | 16 MiB / 256 MiB |
| ZIP 展开比 | 单项 `展开大小 ≤ (压缩大小 + 1024) × 200` |
| XML / XHTML 单文档 | 4 MiB |
| 累计 XHTML 文本 | 12 Mi UTF-16 code units（包括读取 nav） |
| 单 HTML DOM 节点 / 嵌套深度 | 100,000 / 128 |
| 单章语义块 | 100,000 |
| 去重后托管图片总字节 | 128 MiB |
| TOC 项 / 嵌套深度 | 10,000 / 32 |
| manifest / 总托管包 | 沿用 32 MiB / 512 MiB |

ZIP 只接收单磁盘、非 ZIP64、stored / deflate。先校验中央目录和 local header 一致性、条目数量、大小、重复名称、重叠范围和路径，再对读取的条目解压；每次 zlib 输出回调检查真实字节数，最终校验长度与 CRC。绝对路径、反斜杠、`..` 条目、符号链接拒绝。包内 href 允许正常的 `../` 相对引用，但百分号只解码一次、规范化后不得越过包根。不会把 ZIP 条目名当落盘路径。

`archive 4.2.0`（MIT，Dart >= 3.0）提供 CRC 工具和离线测试 ZIP 编码；生产解压由 Dart SDK zlib 加有界输出接收器处理，不依赖 ZIP 库预分配整个声明大小。`xml 6.6.1`（MIT，Dart >= 3.8）用于 OPF / NCX，沿用 `html 0.15.7`（MIT）处理正文。这些依赖已在项目固定 Dart 3.10.3 / Flutter 3.38.4 下解析；无平台最低版本变更。[archive 官方包](https://pub.dev/packages/archive/versions/4.2.0)、[xml 官方包](https://pub.dev/packages/xml/versions/6.6.1)。

本地 manifest v1 增加可选 navigation 字段；旧记录缺省为空，既有详情 / 目录 / 正文 codec 和数据库 schema 不变。发布及重开均校验目录目标属于本书且 blockKey 存在，旧在线 Catalog / ReaderPosition 不受影响。LOCAL-005 再消费此导航树和托管媒体接口。

验证记录见 [LOCAL-003 / 004 验收](validation/local-003-004.md)。
