# DETAIL-001：详情状态与元信息展示

> iOS 状态更新（2026-09-08）：Mac / Simulator 已可用，当前证据见 [IOS-001 报告](validation/ios-001.md)。本次仅验证正式应用启动，详情、目录与导航专项尚未补验。下方带日期的 `DEFERRED_NO_MAC` 等结论是当次历史记录，不代表当前环境。

2026-09-07，状态 DONE。详情组件位于 `lib/features/novel_detail/`，领域契约和 Source 实现未改变。

## 状态与生命周期

DetailController 显式借用 NovelRepository 和完整 NovelKey，在 onInit 先订阅对应 detailUpdates，再以 cacheFirst 加载。ControllerScope 使用书籍身份与 Repository 构成 Key，依赖变化时关闭旧 Controller；退出取消请求和订阅，共享 Repository 不由页面关闭。

手动刷新使用 refresh 模式，进行中重复刷新不增加请求。GetX 的 refresh 是通知方法，因此业务动作命名为 refreshDetail。详情接受 LoadResult 的 stale 与 refreshFailure：陈旧内容标注提示，刷新中保留元信息，刷新失败放局部提示，成功更新清除提示。未取得任何内容的失败使用完整错误视图；取消静默，原始异常防御性映射为标准 sourceUnavailable。访问限制及未到期/未知的限流冷却不通过刷新按钮绕过，数据层仍负责实际预算。

流通知优先于较早的初始加载快照；如果初次缓存返回前先收到失败通知，仍保留缓存内容和失败信息。错误书籍身份不展示，保留已有详情并报告 parse；不拆解站点 ID，不将站点字段带进 Controller。晚请求完成和退出后的事件不能更新页面。

## 页面与动作接口

- 封面复用 SourceImage / ImageRepository，固定2:3展示框，原图 contain；缺封面或未注入图片仓库时显示书签占位，图片失败不影响元信息。
- 展示完整标题、可缺省作者、简介、标签和本地化连载状态。缺简介有明确提示；标签和书籍原始内容不翻译。新增界面文案由中英文 ARB / gen-l10n 管理。
- 复用 Shiori 主题；最大840宽，内容区达到600宽时封面与元信息并排，窄屏纵排。SafeArea 与滚动布局支持长标题/简介、两倍字体和横屏；不固定操作区高度或裁掉完整详情标题。
- onRead / onShelf 回调传递完整 NovelKey；continueReading / isOnShelf 由装配者提供真实状态。未注入回调时按钮禁用且显示开发中说明，不假报阅读/收藏完成。目录留 DETAIL-002，收藏及开始/继续逻辑分别按 SHELF-002 / PROGRESS-001 接通。
- 开发菜单“离线搜索”已接入真实 DetailScreen 与同路由环境的 FixtureRepository / 图片仓库。搜索 `shortChapter` 可点开离线详情，返回后保留搜索草稿和结果。dev 环境仍仅由开发入口引用；本轮不装配普通首页或启用生产联网。

## 验证记录

新增10项测试，包括订阅先于加载、流通知/初始快照竞态、刷新 single-flight、取消释放、失败先于缓存、重试策略、原始异常归一化、缺字段、stale/刷新失败/成功更新、错误身份、依赖切换、动作 key、中英文大字/横屏/长内容、封面实际解码，以及搜索到详情再返回的闭环。

- 全量 `flutter test --no-pub --reporter expanded`：**255项 PASS**，本机证据 `.tooling/evidence/detail001-tests.txt`。
- `flutter analyze --no-pub`：No issues found。
- `flutter build apk --debug --no-pub --target lib/main_dev.dart`：PASS。
- 本轮无真实 Source 请求、无新增依赖及原生代码；未安装/运行模拟器新包，不能以 widget 测试或构建声称设备验收完成。
- iOS Level A：共享 Flutter 布局、SafeArea、gen-l10n、既有 Cupertino 路由和图片解码组件，无 Android-only 分支；实际 iOS runtime 仍 DEFERRED_NO_MAC。Android 设备交互收尾按 UX-001，iOS runtime 按延期轨道验证。

下一项 DETAIL-002：卷章节目录与选择，不自动领取。

后续用户已授权 DETAIL-002 / READER-007 / SHELF-002 / PROGRESS-001：目录按钮及准确 ChapterKey 导航、正式首页装配下的收藏/开始/继续阅读均已接通；详情元信息动作占位仅留在未注入动作的独立开发组件测试中。见 [闭环验收](reading-flow.md)。
