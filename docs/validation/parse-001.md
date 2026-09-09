# PARSE-001：EPUB 结构对照

2026-09-09。对照官方发布归档 [epub_parser 3.0.1](https://pub.dev/packages/epub_parser/versions/3.0.1)，归档 SHA-256：`a620d67dd1de88ca91e732e95faece9b4c673b7875599359e76c966367158868`。MIT，Copyright (c) 2022 Tran Manh。只参考行为、独立实现，不复制上游代码，不新增依赖。

## 修复前差异与决定

下列源码路径相对上游 `lib/src/`。

| 对照项 | 上游位置与行为 | Shiori 决定 |
| --- | --- | --- |
| OPF / manifest / spine | `readers/package_reader.dart:59,326,386` 按直属节点读取章节列表 | 修复跨层搜索误收扩展节点；限定 OPF 子节点及元数据范围，拒绝缺失/重复结构和空 ID/href。保留现有阅读顺序与身份算法 |
| nav / NCX | `readers/navigation_reader.dart` 按 EPUB 版本选择目录；nav properties 使用完整字符串匹配 | 保留 Shiori properties token 集合、嵌套及 fragment 块定位；补充合法前缀别名。独立兼容策略：nav 没有可用条目时再读 NCX；不吞掉读取/安全错误 |
| 章节顺序 | `readers/chapter_reader.dart` 从导航递归生成章节 | 保留 spine 阅读顺序，目录可独立排序，同文档多锚点不复制章节 |
| 资源 / WebP | `readers/content_reader.dart:97` 不把 WebP 分类进 Images，但二进制仍在 AllFiles | 不照搬 MIME 分类；保留实际字节识别 PNG/JPEG/GIF/WebP、摘要去重及图片限额 |
| 路径 | `utils/zip_path_utils.dart` 拼接路径，部分读取点 decodeFull / 忽略大小写 | 保留包内 POSIX 规范化、一次解码、精确大小写、根越界/反斜线/外部地址拒绝；不采用宿主路径 API |
| 错误与限额 | 上游主要抛通用异常，没有等同 Shiori 的归档/文本预算 | 保留现有 ZIP/XML/深度预算与 DRM/固定版式拒绝，不扩大支持范围 |

## 验证

修复完成。新增 `test/data/local/epub_structure_test.dart`：修复前四项失败复现，修复后七项通过；包含前缀别名、空 nav → NCX、OPF 扩展隔离、无效结构、一次解码及 WebP（通用 MIME）资源保留。WebP 测试验证分类与字节保留，不声称完成设备解码。

`flutter test test/data/local` 91 项通过；之后增加的两项检查随上述七项结构测试通过。已有 `parsers_test.dart` 覆盖 EPUB2/3 嵌套目录、同文档 fragment、spine 顺序、中文编码图片路径及 ZIP/XML 边界。静态分析通过，格式化及 diff 空白检查通过。

未重跑其他电脑的 35 文件比较或设备验收；不把合成测试当作真实 EPUB 全覆盖。旧导入数据不自动重解析，迁移另见 PARSE-005。

## 第二轮：扩展结构边界（完成）

用户授权继续深入，以合成测试发现新盲区，不重复既有真实样本扫描。新增 epubx 4.0.0 与 EbookLib 0.20（Python）源码对照。EbookLib 为 AGPL-3.0-or-later，只对照行为，生产代码独立依据规范实现，不复制代码或增加依赖。

修复前确认的候选：container / NCX / metadata 外来命名空间误收、无命名空间属性被同名扩展属性遮蔽、XML 深度预算缺口、spine 外来格式有 XHTML fallback 时仍整体拒绝、nav 为 spine 文档时无链接分组可能错误指向自身。上述六类均由修复前失败测试确认，并已修复。`linear=no` 保留原位置是既有明确策略，不自动删去辅助内容；追加修复优先封面失效后的 legacy meta 降级，以及 EPUB2 guide 图片 / XHTML 封面页读取。RTL 手势、完整 CSS / SVG / SMIL 不因库提供字段而直接承诺支持。

依据：[EPUB 3.3](https://www.w3.org/TR/epub-33/)，重点 §3.5.1 fallback、§5.5 元数据、§5.7 spine、§6.1.3 命名空间。实现差异不能代替规范判断。


### 跨语言对照来源

- epubx 4.0.0：MIT，Copyright (c) 2017 Colin Nelson；官方发布归档 SHA-256 `0ab9354efa177c4be52c46f857bc15bf83f83a92667fb673465c8f89fca26db3`。`lib/src/readers/package_reader.dart` 的 manifest/spine 与 epub_parser 对应实现高度相似；`navigation_reader.dart:203` 的宿主 `path.normalize` 不采用。`book_cover_reader.dart:16` 的 legacy cover 选择促成封面失败降级测试，但不采用其绑定 Images 分类和整张图片解码的做法。
- [EbookLib 0.20 源码](https://github.com/aerkalov/ebooklib/blob/v0.20/ebooklib/epub.py)：`_load_metadata:1483` 按命名空间归类、`_parse_ncx:1614` 限定 NCX 命名空间、`_load_spine:1699` 保留 linear、`_load_guide:1718` 保存 guide。借鉴行为检查点，未复制 AGPL 代码。它的 nav `@*='toc'` 选择不采用，Shiori 保留语义命名空间与 token 判断。
- fallback 遍历独立依据 EPUB 3.3 §3.5.1 实现；不把库仅保存 fallback 字段当作支持完整 fallback 渲染的证据。仅为不支持的 spine 类型寻找本地 XHTML/text-html 替代，拒绝遍历中的循环/断链；被选中 XHTML 的原有章节身份算法保持不变，原目标路径作为目录别名。不会为远程资源发起请求。

### 测试支持矩阵

| 类别 | 本轮及已有离线证据 / 明确行为 |
| --- | --- |
| 容器与 XML | 正确 rootfiles 层级、外来节点隔离、无前缀属性、深度拒绝；保留既有 CRC、ZIP 限额、DTD/ENTITY/加密拒绝 |
| OPF 元数据 | DC 命名空间与前缀、扩展标题不污染、重复结构/空身份拒绝；缺标题仍走文件名兼容策略 |
| spine | 顺序独立于目录、保留 linear=no、XHTML fallback、循环/断链拒绝、章节身份不变 |
| nav / NCX | 嵌套、同文件 fragment、中文编码锚点、嵌套目录路径、多 properties token、前缀别名、空 nav 降级、无 href 分组选择首个子项 |
| 图片 / 封面 | WebP 不依赖 MIME 分类、缺图保留占位及正文、cover-image → legacy meta → guide、外部封面不加载 |
| 路径 | 中文及空格、百分号只解码一次、大小写精确、禁止根越界与外部引用；不借用宿主文件系统路径语义 |

第二轮 `epub_boundary_test.dart` 14 项，含八类修复前失败复现；首轮 `epub_structure_test.dart` 7 项。最终 `flutter test test/data/local test/data/sources test/widgets/reader --reporter expanded` **231 项通过**，`flutter analyze` 无问题，格式与 diff 空白检查通过。曾误用不存在的测试目录导致命令失败，已纠正路径重跑，最终结果以上述命令为准。

不重复扫描已兼容真实样本，不执行模拟器/真机验收。本轮是源码行为对照与 Shiori 合成回归，不是运行三个上游库的差分测试，也不是 EPUB 标准一致性认证。

### 当前支持边界

不支持 DRM、固定版式、独立 SVG spine（有 XHTML fallback 则可读替代）、SMIL 音视频同步、完整 CSS、任意嵌入对象、RTL 翻页方向或出版物写回；这些不能通过结构库比较补齐。普通图文 EPUB 的结构兼容已按上述矩阵收口，正文共享改造仍属于 PARSE-002，旧数据重解析仍属于 PARSE-005。没有更改持久化合同、版本、依赖或发布配置。
