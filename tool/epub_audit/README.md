# EPUB 兼容审计工具

开发侧只读工具，以受限源清单、实际解析决定和输出模型交叉检查 EPUB。报告不是渲染认证或 EPUBCheck 结果；不执行脚本、启动 WebView、联网下载资源、导入书库或修复 EPUB。

## CLI

在仓库根目录使用固定 FVM 工具链，PowerShell 命令如下：

```powershell
fvm dart run tool/epub_compatibility_audit.dart --help
fvm dart run tool/epub_compatibility_audit.dart scan --input "book.epub" --out ".tooling/epub-audit/single"
fvm dart run tool/epub_compatibility_audit.dart scan --paths "paths.json" --out ".tooling/epub-audit/list"
fvm dart run tool/epub_compatibility_audit.dart scan --input-dir "E:\epub collection" --recursive --out ".tooling/epub-audit/corpus"
fvm dart run tool/epub_compatibility_audit.dart compare --before ".tooling/epub-audit/old" --after ".tooling/epub-audit/new" --out ".tooling/epub-audit/diff"
```

`paths.json` 是文件路径字符串数组。三种输入方式互斥；目录默认不递归，不跟随符号链接或 junction 越出范围。内容 SHA-256 相同的副本只解析一次，保留本地别名。输出目录必须不存在；旧的两个位置参数入口只返回迁移提示，不覆盖旧报告。

## 输出与比较

`report.json` 是版本化汇总事实来源，`report.md` 只从相同 JSON 生成；每本的完整检查、文档清单和有界观察保存在 `book-*.json`。`inventory.json` 保存输入身份，`books.jsonl` 逐本提交索引；已完成的单本 JSON 不再改写，重复别名仅追加到索引，读取时合并。中断后可从索引读取已完成结果并忽略未写完的尾行，汇总的 `complete=false` 表示范围尚未完成。

每项检查有 `pass/fail/unknown/not_run`；观察分别记录处理结果、证据层级、影响和置信度。原生元数据已输出与设备显示正确分开，运行时始终未验证。没有真实 source span 时行列为 null，使用规则序号和 DOM 路径。旧 `differences/policyDifferences/presentationImageDifferences` 字段弃用，不与新 schema 的检查数量直接比较。

简单文本块按顺序对应并消费输出；全部源文本属于可靠简单块的文档还检查额外输出。容器直接文本、复杂转换和未对应输出显式记为 unknown。简单 Ruby 逐组比较注音及码点范围；简单链接和脚注按源块、码点范围与目标对应，每条输出关系最多消费一次，跨块等不可靠范围保持 unknown。

比较只匹配同内容 hash；schema、审计规则、工具代码指纹或选项不同会拒绝直接比较。比较单独记录各检查的 checked/failed/unknown 数量变化；相关检查含 unknown、缺少覆盖计数或未执行时，观察消失记为 unknown，不宣称修复。

## 预算与隐私

默认串行，每本独立 Dart worker，60 秒超时后等待实际终止；`--timeout-seconds` 可显式调整。独立进程是失败隔离，不是完整安全沙箱。生产载荷上限 64 MiB 不放宽；身份流式哈希上限 128 MiB，超限输入身份标 unknown。遵守生产 ZIP 的 CRC、路径、解压和资源预算。

默认每本最多 1024 个源文档、100000 个 trace 事件、2000 个聚合观察、每组 3 个位置和 8 MiB 报告；`--max-documents/--max-events/--max-findings` 可在 CLI 边界内调整。源文本总量 12 Mi 字符、CSS 8 Mi 字符；单次 XML/HTML 读取及节点深度也有界。目录枚举最多 100000 项、64 层、10000 个 EPUB。批次内存中用于聚合的观察最多 64 MiB，汇总最多 10000 组、32 MiB；达到上限显式标截断或下界，不输出完整兼容结论。

详细 trace 仅显式开启，独立且有界，不写入书籍模型或数据库。生产 100 条轻量诊断合同保持不变。报告仅保留计数、哈希、包内路径、有限定位和脱敏 CSS 值，不输出正文、注音、脚注全文、媒体或敏感 URL。报告属于私人藏书信息，应放在 Git 忽略的 `.tooling` 或临时目录；工具不会上传。
