# 领域模型与内容身份

领域层保持纯 Dart、不可变，不依赖 UI、网络、SQL 或平台。入口 `lib/domain/models/models.dart`，摘要实现 `lib/domain/content_identity.dart`。

## 模型边界

- 所有模型具有值相等语义；构造时复制集合，对外不可修改。运行时 hashCode 只服务内存集合，不可持久化。
- SourceId / NovelKey / ChapterKey / MediaRef 保留不透明字符串，不 trim、不拼 URL；拒绝空白 ID 和非法 Unicode。SourceId 在注册层使用 `lightnovel`，Domain 不内置具体源常量。MediaRef 无 secret 的前提由 Source 保证，Domain 不猜测 URL 的签名字段。
- Summary / Detail 以字符串列表表示作者和标签；缺少信息保留 empty / null / unknown，不猜作者、完结状态或时间。Source 负责 HTML entity / 标记清理，Domain 只接收普通文本；不因文本含 `<` 等合法字符便把它当 HTML 删除。
- Catalog 只持有不可变卷章树，flatChapters 是惰性视图；不按 ID 或标题排序。全目录 ordinal 必须从 0 连续递增；重复 groupId / ChapterKey、跨小说归属或卷归属错误直接拒绝。Source 先处理重复链接和缺名诊断，不能依赖 Domain 静默去重。无卷可用明确 isSynthetic 的分组，缺卷名为 null，由 UI 展示占位名。
- ChapterContent 接受 Paragraph / Image / Heading / Divider，保留段落顺序和单段完整文本。可读正文至少有一个非空 Paragraph 或 Image；纯图片章有效，只有空白 / 标题 / 分隔符无效。空 Paragraph 可在有效正文中表达已确认的语义空白。
- Paragraph 的 alignment 为 start / center / end，leadingIndent 为整数 0–8 em，表示段落首行缩进，不是整段左内边距；展示用前缀不计入原文位置。当前不启用 text runs / 嵌套 AST；Source 的 Ruby 初始降级为基字加括注、强调保留文字，不在 Domain 处理站点标签。
- 图片尺寸各自可未知；已知值须正数。封面和正文图片必须属于相同 Source。ImageBlock 尺寸为后续可发现的布局元数据，更新尺寸不改变 blockKey / contentRevision；mediaId、alt、caption 的改变会改变语义身份。
- ReadingProgress 持有 NovelSummary 快照以保留离线标题 / 封面，并检查 ChapterKey 与快照属于同一本书；是否收藏由独立 BookshelfEntry 表示。lastReadAt 统一为 UTC 毫秒，写入先后由持久化 sequence 控制。

## 摘要 v1 与序列化

固定输入为无额外空白的 JSON 数组：`["shiori",1,kind,fields]`，再按 UTF-8 编码、SHA-256 输出 64 位小写十六进制。fields 只允许字符串、整数、布尔值、null 和嵌套数组，拒绝 map / 浮点值，避免字段顺序和非有限数歧义。文本只将 CRLF / CR 统一为 LF；不 trim、不做 NFC/NFKC，不改变全角字符、标点、emoji、段内换行或首尾空白。拒绝孤立 UTF-16 surrogate，避免编码替换造成内容碰撞。

| 摘要 | 固定 fields 顺序 |
| --- | --- |
| Paragraph 语义 | text、alignment.name、leadingIndent |
| Image 语义 | `[sourceId, mediaId]`、alt、caption；不含 width / height |
| Heading 语义 | text、level（1–6）；非默认 alignment 追加参与身份，默认 start 保持旧格式 |
| Divider 语义 | 空数组 |
| blockKey（kind=block） | block kind、该类 semantic fields、同章该语义的 occurrence（从 0 开始） |
| contentRevision（kind=chapter） | title、按正文顺序排列的 blockKey 数组 |
| Catalog revision（kind=catalog） | `[sourceId, novelId]`，然后每个卷依次为 `[groupId,title,isSynthetic,章节数组]`；章节项为 `[[sourceId,novelId,chapterId],title,ordinal]` |

ChapterContent 统一重新分配 occurrence，不信任调用方手填值。不同语义块的插入不改变既有块键；在同样内容的重复块之前插入另一个相同块会改变后续 occurrence，这是规则的明确限制。blockKey 只在章节内使用；纯文本内容完全相同的不同章节可以得到相同摘要，业务定位始终同时使用 ChapterKey。

ChapterContent 提供 toJson / fromJson；读取时校验 normalizationVersion、块类型、blockKey、occurrence 和 contentRevision。JSON 返回的是独立容器，改动它不会修改值对象。存储 envelope 的 parserVersion、cache codec version、抓取时间不进入 Domain 摘要；其他模型由存储层 codec 负责。ReaderSettings 当前为 schemaVersion=3；读取 v1 / v2 保留原数值与阅读明暗，v1 补 paged，旧版统一补 paper=paper、controlsHintSeen=false。未知版本仍拒绝。

字号、屏宽、DPR、主题、pixelOffset、layoutKey、临时渲染切片都不进入正文摘要或序列化。一个极长 Paragraph 始终一个语义块，presentation 可临时切片但不能回写 Domain。

测试中的固定向量由 .NET `SHA256.HashData` 对手写精确 UTF-8 JSON 独立计算，包含 paragraph 语义、重复块 0/1、image、chapter 和 catalog。`tool/domain_example.dart` 在两个实际 Dart 子进程中输出完全一致，Windows 的输入/输出编码显式指定 UTF-8。

## 阅读位置与设置

ReaderPosition 的 blockIndex 非负，blockFraction / chapterFraction 必须有限且位于 0..1；NaN / Infinity / 越界直接拒绝，不静默改写错误进度。fractionFor 依 `(blockIndex + blockFraction) / blockCount` 计算，检查 index 属于本章；空内容仅允许 0/0 起点。文本 fraction 按 Unicode code point 偏移定义，UTF-16 布局索引转换留 presentation。构造位置时尚无正文实例，不假装已验证 blockKey 在某章内存在；实际恢复由阅读器处理。

像素提示必须同时包含合法 pixelOffset 和 layoutKey，仅用于同布局提示，不能替代语义位置。ReaderSettings 当前 schemaVersion=3，默认字号 20、行高 1.6、段间距 20、左右边距 40；有效历史排版保留，未知版本拒绝。ReaderMode.scroll 只保留兼容解码，生产偏好层归一化为 paged，详见[阅读器](reader.md)。

AppSettings 独立 schemaVersion=2，包含 system / light / dark 和 teal / blueGrey / warmBrown / softPink；旧 v1 补默认青绿，不借用阅读主题。ReaderPaper 表示阅读纸色，controlsHintSeen 记录提示已确认；恢复默认保留该提示状态。所有值模型不含 Flutter Color 或语言文案。



## 本地与缓存模型

本地书籍以原文件 SHA-256 标识，章节使用稳定解析定位符。LocalNavigationEntry 独立保存嵌套目录与可选 blockKey，不改变 Catalog 章顺序；LocalBookInfo / LocalBookDeletion 描述管理结果，不暴露平台路径。规则见[本地导入](local-import.md)。

CachedChapter / CacheOverview / PrefetchState 是不可变投影，预取目标是既有 ChapterKey，不代表已读或未经确认的续卷关系。见[契约](contracts.md)与[缓存](cache.md)。

模型与摘要测试位于 `test/domain/`；`fvm dart tool/domain_example.dart` 使用自制内容演示跨进程确定性。平台证据见[验收摘要](validation/README.md)。
