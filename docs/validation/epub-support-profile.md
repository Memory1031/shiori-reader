# 1.1.0 解析支持矩阵

更新：2026-09-09，PARSE-004 收口。描述当前实现，不代表完整 EPUB 标准认证或设备验收。任务证据见 [收口报告](parse-004.md)，历史第三方差异见 [固定版本审阅](epub-reference-audit.md)。

| 能力 | 当前支持与限制 | 回归入口（test/data/local 下） |
| --- | --- | --- |
| ZIP / container / OPF | 有界解包、CRC、路径校验、manifest/spine 顺序；多 rootfile 选择首个匹配项 | parsers、epub_structure、epub_boundary |
| EPUB 2 / 3 目录 | NCX/nav、嵌套标签与 fragment；可选目录损坏可降级；内部存储章节以 spine 文档为单位 | epub_structure、epub_boundary |
| 路径与 fragment | Unicode、百分号一次解码、大小写精确；目录缺锚点可回章首，正文链接缺锚点明确不可用 | epub_structure、epub_links |
| 重复 spine | EPUB 3 occurrence 独立身份，同文档链接保留 occurrence；跨文档指向首个 occurrence；EPUB 2 重复拒绝 | reparse、epub_links |
| 正文语义 | 段落、标题、br、缩进、对齐、ruby 文本降级；强调/上下标无完整富文本样式 | epub_compatibility、epub_prose_semantics |
| CSS | 受限选择器、顺序/media、important、white-space 与 visibility；隐藏元素不保留原生几何占位，非完整 cascade | epub_stylesheet、epub_prose_semantics |
| 图片 | PNG/JPEG/GIF/WebP 字节识别、SVG image 包装、srcset/picture 包内候选；确定性选图，不按 viewport/sizes 计算；缺图占位 | epub_compatibility、epub_resources |
| 特殊页 | 受限静态 HTML；保留部分复杂排版，脚本/外链受限；不保证完整出版方布局 | epub_presentation |
| base/xml:base | 不解释，按所在文档解析；这是明确未实现的兼容变体 | PARSE-006 报告与路径用例 |
| 未声明图片 | 容忍包内可识别位图，不声称符合完整 manifest 规范 | epub_resources |
| 辅助链接 | 通过“本章链接”菜单打开包内辅助页并返回；linear=no 不参与连续阅读；未开放正文内联/WebView 点击，隐藏目标不揭示 | epub_links、reparse；widget local_links |
| 诊断 | 每次至多 100 条 data 层原因码快照，不存正文/本机路径；无持久化/UI | epub_diagnostics |
| TXT | 严格 UTF-8/UTF-16/GB18030、BOM 优先、歧义预览、保守标题识别、原始 code point 身份；16MiB 上限 | txt 系列；PARSE-003 |
| 旧书与重解析 | 已发布 manifest 稳定读取；用户显式重解析，在暂存区生成并原子切换；精确或近似迁移位置，失败/取消保留旧书 | reparse；domain reparse_position；widget local_reparse |
| 重启恢复 | schema v4、活动 bundle、进度和辅助资源恢复；旧会话晚写拒绝 | reparse、database migration |
| DRM / 固定版式 / SMIL / 互动 | 拒绝或受限静态降级；无 DRM 解密、媒体同步、通用浏览器排版 | epub_boundary、epub_presentation |

表中入口为文件名主题，不意味着每项已在手机验证。图像可解析不等于设备 codec、排版、裁剪均通过。

## 缺口处理结果

- GAP-001/007/008/009：PARSE-001 完成结构与目录修复。
- GAP-002：PARSE-002 完成受限正文语义。
- GAP-003/005/011：PARSE-006 完成候选选择；base 明确不实现；未声明图片保留容忍。
- GAP-006：PARSE-007 完成有界诊断。
- GAP-004/010：PARSE-005 完成显式重解析、位置迁移与 occurrence。
- GAP-012：PARSE-008 完成菜单辅助阅读；内联点击与隐藏脚注仍不支持。

没有将以上限制自动加入下一版本。CFI、完整 CSS、原生富文本、固定版式等需另行确定需求；CFI 本身不能解决 DOM 重组后的迁移。

## 更新与证据边界

重复导入按摘要去重，不升级旧 manifest；无需删除重导。使用本地书菜单的重新解析获取新语义，近似恢复会提示，不保证原行位置。取消或失败不发布新结果；已提交后的取消不能撤销成功发布。

历史真实样本核查为 35 个文件、34 个不同摘要，包含加密拒绝样本；之后跨机可访问清单为 31 项。本轮未重新读取或提交用户原件，也不把缺文件当成失败。支持依据为已有脱敏/合成测试与历史报告，未运行第三方全部官方套件。Android 12 真机主要流程已通过，取消未测，iOS 用户确认重解析后特殊排版正常并确认整体收口；详情见收口报告。
