# 阅读器：单章状态、块样式、操作栏与图片

2026-09-07，READER-002 DONE。完整离线测试 91 项通过，静态分析无问题，普通 / 开发入口 Android Debug 构建通过；MuMu 新包安装、冷启动、排版、操作栏、滚动模式及返回验证通过。iOS Level A 兼容审查通过，实际构建 / 运行仍 DEFERRED_NO_MAC。

## 实现与边界

`ReaderScreen(chapter, repository)` 显式接收 ChapterKey 与 NovelRepository，按路由拥有局部 ReaderController。Controller 通过 cacheFirst 加载单章，呈现 loading / ready / typed error；重试遵守失败策略和冷却时间，返回或销毁取消当前请求，替换请求后忽略旧完成结果。共享 Repository 不由页面关闭；返回错误章节 Key 的结果拒绝显示。

本轮 ready 内容保持该次读取快照，不订阅后台正文刷新导致阅读中重排；缓存失败提示、更新策略和持久恢复仍按后续任务补齐。取消结果静默，可由用户重新加载；Domain 不允许完全无文字也无图片的空正文，这类内容应由数据层返回失败，不能伪造 ready。合法正文中的空段落保留 16 logical px 间隔，非空白字符和显式换行原样交给 Flutter 排版。

`ReaderContentView` 复用 READER-001 的两个视口，默认分页，操作栏可切换上下滚动；切换前捕获语义位置，交给目标视口恢复。标题按 level 区分字号并标记 heading semantics；段落支持 start / center 和 leadingIndent，Divider 独立渲染。共享 block_style 用于 TextPainter 与实际 Text，分页片段测量和显示使用相同样式 / 宽度。当前 leadingIndent 作为语义块首个 chunk 的起始侧整体内缩，尚非精细首行缩进；不改原文、blockKey 或持久模型。

操作栏默认可见，分页中央点击或滚动模式正文点击切换；拖动交由视口，不触发点击。左右外侧点击仍是章内前后页。显隐仅更新局部 ValueNotifier 控制区，视口 widget 保持不变；顶部 56 / 底部 64 logical px 保持预留，避免显隐导致重新分页。隐藏后保留带中英文无障碍标签的显示按钮。标题超长省略，模式按钮在窄屏可横向滚动；SafeArea 保留系统区域，不改变全屏 / 系统栏模式，返回沿用平台 Navigator。

READER-003 已接入实际图片，详见下节；未注入 ImageRepository 的未装配页面仍只显示占位。模式选择仅限当前会话，持久设置归 READER-004；持久位置保存 / 恢复归 READER-005 / 006；目录与跨章导航按 DETAIL-002、READER-007 / LOCAL-005 后续任务衔接。本地导入仍为规划，未实现。

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

DB-001 / DB-002 已完成，见 [本地存储](database.md)。READER-004 的持久阅读偏好前置已解除，尚未执行。
