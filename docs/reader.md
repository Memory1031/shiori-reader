# READER-002：单章阅读状态、块样式与操作栏

2026-09-07，READER-002 DONE。完整离线测试 91 项通过，静态分析无问题，普通 / 开发入口 Android Debug 构建通过；MuMu 新包安装、冷启动、排版、操作栏、滚动模式及返回验证通过。iOS Level A 兼容审查通过，实际构建 / 运行仍 DEFERRED_NO_MAC。

## 实现与边界

`ReaderScreen(chapter, repository)` 显式接收 ChapterKey 与 NovelRepository，按路由拥有局部 ReaderController。Controller 通过 cacheFirst 加载单章，呈现 loading / ready / typed error；重试遵守失败策略和冷却时间，返回或销毁取消当前请求，替换请求后忽略旧完成结果。共享 Repository 不由页面关闭；返回错误章节 Key 的结果拒绝显示。

本轮 ready 内容保持该次读取快照，不订阅后台正文刷新导致阅读中重排；缓存失败提示、更新策略和持久恢复仍按后续任务补齐。取消结果静默，可由用户重新加载；Domain 不允许完全无文字也无图片的空正文，这类内容应由数据层返回失败，不能伪造 ready。合法正文中的空段落保留 16 logical px 间隔，非空白字符和显式换行原样交给 Flutter 排版。

`ReaderContentView` 复用 READER-001 的两个视口，默认分页，操作栏可切换上下滚动；切换前捕获语义位置，交给目标视口恢复。标题按 level 区分字号并标记 heading semantics；段落支持 start / center 和 leadingIndent，Divider 独立渲染。共享 block_style 用于 TextPainter 与实际 Text，分页片段测量和显示使用相同样式 / 宽度。当前 leadingIndent 作为语义块首个 chunk 的起始侧整体内缩，尚非精细首行缩进；不改原文、blockKey 或持久模型。

操作栏默认可见，分页中央点击或滚动模式正文点击切换；拖动交由视口，不触发点击。左右外侧点击仍是章内前后页。显隐仅更新局部 ValueNotifier 控制区，视口 widget 保持不变；顶部 56 / 底部 64 logical px 保持预留，避免显隐导致重新分页。隐藏后保留带中英文无障碍标签的显示按钮。标题超长省略，模式按钮在窄屏可横向滚动；SafeArea 保留系统区域，不改变全屏 / 系统栏模式，返回沿用平台 Navigator。

图像块当前仅显示占位（alt / caption 或本地化“插图”），没有发起媒体请求。READER-003 才接实际解码、失败重试和尺寸策略。模式选择仅限当前会话，持久设置归 READER-004；持久位置保存 / 恢复归 READER-005 / 006；目录与跨章导航按 DETAIL-002、READER-007 / LOCAL-005 后续任务衔接。本地导入仍为规划，未实现。

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

下一可执行建议 NET-001 → NET-002 → MEDIA-001，再进入 READER-003；DB-001 → DB-002 可为设置、进度和本地导入解除前置。此次未自动领取后续任务。
