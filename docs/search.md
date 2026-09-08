# SEARCH-001：搜索状态与请求竞态（2026-09-07）

> iOS 状态更新（2026-09-08）：Mac / Simulator 已可用，当前证据见 [IOS-001 报告](validation/ios-001.md)。本次观察到搜索页显示；未受控验证 Search / Enter、请求预算、分页或 swipe-back。下方带日期的 `DEFERRED_NO_MAC` 等结论是当次历史记录，不代表当前环境。

状态：DONE。SearchController 位于 lib/features/search/search_controller.dart，继承既有 ScopedController，显式注入 NovelRepository、SourceId 和 supportsPaging，不依赖 Source 协议、计时器或全局服务定位。SearchState 是不可变快照，items 复制为只读列表。

## 提交、编辑和分页

- 构造与 edit 无 I/O，无 debounce。draftKeyword 保留用户输入，submit 才 trim 并记录 submittedQuery；空白提交回到 idle，不发请求。按钮 / 键盘 Search / Enter 在 SEARCH-002 统一调用同一 submit；本项没有提前实现页面事件。
- 首次 / 重新提交清空旧 items 与 cursor，进入 loading。同 query 首屏或分页在途时重复提交不发新请求。初次失败为 error，合法空结果为 empty；请求取消不展示失败。
- 每次实际编辑取消旧请求并移除续页资格。旧 items 可以保留，但 submittedQuery 仍标记其所属查询、needsSubmission=true；即使编辑回原文本也须重新提交，不能复用已作废 cursor。
- loadMore 仅在结果就绪、未编辑、支持分页、有 cursor 且没有分页在途时启用。分页失败保留已有 items/cursor 并设置独立 paginationFailure，可明确重试；成功才追加，终页停止。无分页能力忽略 nextCursor。
- 请求对象身份与取消令牌共同阻止晚响应更新；编辑期间或关闭后到达的成功 / 失败均忽略。重复页 ID、已消费或原样返回 cursor、跨源结果返回 parse，保留已接受的旧结果并移除续页资格，不循环请求。
- Controller 持有自己的请求令牌，onClose 取消；Repository 只借用，不关闭。原始 Repository 异常防御性映射为标准 sourceUnavailable，不向 UI 泄漏异常内容。

## 验收与下一步

新增9项可控 fake Repository 测试，覆盖输入 / 停顿零请求、重复提交和翻页、乱序响应、编辑取消、保留结果查询标记、分页重试、重复 cursor / ID、无分页 / 空 / error、关闭晚结果及不可变状态。完整 **235项离线测试 PASS**，analyze **No issues found**；本机 .tooling/evidence/search001-tests.txt。

本轮无网络请求、没有新增依赖、页面文案或原生代码；未构建/安装模拟器新包。iOS Level A：状态机不依赖键盘平台事件或平台 API；iOS runtime仍DEFERRED_NO_MAC。按钮/Enter的实际事件、屏幕布局、翻译和导航在SEARCH-002验收，不能以本项Controller测试冒充页面已完成。

## SEARCH-002：搜索页面与结果导航（2026-09-07）

状态：DONE。`SearchScreen` 显式借用 NovelRepository、SourceId、AppRoutes 与分页能力，通过 ControllerScope 持有并释放 SearchController。输入与停顿不请求；按钮、软键盘 Search 和实体 Enter / 数字键盘 Enter 统一提交。中文输入法仍在组词时，实体 Enter 留给输入法处理，不触发搜索。

采用现有 Shiori 主题、最大840宽的居中纵向列表和稳定2:3书签封面占位；标题最多两行，完整标题及作者保留在可点击的无障碍语义中，缺作者省略。当前任务只交付封面占位，不发媒体请求。表单和结果共用可滚动区域，支持键盘避让、大字及长文案，不锁文字缩放。

初始提示、加载、无结果、首屏错误、已有结果、分页加载/错误/终页分别展示。所有新增界面文案使用中英文 ARB，并通过 gen-l10n 生成。编辑时旧结果保留所属查询说明和待提交提示，隐藏分页入口；分页错误保留结果，只有可继续且失败策略允许时显示重试。错误复用 FailureView 的访问限制、unsupported、冷却和取消规则。

点击条目将完整 NovelKey 传给 NovelDestination，不拆站点 ID、不放入 route name；返回搜索保留草稿与结果。详情页面内容仍待 DETAIL-001，默认 AppRoutes 明确显示开发中。开发菜单新增“离线搜索”，搜索 `a` 可体验现有 FixtureSource 的多页结果；开发环境按路由创建和关闭，生产搜索组件不导入 dev，普通入口未注入 fake 或自动启用生产联网。

验证：新增 **10项 widget 测试**，覆盖输入停顿零请求、按钮/软键盘/实体 Enter、中文组词保护、晚响应丢弃、所有主要状态、分页失败/重试、准确身份导航及返回、开发入口分页、中英文320宽/2倍字/300高键盘占位及明暗布局。完整 **245项离线测试 PASS**（`.tooling/evidence/search002-tests.txt`）；`flutter analyze --no-pub` 无问题；最终 `flutter build apk --debug --no-pub --target lib/main_dev.dart` PASS。

本轮无真实 Source 请求、无新依赖及原生改动，未安装或运行模拟器新包。Android 真实键盘/back 手势实测按任务范围留 UX-001。iOS Level A：使用共享 Flutter 表单、SafeArea、Navigator 和既有 Cupertino 路由，无 Android-only 分支；iOS keyboard/swipe-back runtime 仍 DEFERRED_NO_MAC，留 IOS-003。下一项为 DETAIL-001，不自动开始。

后续 DETAIL-001 已将开发离线搜索的 NovelDestination 接入正式 DetailScreen，复用同一 Fixture 环境及图片仓库；搜索→详情→返回保留结果的 widget 闭环通过。此处早期“默认详情开发中”记录为 SEARCH-002 当时边界，当前详情元信息已可操作，阅读/书架仍待接线，见 [详情验收](novel-detail.md)。
