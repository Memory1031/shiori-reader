# ADR-07 / READER-001：双模式原生语义视口

> iOS 状态更新（2026-09-08）：Mac / Simulator 已可用，当前证据见 [IOS-001 报告](../validation/ios-001.md)。双模式阅读视口的 iOS 专项仍待验，本次只完成正式应用启动。下方带日期的 `DEFERRED_NO_MAC` 等结论是当次历史记录，不代表当前环境。

2026-09-07。**实验 Gate PASS，READER-001 DONE**。按用户在执行中的最终选择：**默认左右翻页，同时保留上下滚动**。这取代原计划「仅滚动、不做真实分页」的限制。两种模式共享原文锚点，模式/字号的持久化留 READER-004；本轮不将实验页算作完整 Reader。

## 决策与代码边界

后续 READER-002 更新：开发入口的实验按钮现名为“视口实验 / Viewport experiment”；“打开阅读器”进入正式单章页。正文中央点击已可由正式页面切换 Chrome；共享块样式与空段落间隔也已接入两种视口。下述 READER-001 数量及运行证据保留为当次记录，当前实现和验收见 [Reader 说明](../reader.md)。

采用原生 Flutter Sliver，不新增 indexed-scroll 或翻书动画依赖。上下滚动由 `ReaderViewport` 实现：目标 RenderChunk 作为 CustomScrollView.center，前文反向生长、后文正向生长。只维护已挂载单元的 RenderBox，整个视口一个 GlobalKey，没有给 2,000 段分配 GlobalKey，也不遍历整棵 RenderObject 树。

左右翻页由 `PagedReaderViewport`、`PageLayout` 实现：横向 CustomScrollView + 两侧 SliverFixedExtentList + PageScrollPhysics。按目标附近的文本行生成当前/邻页；TextPainter 负责原生文字测量，单次测量有界 RenderChunk，不实现字体塑形或自制排版引擎。前页从当前原文起点向前选取可容纳行，后页从当前终点继续，无需先分页全部前文。滑动和点击左右外侧 30% 区域都可翻页；中间区域暂不处理 Chrome。

页码只是当前视口内部相对索引，不存入 Domain、不当成全章页码、不伪造总页数。停止翻页后只保留当前位置附近最多 7 个页描述；native sliver 自身只构建视口附近页面。没有全章预排、整章 Column 或巨大整章 Text。页内 Column 仅包含本页有限片段。

`lib/features/reader/viewport/` 不依赖具体 Source、dev registry 或数据库；`lib/dev/ui/viewport_experiment.dart` 装配离线图片和临时模式/字号控件。开发检查页的「打开阅读器」进入实验，默认左右翻页，可切换上下滚动、跳到第 1 / 1,500 / 2,000 块或 75% 位置。生产入口没有新增 dev import/route/assets。

## 原文位置和 Unicode

RenderChunk 记录语义 blockIndex / blockKey、完整段落的 code point 起止和总长度；普通短段不切分，极长段默认按约 800 code points 切分。`characters 1.4.0` 提供 extended grapheme 边界，避免拆开 surrogate、组合音标或 emoji ZWJ 序列。一个超长字素不会为了满足软长度限制被拆断。

字符偏移与 Flutter UTF-16 索引仅在展示层转换。切分大小改变不修改 ChapterContent、contentRevision、blockKey 或持久 ReaderPosition。该依赖原已由 Flutter 锁定；本次仅从传递依赖改为直接依赖，版本、内容哈希、最低 OS 和原生插件均不变。

恢复先匹配 blockKey；找不到时按 chapterFraction 映射并通过 usedFallback 暴露降级。相同段落按完整段落字符比例找到新 chunk / 文字行；分页以目标字符作为局部排版起点，上下滚动对目标行做像素校正。fraction=1 定位末个可见字素，不进入空白的章外页。书/章身份选择和持久恢复状态机仍由 READER-005 / READER-006 负责。

上下滚动的 capture 读取首个可见已挂载单元，用实际排版对应的行首字符位置形成语义比例；图片则记录越过视口顶端的高度比例。换字号、宽高、文字缩放或 chunk 方案前保留锚点再恢复。图片内部尺寸变化由布局追踪器延后校正；用户主动拖动期间不抢回旧位置。上下滚动末尾留一个无语义视口高度的空间，使末块也能对齐阅读顶边。

分页图片整体缩放至本页可用高度，不跨页切图。未知比例用有界占位，实验图片解码后回报比例触发重排；用户拖动时图片重排推迟到停止后。分页模式切回滚动模式仍定位同一原文段落附近，不保存页号或 RenderChunk ID。

## 验收证据

宿主完整 Flutter 测试目前 **85 项通过**（既有 73 + 本轮 12）；静态分析通过。下列预算是 fixture 功能实验，不是 ARM64 profile 性能报告。

| 场景 | 验证结果 |
| --- | --- |
| 2,000 段 / 100,000 字直接进入第 1,500 块 | 宿主上下滚动挂载 <25、构建 <40；左右翻页附近测量 <50，无前缀布局 |
| 第 2,000 块、首块、fraction=1、双向连续移动 | 目标块可进入，首尾不会进入不存在的页；滑动、控制器和两侧点击均覆盖 |
| 100,000 字单段 | 相同布局重新恢复，用实际 RenderParagraph caret 坐标验证 ≤34 logical px（一行） |
| 字号 20→28、宽度 360→600、textScale 1→1.5、chunk 800→256 | 上下滚动仍在同段，原目标行偏差 ≤500 logical px（测试视口）；分页原文字符比例保持 |
| Unicode 正反向分页 | 汉字/日文/组合音标/emoji 拼接与原文完全一致，不丢字、不重字；chunk 边界均为字素边界 |
| 未知图高 180→700、拖动期间尺寸变化 | 上下滚动仍定位图片中部，非拖动校正到 -350±1 px；主动拖动期间不进入恢复 |
| 图片分页重排、大字 | 图片高 100→700，字号 20→32、textScale=2、小宽度280仍保留原块，不溢出 |
| 无障碍顺序 | 横向可见内容及纵向 pivot 前后列表的语义标签按原文顺序、无重复；未伪造全章页数 |
| 模式切换 | 75% 极长段锚点：Paged→Scroll→Paged 的原文字符比例偏差在约定范围内 |

Android 使用本项目已连接 MuMu `127.0.0.1:16384`（V2366GA / PD2366），独立探针的新安装包启动成功，当前进程输出：

```text
READER_METRIC vertical1500 mounted=20 built=22
READER_METRIC paged1500 measured=24 cached=2
READER_METRIC longParagraph fraction=0.74985 mounted=3
READER_VIEWPORT_PASS
```

探针还检查第 2,000 块、翻到后一页再返回、极长段、改字号和模式切换。这些是 Android fixture 功能/构建数量证据，不代表 60/120Hz 帧耗时、最终图片内存上限或 ARM64 真机性能。iOS Level A compatibility review PASS：原生 Flutter widgets/rendering/text API + 纯 Dart characters，无平台专用实现；iOS runtime 为 DEFERRED_NO_MAC，VoiceOver/TalkBack 真人使用验收仍随后续可访问性任务继续。

最终开发包也已安装启动，截图确认「打开阅读器」后默认左右翻页，横向滑动后正文换页；当前应用日志未见所检查的 E/flutter / FATAL / Unhandled。截图位于忽略目录 `.tooling/evidence/reader-paged.png` 与 `reader-paged-next.png`。普通 main.dart Debug 构建另行通过；设备保留开发阅读页，开发包另存 `build/app/outputs/flutter-apk/shiori-reader-lab-debug.apk`。

## 复验

```powershell
flutter test --no-pub test/widgets/reader --reporter expanded
flutter analyze --no-pub
flutter test --no-pub --reporter expanded

# Android 自动功能探针，等待当前进程的 READER_VIEWPORT_PASS。
flutter run --target test/support/reader_viewport_probe.dart -d 127.0.0.1:16384

# 日常人工实验：检查页点击「打开阅读器」。
flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=longChapter
flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=extremeParagraph
flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=unknownImageSize
```

本机 analytics/SDK 环境处理继续遵循 development.md。生成代码随 ARB 一起提交。

## 后续边界

READER-002 接入正式 ReaderController、章级加载/失败、完整块样式和 Chrome；READER-003 接生产 SourceImage、尺寸/解码预算；READER-004 增加模式默认值、偏好 schema 迁移和持久化；READER-005..006 接位置保存与完整恢复状态机。本轮没有更改 ReaderSettings v1 codec 或创建并行的进度模型。

本地分页还不提供纸张卷曲动画、固定全章总页数、跨章翻页或精细禁则排版；极端到连一行都容不下的视口不会强行裁掉文字，保留位置等待可用尺寸。测试视口覆盖的正常手机字号/缩放范围之外不作保证。正式图片缓存、性能门槛和真实设备验收不能由该实验代替。
