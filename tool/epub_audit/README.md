# EPUB Reading-Loss Auditor v2

用此工具查找 EPUB 在解析和阅读中可能丢失的内容。先运行 `scan` 比较源内容、解析决定和输出模型，再选代表页面验证；扫描结果用于定位问题，完整渲染与 EPUB 标准合规需分别检查。

工具只读原文件，不导入用户书库或修改 EPUB。普通 `scan` 不启动 Flutter、浏览器、WebView 或声音，也不执行作者脚本。

## CLI

在仓库根目录使用固定 FVM 工具链，PowerShell 命令如下：

```powershell
fvm dart run tool/epub_compatibility_audit.dart --help
fvm dart run tool/epub_compatibility_audit.dart scan --input "book.epub" --out ".tooling/epub-audit/single"
fvm dart run tool/epub_compatibility_audit.dart scan --paths "paths.json" --out ".tooling/epub-audit/list"
fvm dart run tool/epub_compatibility_audit.dart scan --input-dir "E:\epub collection" --recursive --out ".tooling/epub-audit/corpus"
fvm dart run tool/epub_compatibility_audit.dart compare --before ".tooling/epub-audit/old" --after ".tooling/epub-audit/new" --out ".tooling/epub-audit/diff"
fvm dart run tool/epub_compatibility_audit.dart plan --run ".tooling/epub-audit/single" --out ".tooling/epub-audit/plan" --max-targets 12 --configurations 3 --max-pages 12
fvm dart run tool/epub_compatibility_audit.dart verify --plan ".tooling/epub-audit/plan/plan.json" --input "book.epub" --allow-root "." --provider native --out ".tooling/epub-audit/verification"
fvm dart run tool/epub_compatibility_audit.dart review --run ".tooling/epub-audit/single" --evidence ".tooling/epub-audit/verification" --out ".tooling/epub-audit/review"
fvm dart run tool/epub_compatibility_audit.dart capture --input "book.epub" --allow-root "." --out ".tooling/epub-audit/private-bundle"
fvm dart run tool/epub_compatibility_audit.dart evaluate --bundle ".tooling/epub-audit/private-bundle" --allow-root ".tooling/epub-audit" --out ".tooling/epub-audit/replay-evaluated"
```

`paths.json` 是文件路径字符串数组。三种输入方式互斥；目录默认不递归，不跟随符号链接或 junction 越出范围。内容 SHA-256 相同的副本只解析一次，保留本地别名。输出目录必须不存在；旧的两个位置参数入口只返回迁移提示，不覆盖旧报告。

## 输出与比较

`report.json` 是版本化汇总事实来源，`report.md` 只从相同 JSON 生成；每本的完整检查、文档清单和有界观察保存在 `book-*.json`。`inventory.json` 保存输入身份，`books.jsonl` 逐本提交索引；已完成的单本 JSON 不再改写，重复别名仅追加到索引，读取时合并。中断后可从索引读取已完成结果并忽略未写完的尾行，汇总的 `complete=false` 表示范围尚未完成。

schema2 / rules2.0.3 保留旧检查与观察，并增加独立的源事实、表示事实、对应关系、候选和验证证据。源实例身份包含 EPUB hash、包内路径、spine occurrence 与 DOM 位置；资源 hash 不代替实例身份。偏移明确标记 Unicode 码点、UTF-16 或字节；没有可靠 HTML source span 时保持 null。简单文本预期独立于 trace；有效 CSS 依赖共享的生产原生 cascade，明确记录该依赖。

各证据层分别使用 `pass/fail/unknown/not_run`。原生模型已输出、真实 Reader 选择、widget 几何／点击、浏览器、原生 WebView、音频解码和字体字形归属互不升格。候选按内容、结构、视觉、交互及可解释的证据分档组织；支持观察、Reader 策略、安全边界和源问题保留事实，但不按警告数量生成开发任务。

简单文本块按顺序对应并消费输出；全部源文本属于可靠简单块的文档还检查额外输出。容器直接文本、复杂转换和未对应输出显式记为 unknown。简单 Ruby 逐组比较注音及码点范围；简单链接和脚注按源块、码点范围与目标对应，每条输出关系最多消费一次，跨块等不可靠范围保持 unknown。

音频按可见且未被其他语义消费的 `controls` 建立源实例预期，核对声明与签名、原生控件的资源／不可用原因及所选显示路径。正确保留的不可用控件与控件缺失、状态矛盾、被特殊呈现遮掉分别记录；无控件或未参与显示的音频不一律归为安全过滤。原生控件已输出不证明平台解码、点击或播放通过。

比较只匹配同内容 hash，分别保存 producer（parser／模型／renderer）、evaluator、probe 和环境指纹。同 evaluator 比较不同 producer；同 producer 的规则变化记 `assessment_changed`。旧候选消失须有同源实例的正向对应证据才能记 `resolved_with_evidence`，覆盖下降保持 unknown。当前 renderer 重放旧模型不代表执行了旧 renderer。schema1 可读取并展示旧报告；跨 schema 不可靠时给出重新扫描／评估命令，不补造关联或覆盖旧文件。

## 显式验证与重放

`plan` 默认最多 12 个不同形状的目标，每目标最多 3 个配置；带完整文档、语义定位、前后上下文与页数／时间／截图预算。未选中、未达到目标和预算不足保持 not_run／partial。`verify` 必须显式提供原书或 bundle 及 `--allow-root`，独立核对 hash 和规范路径；报告中的别名不授权磁盘读取。

`native` 使用固定 Flutter widget 入口挂载生产 BookReaderScreen、隔离 Repository 和真实分页组件；检查完整字符、选择框、混合行、翻页与恢复、纯色对比度及等宽同色实线圆角像素。双线、ridge／groove、不同侧颜色或边宽保持特征 unknown，整页文字几何通过不会认证该边框候选。点击实际控件，音频使用 fake 平台验证一次播放、生命周期停止和关闭，默认不发声。`--font` 可显式提供本机现有字体；未提供时记录测试 Ahem。资源加载与目标字形实际使用分开，复杂背景、字形归属保持 unknown。

`browser` 使用已安装的 Chromium 独立进程和临时 profile，测量真实生产 presentation 与宿主注入，阻止网络访问，记录几何、滚动位移和实际输入。它不能证明 Android WebView／WKWebView／WebView2。`webview` 使用专用入口 `integration_test/epub_loss_webview.dart` 的隔离构建；通过 `SHIORI_LOSS_WEBVIEW_HOST` 显式提供可执行文件，旁边的 `.identity.json` 必须包含当前 `producer`、`probe` 指纹及 `executableHash`。固定宿主测量保留 CSP、作者脚本禁用和原导航拦截；缺少能力返回 69。构建应在临时工程中进行；若使用正常工程须按 AGENTS 恢复入口和生成配置。

验证证据单独落盘并以 checksum 追加 JSONL；截图也核对 checksum。`review` 校验候选、源、producer、probe、环境和配置身份；人工／agent 的决定单列，不改变机器运行状态。JSON 是事实来源，Markdown 只从同份 JSON 生成。正常退出 0；参数／格式 64，输入或 provider 未执行 65，能力缺失 69，IO 73，超时 124，中断 130；已完成证据可在中断后读取。

浏览器测量区分当前被裁剪和可通过普通滚动到达的范围，纳入祖先裁剪；transform、clip-path、圆角裁剪或复杂嵌套滚动保持局部 unknown。观察到裁剪不自动证明违背作者意图。验证批次中断后等待自有进程退出，不再派发后续目标／配置；已落盘证据保留，剩余项在 verification.json 记录 not_run 原因。

`capture` 的 PRIVATE bundle 保存原书、生产模型、导航、媒体、presentation 和指纹。`evaluate` 从该模型重放，故意不调用当前 parser.parse；不能用新 parser 生成的结果伪装旧版本。bundle 逐文件校验、限制 256 MiB，模型 32 MiB，原书仍限 64 MiB。历史源码仅在隔离目录运行。私人材料只放 Git 忽略的新目录；保留需要的版本，确认不再使用后仅删除明确的私人输出目录。

## 预算与隐私

静态扫描不执行探针。`review` 用当前实际 probe 指纹校验独立验证证据，保留扫描时的 `scanProbe`；旧探针的结果不会自动升格。重放环境单独记录实际 renderer 指纹，不能将当前 renderer 的测量当作旧 renderer 已运行。

默认串行，每本独立 Dart worker，60 秒超时后等待实际终止；`--timeout-seconds` 可显式调整。独立进程是失败隔离，不是完整安全沙箱。生产载荷上限 64 MiB 不放宽；身份流式哈希上限 128 MiB，超限输入身份标 unknown。遵守生产 ZIP 的 CRC、路径、解压和资源预算。

默认每本最多 1024 个源文档、100000 个 trace 事件、2000 个聚合观察、每组 3 个位置和 8 MiB 报告；`--max-documents/--max-events/--max-findings` 可在 CLI 边界内调整。源文本总量 12 Mi 字符、CSS 8 Mi 字符；单次 XML/HTML 读取及节点深度也有界。目录枚举最多 100000 项、64 层、10000 个 EPUB。批次内存中用于聚合的观察最多 64 MiB，汇总最多 10000 组、32 MiB；达到上限显式标截断或下界，不输出完整兼容结论。

详细 trace 仅显式开启，独立且有界，不写入书籍模型或数据库。生产 100 条轻量诊断合同保持不变。报告仅保留计数、哈希、包内路径、有限定位和脱敏 CSS 值，不输出正文、注音、脚注全文、媒体或敏感 URL。报告属于私人藏书信息，应放在 Git 忽略的 `.tooling` 或临时目录；工具不会上传。

源 sidecar 默认最多 4000 facts、8000 representations、2000 candidates，截断单独标下界，不削弱原独立检查。验证每项最多 8 MiB 证据，每 run 64 MiB；private replay cache 至多 768 MiB，浏览器 profile 在退出并等待自有进程收尾后释放。超时只终止本命令启动的进程树，不处理用户其他浏览器／开发进程。截图与 private 日志含原书内容，不能视为脱敏报告。
