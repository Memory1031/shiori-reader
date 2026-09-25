# 本地导入与 EPUB 兼容

## 用户流程

文件选择、系统「打开」或分享只接收文件；应用内确认后才发布到书库。导入会保存托管副本、加入书架，并用完整文件 SHA-256 去重。同名不同内容是不同书籍，相同字节重复导入不重复建书。

待确认回执按 inbox 顺序组成批次：用户在应用内确认一次后严格串行导入，单个文件失败只标记该项并继续后续文件；成功项提交后立即发送 ack 回执（确认消费），对应项从待处理 inbox 删除，失败与未处理项保留供重试（应用重启后仍可见）；非运行态的「取消 / 放弃导入」显式放弃当前批次，逐条 ack 并清理 inbox 副本，不删除用户原文件或已入库书籍；清理失败保留未 ack 项和错误供重试，成功后可以重新选择文件。批量确认面板按回执顺序列出文件、逐本显示导入状态，结束后显示成功/失败汇总并可重试失败项；运行中的「停止导入」仅停止当前处理，不回滚已成功项，保留全部未完成回执。Dart 侧 `ImportSource.pending()` 返回有序回执列表；Android 和 iOS 均支持一次多选或多文件分享。

导入浮窗在未运行时可通过点击空白区域或按 Esc 收起，保留待导入回执，重新打开可继续；收起不等于「取消 / 放弃导入」。浮窗打开时隔离底层页面的键盘焦点，收起后恢复原焦点。运行时 Esc 不关闭浮窗，停止操作使用「停止导入」。

本地书从书架或详情移除，与本地文件管理中的删除使用同一流程；确认后删除应用内原件和解析资源，不提供撤销。单独清缓存不删除用户托管文件。删除操作清理该书托管数据、书架和进度，并失效旧会话晚写；外部原文件不动。

本地书使用 `SourceId('local')`，所有读取模式均走本地，不经过在线 Source、在线预取或可淘汰正文缓存。

## 文件与事务

`users/books/<hash>/` 保存 `original`、codec v1 的 `manifest.json` 和按内容哈希命名的媒体。暂存在 `users/import-staging/`：复制 / 哈希 → 解析与资源落盘 → 原子改名 → 数据库事务发布。失败不发布半本书；启动回收只处理确认未被用户库索引的暂存，不能把数据库读取失败当成空书库。

`LocalImportSession` 拥有暂存，`LocalBookStore` 管理文件，`LocalBookManagement` 管理删除。已发布文件损坏时保留并报错，不自动删除用户数据。存储与迁移见[数据库](architecture.md)。

身份不包含外部路径或临时 URI。TXT 章节以去 BOM 后、归一化前的原始 code point 起点派生；EPUB 首次资源章节以规范 spine href 派生，EPUB 3 后续重复 occurrence 使用独立摘要身份；目录 href 指向首次出现。目录条目可附 fragment 定位 blockKey，目录层级与物理章节文件不是同一概念。

## 平台接收

Android 与 iOS 通过各自系统入口接收文件；DesktopImportSource 使用 Dart 与 file_selector 接收桌面选择，Windows 还支持将一个或多个 TXT / EPUB 文件拖入应用窗口。拖放与文件选择共用待确认批次，已有批次未处理完时不接收新批次。各适配器均先保存 durable inbox 副本，再提供待确认回执；平台差异体现在入口、授权模型和目录位置。

### 公共收件箱协议

两平台的收件箱子结构相同（Android 位于 `noBackupFilesDir/import-inbox/`，iOS 位于共享 App Group 的 `ImportInbox/`）：

```text
import-inbox/
  lock
  working/                         # 尚未发布的整批暂存
    item-0000-<uuid>/payload
    item-0000-<uuid>/receipt.json
    item-0001-<uuid>/...
  pending/                         # working 一次原子 rename 后出现
    item-0000-<uuid>/payload
    item-0000-<uuid>/receipt.json
    item-0001-<uuid>/...
  ack-trash-<uuid>/                 # 已 ack 项的可回收墓碑
```

回执包含不透明 `id`、展示 `name`、实际 `size` 和从 0 开始的 `order`；恢复按 order 排序，ack 后允许序号有缺口但相对顺序保持。目录名来自内部序号和 UUID，不使用外部文件名、URI path 或调用方传入的 ID。读取时验证元数据、重复 ID/order、payload 长度及符号链接；损坏的已发布 pending 返回 `storage` 并保留原数据。

同一时刻最多一个 pending batch，不追加、不合并、不覆盖已有批次。每批最多 64 个文件、单文件 128 MiB、实际累计复制量 512 MiB；超过 64 个文件或整批超过 512 MiB 返回 `batchLimit`，单文件超过 128 MiB 返回 `tooLarge`。128 MiB / 512 MiB 是 Native inbox 暂存上限，不等于 TXT / EPUB 解析器接受该体量输入；[TXT](#txt) 与[输入边界](#输入边界)各自的解析限制仍独立生效。`batchLimit` 仅是原生选择 / 接收拒绝，不加入控制器 fatal 策略。

接收在 `lock` 上整批进行：stage、pending、ack 共用同一锁，持锁期间可以复制整批，其他访问不会读到 working。创建 working 和打开任何输入前，先 prepare 全部输入并逐项检查取消、大小写不敏感的 `.txt` / `.epub` 展示名及可用的声明大小；后项元数据失败时不复制任何 payload。按块流式复制（64 KiB）检查取消、单文件与整批实际字节数，不依赖声明的文件大小。任一文件不可读、空、扩展名不支持、超限或取消，都清理 working，不发布部分回执——Native 接收是 all-or-nothing。每个 payload 和 receipt 写入后同步，目录同步完成并做最后取消检查后，只执行一次 working → pending 原子发布。rename 后的已发布数据不再作为 working 回滚；极端的发布后同步错误保留 pending 并报告 storage。协议覆盖进程中断恢复，不宣称已验证物理断电。

ack（确认消费回执）通过元数据定位匹配 ID，在锁内将该 item 原子 rename 为根目录的 `ack-trash-<uuid>`，同步目录后清理空 pending，再尽力删除墓碑。ack 按 ID 幂等，只消费指定回执：不存在的 ID 可重复 ack，不影响其他回执。若进程在 detach 后、递归清理中退出，剩余 pending 仍完整；下次 pending/stage/ack 清理 working、墓碑和空 pending，避免永久 busy。恢复只回收暂存、墓碑和空 pending，只清理明确的临时 / 墓碑目录，不静默删除损坏的已发布数据。

升级兼容旧单文件 `pending/{payload,receipt.json}`：作为一项批次读取，不要求迁移；已有合法旧回执仍返回 busy，匹配 ID 的 ack 原子移走整个 legacy pending 后清理。

进度事件沿用 `{bytes}`，约每累计 1 MiB 发一次，跨文件不归零，结束发送 `{done:true}`。取消只设置取消标记，并通过同一 worker 排队等待复制、流关闭和 working 清理完成再回复，不在写入尚未停止时声称完成。Native 整批接收的 all-or-nothing 与之后 Dart 逐书入库的 partial success 是两层独立语义。

三种取消类行为互不相同，不混用：

1. 系统 picker 取消：接收侧静默结束，不产生任何回执、不发布批次。
2. 运行中的「停止导入」：停止当前处理，不回滚已成功项，不 ack 未完成回执，剩余回执留在 inbox 供重试。
3. 非运行态的「取消 / 放弃导入」：逐条 ack 并 discard 剩余 inbox 副本；不删除用户原文件，也不删除已经入库的书。

恢复通过 inbox 实际状态和应用恢复前台检查，不只依赖一次事件通知。Dart 侧 `PlatformImportSource` 接受两平台的有序 `List<Map>`（空为 `[]`），并兼容旧 `Map/null`；完整校验后一次性替换 ID → 私有路径缓存，路径不进入领域模型。

### Android

`MainActivity` 负责 picker、Intent、ContentResolver 和 channel；`ImportInbox` 实现公共协议，inbox 位于 `noBackupFilesDir/import-inbox/`。

- `ACTION_OPEN_DOCUMENT`：设置 `EXTRA_ALLOW_MULTIPLE=true`，优先按 ClipData 顺序接收，否则读取单个 data URI。
- `ACTION_VIEW`：使用 data URI。
- `ACTION_SEND` 优先 `EXTRA_STREAM`；`ACTION_SEND_MULTIPLE` 优先有序 `EXTRA_STREAM` 列表；两种分享缺 stream 时兼容 ClipData。
- 每个文件只接受 content URI，在临时授权期间立即读取并复制到 no-backup inbox，不请求所有文件权限。
- 不将 stream 与 ClipData 重复拼接，也不按 URI 或同名去重；相同字节的书籍仍由 Dart 存储层 SHA-256 去重。
- 空选择返回 unreadable；系统取消保持静默，不产生回执。

### iOS

Runner 与 ShareExtension 必须使用同一 App Group 配置（`SHIORI_IMPORT_GROUP`）及兼容签名，共用其下的 `ImportInbox/` 实现公共协议。两个进程间的批次 session 从开始到发布或回滚持续持有跨进程 flock。

- UIDocumentPicker 多选：按 security-scoped resource 读取，经 NSFileCoordinator 协调；Runner 在复制前验证全部 URL 元数据。
- ShareExtension：先验证全部附件数量与类型，优先选择 EPUB，再严格串行加载 NSItemProvider；provider 提供的临时 URL 只在各自 callback 内有效，必须在 callback 返回前完成复制。
- 取消等待当前回调、复制清理及锁释放后自动关闭扩展，无需再次点击完成；清理失败则保留错误提示。
- 扩展只复制文件，不解析整本、不写 SQLite，跨进程锁协调；用户回到主应用确认入库。
- 临时权限和共享容器能力需要真实平台配置，见[开发说明](development.md)。

### DesktopImportSource

桌面适配器共用于 Windows / macOS，由调用方注入环境隔离的 `AppPaths.importInbox`（`users/import-inbox/`）并负责关闭。选择器支持 TXT / EPUB 多选；原始路径仅用于接收时读取，不进入领域模型或持久回执。macOS sandbox 需要 `com.apple.security.files.user-selected.read-only` entitlement。

接收沿用公共协议的批量与大小上限、按 order 恢复、整批暂存后原子发布及按 ID ack；文件内容和回执在发布前 flush。每个进程对同一 inbox 只持有一个适配器，实例内请求串行执行，文件锁用于进程间协调；关闭只取消未发布的接收，保留待确认批次。恢复只回收 working、ack 墓碑和空 pending，损坏的已发布批次报告 storage 并保留文件。此实现不承诺目录 fsync 或物理断电恢复，也不读取移动端 legacy 单文件 inbox。

取消等待输入流关闭及暂存清理完成；file_selector 无主动关闭系统对话框的 API，取消或关闭适配器后忽略该对话框的晚到选择，不再复制文件。选择器自身取消保持静默。

## TXT

支持严格 UTF-8（有 / 无 BOM）、带 BOM 的 UTF-16 LE / BE、GB18030 / GBK。无 BOM UTF-16 在字节分布提供保守证据时列为候选，也可手动选择；候选均须全输入严格解码。存在编码歧义时提供头/中/尾合计最多 600 code points 的预览确认，不用 replacement character 静默吞错。换行归一化，保留正文空白；保守识别章节标题，无可信标题则整文件作为正文。

WHATWG 编码映射与许可保留在工程，生成工具位于 `tool/encoding/`；不通过在线猜测编码。TXT 输入上限 16MiB，最多 100000 块、10000 章。

## EPUB 普通正文

支持无 DRM 的流式 EPUB 2/3，以 OPF manifest / spine 为阅读顺序；不支持的 spine 格式可沿包内 fallback 选择 XHTML 替代，循环/断链拒绝；不按 nav / NCX 重排正文。目录可嵌套、可指向同文件 fragment，目录保留 `linear=no` 条目，连续翻章跳过这些条目（旧书需重新解析）；不能把「一个文件」或「一个目录标题」直接当作用户卷数。

原生正文支持段落、标题、分隔线、换行、pre 文本、基础对齐与 em 缩进；普通 HTML 块去除源码边缘可折叠空白，保留 NBSP / 全角空格与 pre，不用源码缩进抵消正文缩进。支持 PNG / JPEG / GIF / WebP，SVG 包裹的位图可提取（支持 href 与带命名空间的 xlink:href），纯 SVG 不在兼容范围。图片缺失显示占位，不丢失前后正文。段落及标题内明确以 em 指定小尺寸的栅格图片保留为行内内容（高不超过 4em、宽不超过 8em），随字号参与原生换行和分页；独立块级图片及其他尺寸仍走普通插图。已有导入需重新解析后生效。

原生富样式子集保留文字颜色、相对字号、粗体与斜体；em / % 嵌套计算，px 字号以 16px 为基准转换为有界比例，随用户字号缩放。普通正文的基础字号、行距和段距由阅读设置控制，无自带背景的黑白文字跟随阅读主题。

简单文本容器可保留 width / max-width、统一 padding、实线 / 虚线边框及纯色背景，同组语义块共享边框并可跨页；宽度不超过阅读区域。接近白／黑的中性背景在渲染时随纸色映射，文字与背景配对调整；明显彩色背景保留，暗色下文字与边框按需调整明度。原始颜色不变，切换主题无需重新解析。暂不还原嵌套装饰框、多方向 padding、完整 CSS 盒模型或 flex / grid。富文本测量、链接显示和行内图片使用同一套 span 几何，不转为整页图片或 WebView。旧书需重新解析。

章节开头最高级标题可提升为章节级显示，解决原书使用 h4 而未命中标题优化的问题。原生标题样式见[阅读器](reader.md)。

整体为 reflowable 的 EPUB 可包含能归一为单张位图的 `rendition:layout-pre-paginated` spine 页（包括 SVG image 包装），沿用原生图片、目录、阅读顺序和进度，不生成特殊 HTML 呈现。固定图片页允许忽略明确无填充或填充透明、且无描边的 SVG 矩形链接热区；不保留其点击交互，也不转为整图链接，导航仍使用 EPUB 目录。固定页仅接受简单容器与基础布局 CSS，可能改变图像、热区绘制或生成内容的样式保守拒绝。整本 pre-paginated / fixed-layout=true、固定文字、多图和 SVG 图形仍不支持；page-spread 属性不影响 layout 判定。

## EPUB 特殊短页

对实际应用了浮动、定位、变换或竖排等样式、且文本不超过 2000 字符的短页，提供受限静态 HTML 展示，适配扉页与标题设计。普通长正文仍走原生分页，不承诺完整 CSS / 固定版式支持。

- 仅允许安全元素和样式，移除脚本、表单与 iframe，关闭 JavaScript，使用严格 CSP，禁止外部请求。
- 含单张包内位图、定位文字和基础矩形的受限 SVG 短页可保留视觉布局；作者用 `<a>` 包住的矩形热点经校验后交由 Reader 执行书内跳转，原始 href 不进入 WebView。复杂 SVG 仍退回原生正文。
- Android / iOS / Windows / macOS 共用 `flutter_inappwebview` 呈现封装；初始化、页面加载失败或超时后切回该章的原生语义正文。Windows 在首次使用时检查 WebView2 Runtime，浏览器数据写入环境隔离的应用可写目录。
- 本地图片、字体内嵌；字体单项上限 8MiB、单文档生成 HTML 上限 16MiB。
- 导入与重解析共用同一写入路径：特殊页呈现（包括「没有特殊页」的空结果）与 manifest 一起发布，hash 进入受校验 manifest；同一次呈现解析找到的 SVG 热点并入链接侧表，读取时不再解析原件。呈现超出自身限额时不保存呈现，书籍照常以原生正文导入。未保存呈现的旧导入仍可从原件校验后派生与已发布正文 revision 一致的特殊页，结果只进内存、不回写；不会替换语义正文。派生缓存有界。
- 通过 `LocalPagePresentationRepository` 提供可选呈现，与 `LocalNavigationRepository` 的目录能力分开；标准阅读进度继续使用本地章节身份。

## 输入边界

EPUB 输入上限 64MiB。ZIP 限制 4096 项、单项解压 16MiB、总解压 256MiB，以及膨胀比 `(压缩字节 + 1024) × 200`；校验目录 / 本地头、CRC，拒绝分卷 ZIP、ZIP64、符号链接和越界路径。合法相对 href 可在书内解析，解码一次后仍必须留在根目录。

XML 单项 4MiB、文本累计 12Mi UTF-16 单元，DOM 100000 节点 / 深度 128；目录 10000 项 / 深度 32，单章最多 100000 块，去重图片累计 128MiB。拒绝 DRM、整本固定版式及复杂固定页面、内部 DTD / ENTITY，不解析外部实体。

存储层另有限额：原件 128MiB、单媒体 32MiB、媒体总量 512MiB、manifest 32MiB、媒体写入 4096 项。解析限制和存储限制独立生效，不能用 ZIP 文件体积代表最终内存成本。

不将上述支持列表解释为所有发行商 EPUB 都已验证。

已有导入记录保存解析结果；解析器修复不会自动重写旧 manifest，相同文件再次导入也会命中去重。可从本地文件管理菜单显式“重新解析”，保留原件并尽量恢复位置，近似恢复会提示；不要通过删除重导迁移，删除会清阅读进度。

当前能力以[支持矩阵](local-import.md#解析支持矩阵)为准。

样式表按文档顺序加载，原生正文与特殊短页共用屏幕筛选规则（空 media / screen / all），不启用打印、alternate 或 disabled 样式；复杂媒体条件不猜测。正文语义保真与 CFI 的剩余边界见[支持范围](local-import.md#解析支持矩阵)。

可选 stylesheet、CSS `@import` 与 presentation 样式依赖的非法包路径按缺失资源跳过，不猜测或修正目标路径；读取资源时仍执行大小限制。container、manifest、spine 与正文图片引用保持严格包内路径校验。

### 图片候选与 base 边界

EPUB 支持包内 picture/source 与 srcset 候选，按固定顺序选择可用栅格图片；不根据 viewport/sizes 进行响应式选图。原生正文、guide 封面与特殊页共用候选规则。未声明在 manifest 的包内图片继续容忍；base/xml:base 仍不解释，包根绝对路径形式仍拒绝。详细候选上限见下方“图片选择细则”。

### 解析诊断

EPUB 解析结果在 data 层附带最多 100 条固定原因码及截断标记。BookDecoder 可由调用方注入独立诊断 slot，读取最近成功解析报告；默认不保留，不写书籍文件或进度，不包含路径/正文。生命周期见下文。

### 显式重新解析

原件保持不变，新 manifest/媒体/特殊页先写暂存，再发布到 `revisions/<bundle>/`。SQL 事务原子切换活动指针与阅读进度，失败或取消保持旧版本；成功后清理旧资源。无历史不创建历史，无法精确匹配的位置明确提示近似，清除旧像素布局提示。TXT 新记录保留选择编码，旧记录可预览重选。

旧书升级后若特殊排版退回普通文字，可能是旧正文与重新派生的特殊页版本不匹配；使用此入口后重新打开即可应用新结果。当前没有自动提醒。

本地文件页提供「全部重新解析」：确认后按当前书籍列表逐本处理，显示当前书名与进度；失败保留该书旧内容并继续，结果汇总成功、失败、未处理数量及近似恢复提示。停止或离开页面会取消当前处理，不回滚已完成的书籍；TXT 沿用各书保存的编码，需要确认时逐本选择。

维护开始会退役已打开的 Reader，结束后从书架重新打开；旧会话及不匹配的新会话不能写旧正文进度。匹配、并发及崩溃恢复边界见下文。

### 正文辅助链接

新导入或重新解析后的 EPUB 可在阅读菜单“本章注释”查看本章脚注和包内链接：脚注直接显示注释原文，较长时展开阅读；链接注明去向（本章内、目录中的章节名或书中其他位置），不可用的链接列出原因且不可点击。普通辅助文档进入临时阅读页，返回保留原页面，不写主阅读历史。同文档链接保留当前 occurrence，跨文档使用首次出现。缺失或外部目标不可用，不触发联网。


原生正文识别 EPUB `noteref`、ARIA `doc-noteref` 和多看脚注入口；以数字上标替代入口图片或文字，点击在底部面板显示包内 `footnote` / `endnote` 注释原文，长注释可滚动，关闭后保持阅读位置。明确标记的脚注正文不重复进入主阅读流，隐藏脚注容器也可作为注释来源；界面及无障碍文案支持中英文，注释不自动翻译。旧书需显式重新解析。
原书目录页保留为书中内容，普通文字内链可直接点击，跨段链接的各段均可点击；“本章注释”菜单仍可使用。同章目标原地定位，主阅读顺序中的目标直接切章，其他文档打开临时辅助阅读页。非 spine XHTML 辅助文档独立保存，WebView 导航关闭。正文链接目标保留语义块及块内字符偏移，定位包含锚点的页面；隐藏目标不揭示。旧书需重新解析才能获得正文点击范围及目标字符偏移。

## 图片选择细则

按 picture/source、img src 或 SVG href、img srcset 顺序寻找实际存在且字节可识别的 PNG/JPEG/GIF/WebP，候选按声明顺序。source 只接受支持的 type 和空 / all / screen media。w/x 描述符仅校验，不实现响应式布局；每个消费点最多 64KiB srcset 和 128 个候选。外部或缺失候选跳过，根越界仍拒绝。特殊页选定后移除 source/srcset 并内嵌资源，沿用特殊页 8MiB 资源预算。

## 诊断生命周期

诊断保持在 data 层：`ParsedEpub.diagnostics` 返回不可变 `EpubDiagnostics`，只有固定 `EpubDiagnosticCode` 列表和 truncated 标志。每次解析最多 100 条，超出只设置截断标志；不累计无界计数，不附带文件名、路径、URL、正文、书籍 ID 或原始异常。顺序表示发生顺序，重复原因可能来自不同候选，不等于受影响图片总数。

`BookDecoder(epubDiagnostics: slot)` 可选接收调用方拥有的 `EpubDiagnosticSlot`，worker 成功返回且媒体写入、取消检查完成后替换最近一次报告。slot 不保留书籍身份；需要与单次操作对应时调用方使用独立 slot。`clear()` 显式释放；失败、取消和 TXT 不更新“最近一次成功 EPUB”报告，不能把旧报告当作本次结果。默认解码器不持有 slot，没有隐藏全局服务、自动日志或新 UI。

不修改 LocalBookContent / LocalBookDecoder 的领域合同，不写入 manifest，也不改变正文摘要或 blockKey。派生特殊页重建没有自动发布到 slot。已有导入不会因增加诊断而重解析。

## 重解析位置与并发

本地文件管理菜单新增“重新解析”，确认后从托管原件解析。保留书籍 SHA-256、导入日期、书架加入日期和最后阅读时间；无阅读历史不会新建进度。旧 TXT 未记录编码时提供严格预览及手选；新 TXT manifest 保存已选编码，重解析入口允许覆盖。

位置迁移为纯 Dart 函数：同 revision/块身份、唯一语义及邻近上下文、最多三个相邻块的文本窗口，最后降级到同章比例或最近可读章节起点。文本按 Unicode code points 计数。窗口最多 16384 code points，局部锚点最多前后各 32 个，重复候选不强行当作精确。拆分/合并窗口恢复及比例恢复均显示近似提示；近似结果清 completed，所有结果清像素提示。短文本、不唯一或窗口外的修改允许降级，不承诺原行位置。

旧 EPUB 读取不再把新解析的 catalog/chapters/navigation 替换进内存记录。旧特殊页仅在对应正文 revision 相符时派生；新导入与新 bundle 均保存受限呈现 JSON，hash 进入受校验 manifest。原件与媒体仍各自校验 SHA-256。

- 用户库 v4：local_books 增加 active_bundle、parser_version、maintenance，另增 local_chapter_revisions。NULL bundle 兼容旧根目录格式；升级不自动重新解析。
- 原件长期只保留根目录一份。暂存副本用于解析，完成后删除副本，manifest/媒体/呈现进入不可变 revisions/bundle。
- SQL 同一事务更新活动 bundle/hash、已有书架快照、进度与 generation、章节版本索引。提交前取消或 SQL 失败不切换；提交后返回真实成功，清理失败使用 cleanupPending。
- 维护期间拒绝新进度会话及旧写，发 invalidation 退役 Reader。结束后本地仓库发布 detail/catalog/chapter 更新；目录和特殊页后续读取取当前版本。即使旧内容重新申请 generation，正文/catalog revision 校验也拒绝不匹配写入。
- 迁移快照记录 generation/sequence，最终提交重新核对。期间 clearHistory 会改变 stamp 并阻止发布，不恢复用户刚清除的历史。普通进度保存被 maintenance 阻止，不覆盖待迁移快照。
- 启动先读 SQL 再清 staging/未引用 revisions，并解除遗留 maintenance。活动 manifest 缺失或校验失败时保留已有文件，不因坏指针删除旧资料。不是提供历史版本回滚 UI；正常提交后回收旧资源，避免版本无限累积。
- 文件发布仍依赖已有 flush + rename + SQLite 事务策略。测试覆盖人工构造崩溃遗留状态，未执行物理断电或真实磁盘耗尽，不宣称硬件掉电证明。

## 重复资源身份

EPUB 3 同一规范资源路径出现多次时逐次呈现；首次章键不变，后续以独立摘要 kind 和 `[path, occurrence]` 派生，避免与路径字符串冲突。复用资源块、媒体和呈现；额外重复块预算 100000、spine 条目 10000，超限拒绝。

EPUB 2 重复引用保持拒绝；只有明确 package version=3.0 使用 EPUB 3 分支。nav/NCX href/fragment 指向首次出现，连续阅读按实际 spine 顺序。插入同资源 occurrence 可能改变后续身份，不承诺永久稳定。同文档辅助链接保留当前 occurrence，连续阅读跳过 linear=no。

## 解析支持矩阵

| 能力 | 当前支持与限制 | 回归入口（test/data/local 下） |
| --- | --- | --- |
| ZIP / container / OPF | 有界解包、CRC、路径校验、manifest/spine 顺序；多 rootfile 选择首个匹配项 | parsers、epub_structure、epub_boundary |
| EPUB 2 / 3 目录 | NCX/nav、嵌套标签与 fragment；可选目录损坏可降级；内部存储章节以 spine 文档为单位 | epub_structure、epub_boundary |
| 路径与 fragment | Unicode、百分号一次解码、大小写精确；目录缺锚点可回章首，正文链接缺锚点明确不可用 | epub_structure、epub_links |
| 重复 spine | EPUB 3 occurrence 独立身份，同文档链接保留 occurrence；跨文档指向首个 occurrence；EPUB 2 重复拒绝 | reparse、epub_links |
| 正文语义 | 段落、标题、br、缩进、对齐、常见 ruby 基字/注音；复杂 ruby 保留括注降级；强调/上下标无完整富文本样式 | epub_compatibility、epub_prose_semantics |
| CSS | 受限选择器、顺序/media、important、white-space 与 visibility；隐藏元素不保留原生几何占位，非完整 cascade | epub_stylesheet、epub_prose_semantics |
| 图片 | PNG/JPEG/GIF/WebP 字节识别、SVG image 包装、srcset/picture 包内候选；确定性选图，不按 viewport/sizes 计算；缺图占位 | epub_compatibility、epub_resources |
| 特殊页 | 受限静态 HTML；保留部分复杂排版，脚本/外链受限；不保证完整出版方布局 | epub_presentation |
| base/xml:base | 不解释，按所在文档解析；这是明确未实现的兼容变体 | epub_resources |
| 未声明图片 | 容忍包内可识别位图，不声称符合完整 manifest 规范 | epub_resources |
| 辅助链接 | 原生文字内链与“本章注释”菜单导航；脚注使用数字上标及底部面板；linear=no 不参与连续阅读；WebView 导航关闭 | epub_links、epub_footnotes、reparse；widget local_links、footnotes |
| 诊断 | 每次至多 100 条 data 层原因码快照，不存正文/本机路径；无持久化/UI | epub_diagnostics |
| TXT | 严格 UTF-8/UTF-16/GB18030、BOM 优先、歧义预览、保守标题识别、原始 code point 身份；16MiB 上限 | txt 系列 |
| 旧书与重解析 | 已发布 manifest 稳定读取；用户显式重解析，在暂存区生成并原子切换；精确或近似迁移位置，失败/取消保留旧书 | reparse；domain reparse_position；widget local_reparse |
| 重启恢复 | schema v4、活动 bundle、进度和辅助资源恢复；旧会话晚写拒绝 | reparse、database migration |
| DRM / 固定版式 / SMIL / 互动 | 拒绝或受限静态降级；无 DRM 解密、媒体同步、通用浏览器排版 | epub_boundary、epub_presentation |

表中入口为文件名主题，不意味着每项已在手机验证。图像可解析不等于设备 codec、排版、裁剪均通过。
