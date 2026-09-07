# 阅读器：单章状态、块样式、操作栏与图片

2026-09-07，READER-002 DONE。完整离线测试 91 项通过，静态分析无问题，普通 / 开发入口 Android Debug 构建通过；MuMu 新包安装、冷启动、排版、操作栏、滚动模式及返回验证通过。iOS Level A 兼容审查通过，实际构建 / 运行仍 DEFERRED_NO_MAC。

## 实现与边界

`ReaderScreen(chapter, repository)` 显式接收 ChapterKey 与 NovelRepository，按路由拥有局部 ReaderController。Controller 通过 cacheFirst 加载单章，呈现 loading / ready / typed error；重试遵守失败策略和冷却时间，返回或销毁取消当前请求，替换请求后忽略旧完成结果。共享 Repository 不由页面关闭；返回错误章节 Key 的结果拒绝显示。

本轮 ready 内容保持该次读取快照，不订阅后台正文刷新导致阅读中重排；缓存失败提示、更新策略和持久恢复仍按后续任务补齐。取消结果静默，可由用户重新加载；Domain 不允许完全无文字也无图片的空正文，这类内容应由数据层返回失败，不能伪造 ready。合法正文中的空段落保留 16 logical px 间隔，非空白字符和显式换行原样交给 Flutter 排版。

`ReaderContentView` 复用 READER-001 的两个视口，默认分页，操作栏可切换上下滚动；切换前捕获语义位置，交给目标视口恢复。标题按 level 区分字号并标记 heading semantics；段落支持 start / center 和 leadingIndent，Divider 独立渲染。共享 block_style 用于 TextPainter 与实际 Text，分页片段测量和显示使用相同样式 / 宽度。当前 leadingIndent 作为语义块首个 chunk 的起始侧整体内缩，尚非精细首行缩进；不改原文、blockKey 或持久模型。

操作栏默认可见，分页中央点击或滚动模式正文点击切换；拖动交由视口，不触发点击。左右外侧点击仍是章内前后页。显隐仅更新局部 ValueNotifier 控制区，视口 widget 保持不变；顶部 56 / 底部 64 logical px 保持预留，避免显隐导致重新分页。隐藏后保留带中英文无障碍标签的显示按钮。标题超长省略，模式按钮在窄屏可横向滚动；SafeArea 保留系统区域，不改变全屏 / 系统栏模式，返回沿用平台 Navigator。

READER-003 已接入实际图片，详见下节；未注入 ImageRepository 的未装配页面仍只显示占位。持久设置已由 READER-004 接入；持久位置保存 / 恢复归 READER-005 / 006；目录与跨章导航按 DETAIL-002、READER-007 / LOCAL-005 后续任务衔接。本地导入仍为规划，未实现。

## 开发入口

在场景检查页点击“打开阅读器 / Open reader”，通过同一 AppRoutes 工厂注入 fixture NovelRepository，打开正式单章页；加载失败时也可进入并验证错误状态。原 READER-001 实验单独保留为“视口实验 / Viewport experiment”。生产入口没有可用 Repository，仍保留既有未装配占位；没有把 fixture 注册进生产图。

```powershell
flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=typography
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
flutter build apk --debug --no-pub --target lib/main.dart
```

## 验证证据

- 91 项完整测试通过：原 85 项视口 / 数据 / 应用回归，加 6 项 Controller / 正式 Reader 验证。新增覆盖错误章拒绝、不可重试失败、图片章无媒体 IO、旧请求完成顺序与关闭取消、loading / error / retry / ready、操作栏显隐不重建视口、拖动不误触、切换模式锚点、长章懒构建、320×640 / 2 倍大字 / 长标题 / 空段 / Heading / 居中 / 图片占位。
- 静态分析通过、Dart 格式化完成、gen-l10n 正常生成。没有新增依赖、修改 Domain / Contract 或修改原生平台配置。
- MuMu `127.0.0.1:16384`：typography 开发 APK 安装 Success，冷启动 Status ok；截图检查中文 / 日文 / 英文 / emoji、标题、居中、缩进及分隔线；中央点击隐藏，显示按钮恢复，切滚动模式并拖动，系统返回到场景检查页。当前进程错误日志为空。截图和 UI dump 位于忽略的 `.tooling/evidence/reader002-*`，不作为源码资源。
- 普通 `lib/main.dart` APK 最终重新构建通过，未覆盖安装；模拟器仍为本次开发包。MuMu 不代表 ARM64 真机性能或 iOS runtime。
- iOS Level A：共享 Flutter Widget / SafeArea / Navigator，保留已有 Cupertino 路由装配；无平台分支、系统栏全局修改、插件或最低系统变化。真实 swipe-back、状态栏、安全区域与生命周期归 IOS-003 / IOS-004，尚未实测。

后续 NET-001 → NET-002 → MEDIA-001 已完成，见 [网络](network.md) / [媒体](media.md)，READER-003 也已完成；DB-001 → DB-002 可为设置、进度和本地导入解除前置。此次未自动领取后续任务。

## READER-003：图片展示与局部失败（2026-09-07 DONE）

共享 SourceImage 仅接 MediaRef 与显式 ImageRepository，拥有当前请求、独立 MediaLease 和 ui.Image。ReaderScreen / ReaderContentView 可注入 images；开发场景为正式 MemoryImageRepository 注入离线 Fixture SourceMedia，检查器与旧视口实验仍保留各自替身。生产依赖图尚未装配真实 Source，不作在线阅读已完成的声明。

已知尺寸按比例占位；未知尺寸以 180 logical px 起步。分页图片与 caption 整块限制在一页，滚动模式限制到两倍正文视口高度；图片 contain 显示。说明最多三行，长按 tooltip 可读完整说明，同一块计入布局高度。占位、错误和重试沿用同一几何尺寸；解码回报原始尺寸后更新比例，复用视口语义锚点恢复，拖动期间延后应用。已知比例与实际尺寸相同则不重排。图片没有独立分割为多页，也未实现图片缩放浏览器。

布局按需挂载可见与邻近块；离屏取消请求并释放 lease / decoded image。尚未完成的 codec 不能强制取消，完成后检查请求代次并立即释放过期结果。解码使用 ImmutableBuffer + ImageDescriptor，先取得尺寸，再按显示宽度 × DPR 缩小，不放大源像素，目标最多 4,000,000 像素；原始任一边超过 32,768 或总像素超过 100,000,000 时局部 tooLarge。动图仅显示首帧。MemoryMedia 和未来经过仓库验证的 LocalMedia 使用同一适配器；本轮没有实现文件缓存。重排导致块重新挂载时可能再次解码 / 获取媒体，当前无跨视口常驻缓存。

失败保留正文及操作栏，只在单图显示本地化错误说明和重试按钮；手动重试使用 refresh，遵守不可重试 / 429 冷却。沿用 gen-l10n 中英文状态文案，无新依赖和原生配置修改。

验证：

- 完整离线测试 **120 项 PASS**；新增 8 项涵盖真实 PNG 缩略解码、DPR、400 万像素计算上限 / 极端尺寸拒绝、过期解码释放、失败重试、慢请求取消、双模式未知尺寸 / caption / 语义块锚点、二十图邻近加载和卸载释放。滚动测试包含先拖动再加载；既有视口比例锚点和大字回归继续通过。
- 静态分析 PASS。Android Debug 图片探针构建、MuMu 安装和冷启动 PASS；实际输出 `READER_IMAGE_PASS codec=32x24 intrinsic=64x48 retainedBytes=0`。分页整图与 caption、切换滚动和图片渲染已截图检查，证据在忽略目录 `.tooling/evidence/reader-image-*.png`。运行入口 `test/support/reader_image_probe.dart` 全部离线，没有网站请求。
- 普通入口与二十图开发入口 Android Debug 构建 PASS。模拟器已恢复到开发包并打开正式二十图阅读页（截图 `.tooling/evidence/reader-twenty.png`）；最终普通入口 APK 仅构建，未覆盖安装。最终已知尺寸免重排优化另经 8 项图片测试及静态分析复验通过。
- 内存验证是 lease 释放后仓库 retainedBytes 归零及解码对象主动 dispose；不是操作系统 RSS 峰值或 ARM64 真机性能验收。高分辨率多图压力和真实网站媒体仍归 TEST-003 / TEST-001。
- iOS Level A：核对固定 Flutter 3.38.4 的 dart:ui codec / buffer API，并参考 [ImageDescriptor](https://api.flutter.dev/flutter/dart-ui/ImageDescriptor/encoded.html)；没有新增平台插件。iOS 实际解码、内存、生命周期仍 **DEFERRED_NO_MAC / IOS-004**。

DB-001 / DB-002 已完成，见 [本地存储](database.md)。READER-004 的交付见下节。

## READER-004：阅读偏好与布局变化（2026-09-07）

- ReaderScreen / ReaderContentView 显式借用 SettingsStore；ReaderPreferences 管理加载取消与有界串行写入。正式开发入口组装 PreferencesSettingsStore，使用 development 独立 key；测试 / fixture 仍可注入内存实现。普通应用壳的完整持久服务装配留给 CORE-005。
- ReaderSettings v2 新增 paged / scroll；v1 保留排版及主题并补 paged，不在读取时覆盖原存储。数值读取有限越界 clamp；坏 JSON、缺字段、未知版本 / 枚举和非有限值回退默认，复用 DB-002 安全诊断。构造与 copyWith 保持严格约束。
- 双语设置面板提供字号 14–32、行高 1.2–2.4、段间距 0–32、横向边距 12–48、浅色 / 深色 / 系统以及恢复默认。默认 20 / 1.7 / 12 / 20、system、paged。实时布局预览，300ms trailing 合并；slider 结束、面板关闭、后台与退出补写。慢写时至多一个在途加一个最新待写，不逐帧积累队列；读结果不能覆盖用户已改偏好，写失败可重试。系统强杀不保证尚未提交的最后一次修改。
- 两种视口消费统一字号 / 行高 / 间距和边距；文本测量、绘制及滚动字符定位采用相同间距。变更前 capture 语义锚点，沿用视口重布局恢复；不存页码、不修改正文摘要，不实现 READER-005 进度保存。系统文字缩放继续生效，面板可滚动，主题选项 Wrap，正文 Chrome gutters 固定。局部 AnnotatedRegion 保持状态栏图标对比，离开阅读器后由外层界面继续控制。
- 验证：新增迁移 / clamp、写合并与慢写顺序、退出补写、晚加载、失败重试、系统主题 / 明确覆盖，以及双模式排版 / 边距 / 锚点 / 2倍大字和窗口横竖变化测试；现有 DB-002 测试继续覆盖损坏默认与设置读写。完整 Flutter 测试 **133 项 PASS**，`flutter analyze --no-pub` 无问题，最终 Android 开发 Debug APK 构建通过。
- Android MuMu API32：开发包安装启动通过；实际读入旧 v1 字号26，滑动至32、选择深色，并在新进程重新打开设置确认保留；另次冷启动新转储确认 scroll 选中。2倍系统大字下深色面板可滚动，无当前进程 Flutter 渲染异常。最终含系统栏修正的开发 APK 已重新安装并打开阅读器，截图确认深色背景上的状态栏图标为浅色。截图 / UI 转储在本地忽略目录 `.tooling/evidence/reader004-*`。
- Android 旋转实测待补：本次 settings / wm rotation 指令未改变 MuMu 实际 display rotation=1，不能算旋转通过；widget 测试已验证 400×900 → 900×400 的位置保留。已恢复模拟器原 font_scale / 自动旋转设置。不是 ARM64 真机性能证据。
- iOS Level A：纯共享 Flutter / Dart 与现有 shared_preferences，无新插件或最低 OS 改动；SafeArea、系统缩放和平台亮度路径兼容。Runtime 仍 DEFERRED_NO_MAC，排版 / 系统栏 / 手势实测归 IOS-004。

READER-005 后续交付见下节。

## READER-005：位置追踪与有序保存（2026-09-07）

- ProgressTracker 为纯 Dart 会话编排器，借用 LibraryRepository。ReaderController 在正文 ready 后并发读取详情 / 目录快照；元信息成功且身份匹配才启用保存，不因读取或写入失败阻塞正文。元信息期间最多保留一个最新稳定样本，失败显示双语“阅读进度暂未保存”重试入口。
- 两种正式视口均发出布局稳定后的语义位置；文本按完整段落 Unicode code point，图片按越过顶部的高度比例。chapterFraction 重新计算，忽略错 revision / blockKey / index，不保存 chunk ID 或临时像素。恢复开始暂停采样和计时，稳定后继续；结束会话只补写之前接受的稳定样本。
- completed 独立于首可见锚点：末块底部已进入可读视口 / 分页末页即标记完成，所以无需滚动的短章也可完成。快速滑入尾部留白时记录最后语义块 fraction=1，不沿用起点。
- 普通变更采用 2s 周期与 300ms trailing 合并；至多一个在途写和一个最新待写快照。导航可 await flushProgress，ReaderController.onClose 补写，inactive / paused / hidden 尽力 flush。数据库分配 generation，sequence 随尝试递增；Success(false) 表示旧会话失效，停止写入，不重新抢代次。时间仅用于 UTC 展示，不参与新旧判定。
- 保存失败保留内存最新值，不紧密循环重试；滚动中的周期事件或用户重试可重试，停止后不无限重试。只在未保存状态变化时通知 UI，正常周期保存不会重建正文。后台 / 强杀只保证已成功提交的数据；正式跨章导航接线归 READER-007。
- 开发 main 使用 development SQLite 的 LocalLibraryRepository，连接由开发进程持有，路由只借用；启动失败显示可重试错误，不静默切回内存。createDevApp 和测试可显式注入替身。普通应用壳的完整服务生命周期组装仍归 CORE-005。
- 新增 10 项测试：假时钟 10s 连续更新写入≤6次、慢写合并 / forced close、恢复与非法输入、失败手动重试、晚旧章 / 清历史代次保护、双模式短章完成（含正式页面滚动落盘断言）、图片高度比例、分页恢复样本，以及 SQLite trigger 回滚 / 重试 / 关闭重开。最终完整 Flutter 测试 **143 项 PASS**，analyze 无问题，Android Debug 开发 APK 构建 / 安装通过。
- iOS Level A：纯 Dart Timer / 既有 LibraryRepository 与 Flutter 视口回调，无新增插件、全局 GetX 或最低 OS 修改。iOS lifecycle / 真机滚动写入仍 DEFERRED_NO_MAC，不能以 Android 结果替代。

READER-005 交付保存链路；后续 READER-006 的持久位置恢复见下节。

READER-005 Android 补验：用户切换到新的 MuMu 实例，ADB 为 127.0.0.1:16416，V2309A / API32 / 1440×2560。正式 development SQLite 初始化成功，短章无手势先记录 blockIndex=0、completed=1、generation=1 / sequence=0；最终修正版显式选择 scroll 并滚动后，设备内限定查询 dev-fixture / typography 得到 blockIndex=5、blockFraction=0、chapterFraction=0.625、completed=1、generation=3 / sequence=2，后台与 force-stop 后相同。未导出数据库，未查询其他书的记录。模拟器已重新启动到开发入口。实际验证发现并修复了正式滚动视口漏接采样回调，以及快速滑到尾部留白时沿用旧锚点的问题，正式页面滚动落盘断言覆盖此回归。iOS runtime、ARM64 真机性能以及 READER-004 的旧旋转待补项保持原状态。

## READER-006：持久位置恢复与内容变更降级（2026-09-07）

- ReaderController 在正文 cacheFirst 成功后读取该 NovelKey 的历史；只有 ChapterKey 一致才恢复其位置，显式打开别章从该章开头开始，不根据旧 ordinal 换章。章加载失败不建立写会话，保留旧进度；目录 / 选章入口仍归 READER-007 / PROGRESS-001。
- 恢复阶段为 loading → positioning → ready。旧进度和 SettingsStore 初读完成前不挂载正文视口，不产生临时章首写入。读取失败进入 readFailed：正文可读，暂停建立保存会话，并显示中英文重试提示；用户明确点重试才开启新的恢复轮次。恢复轮次作为页面 key，避免快速成功的异步重试复用旧页面状态。离开取消读取并忽略晚结果。
- 纯 Dart position_resolver 先核验同 revision 的 index / key 一致性，否则按 blockKey 查找；正文修订仍优先稳定 key。key 缺失时按 chapterFraction 映射新 blocks 和段内比例，并显示“内容更新，已恢复到附近位置”。重复文本只依赖确定性 occurrence 身份，不用全文模糊匹配。位置标准化为当前 revision / index / fraction；字符比例转回整数偏移时仅消除 1e-7 内的浮点往返误差，修复反复重开前移一行的问题。
- pixelOffset / layoutKey 字段仍向后兼容，但本次明确不使用像素捷径：双模式懒布局的 pivot 没有跨会话稳定的全章像素原点，字号相同也不能证明旧 offset 有效。恢复直接定位语义块，只测附近 chunks；读到像素提示会忽略，后续稳定写入不保留它。没有引入全章测量、chunk ID 或页码持久化。这是任务中可选像素优化在当前引擎下的保守实现决定。
- 分页恢复抑制布局中的采样，仅在当前轮次稳定帧发出位置；滚动恢复主动调度下一帧。拖动取消自动恢复，几何回调校验交互轮次；图片尺寸在拖动期间延后，应用时捕获用户当前锚点，已排队的回调也再次检查拖动状态。退出只允许 tracker 补写先前稳定样本，不把未完成恢复的临时坐标写回。
- 没有修改 Domain / Repository 公共契约、数据库 schema 或设置 v2；不包含 UI-002 的阅读纸色、外观偏好拆分或默认 Chrome 变更。

验证与误差矩阵：

| 情形 | 证据 | 结果 |
| --- | --- | --- |
| 同内容、同设置、重新打开（双模式） | restore_test：先保存实际采样点再创建新页面 | 同 block，字符误差 ≤1；包含旧进度和设置延迟时零临时写入 |
| Android 同设置与真实 SQLite 关闭 / 重开 | reader_restore_probe：原生字体、正式 ReaderScreen / LocalLibraryRepository、独立临时 fixture DB | 分页 0、滚动 0 个字符误差，满足 ≤1 行 |
| Android 正文容器 360×480 → 300×280 | 同一探针，两种模式 | 分页 0、滚动约 5 个字符误差，目标块可见；小于一视口 |
| 字号20→28、320×500→680×300、chunk800→160 | 双模式 widget fixture 极长段 | 同语义块，误差 ≤40 个字符；不保存 chunk identity |
| revision 改变、重复文本、错误 index、过期 pixel hint | 纯解析测试 | key 优先，occurrence 匹配；缺 key 映射 chapterFraction |
| 缺 key 提示 / 保存 | 正式页面 widget | 英文提示可见，仅写新 revision 的附近锚点；中文资源同步 |
| 图片晚完成与用户移动 | 既有真实 PNG 双模式测试 + 新图片高度测试 | 补偿后保持当前锚点，拖动后不返回初始保存点 |
| 读取中退出、读取失败重试、恢复中退出 | 新 widget 回归 | 晚结果不创建写会话，失败期间零写入，退出无异常 |

- 完整离线 Flutter 测试 **155 项 PASS**（UI-001 新增2项，READER-006 新增10项）；全项目 analyze 无问题。Android Debug 恢复探针构建 / 安装 / 运行 PASS，输出 `READER_RESTORE_PASS`，本机日志 `.tooling/evidence/reader006-android-probe-rerun.txt`。
- 最终普通开发入口 `lib/main_dev.dart` Debug APK 构建、安装和冷启动通过；MuMu 已恢复开发菜单，可进入“视觉样板”及各正式阅读 fixture。
- 首次 Android 探针在第三次打开临时数据库时返回 database failure，分页两项此前已通过；新进程重跑完整双模式通过。保留首轮失败日志，不将 MuMu 的数据库环境异常宣称已根治。未导出用户数据库，也未读取非 fixture 记录。
- Android 窗口测试通过改变正文约束完成，不等同系统旋转事件；READER-004 旧 MuMu 旋转待补项不据此销账。该探针验证 SQLite 关闭重开与 Reader 新会话，不冒充 OS 强杀后自动导航；启动后自动选择最近书籍仍归 PROGRESS-001。
- iOS Level A：仅共享 Dart / Flutter 与既有存储依赖，尊重 SafeArea、系统文字缩放、资源取消；runtime / 实际字体误差 / lifecycle 仍 **DEFERRED_NO_MAC / IOS-004**。Android emulator 结果不替代 ARM64 真机性能验收。
