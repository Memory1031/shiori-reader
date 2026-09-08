# 应用规范：UI、多语言、装配与导航

> iOS 状态更新（2026-09-08）：Mac / Simulator 已可用，当前证据见 [IOS-001 报告](validation/ios-001.md)。应用壳的 Simulator Debug 构建、安装和启动已通过；全页面 UX 与系统行为矩阵仍待验。下方带日期的 `DEFERRED_NO_MAC` 等结论是当次历史记录，不代表当前环境。

2026-09-07。CORE-004 DONE；完成应用壳和所需 widget 验收。Android Debug build PASS；初次模拟器安装失败的待项已在 DEV-002 补齐，同一应用壳的新开发包安装、冷启动和返回导航 smoke PASS，见下文补验记录。iOS Level A compatibility review PASS，实际 iOS runtime 仍为 DEFERRED_NO_MAC。

## UI 规范

本文维护当前有效的视觉与交互约定；任务状态及未完成验收集中在 [TASK_PLAN](TASK_PLAN.md#ui-待验收事项)。阅读算法 / 位置语义见 [reader.md](reader.md)，封面定位见 [书源说明](source/lightnovel.md)，缓存与图片生命周期见 [media.md](media.md)。不以视觉改造扩大 Source 能力或改变 Domain 契约。

### 整体风格与主题

采用日系文库感、封面主导、清楚且安静的排版。Material 3 提供交互、焦点及无障碍基础，视觉由 `lib/app/theme/shiori_theme.dart` 的语义 Tokens → ThemeData / ThemeExtension → 页面统一消费。避免 Card 套 Card、满页粉色、全页封面模糊及无数据依据的装饰状态。优先使用组件 Theme，不逐个包装所有 Material 控件。

| 角色 | 浅色 | 深色 |
| --- | --- | --- |
| paper | #FAF8F4 | #1B181C |
| surface | #FFFCF8 | #252126 |
| ink | #302C2B | #EEE7EB |
| secondary | #70686B | #BEB3BA |
| accent（默认青绿） | #52756B | #96CEC0 |
| accent（可选蓝灰） | #5B7185 | #ACC8DF |
| accent（可选暖棕） | #81694F | #DABB9B |
| accent（可选淡粉） | #976478 | #E5B6C8 |
| separator | #DED8D5 | #454047 |

亮色填充独立于前景强调色：鼠尾草绿 `#DCE9DE`、雾蓝 `#DFE8F0`、浅沙棕 `#EFE3D4`、淡粉 `#F3DFE7`，用于主要按钮、选中背景、主题色样点与空书架装饰；文字和操作图标保留较深的同色系以保证对比度。原有三套深色模式保持不变。

`surfaceSubtle` 由 paper 与 separator 插值构成。品牌色集中用于关键动作和当前选中态；普通图标、次级按钮、元信息使用中性色。错误状态有独立语义及文字 / 图标。正文与次要文字目标对比 ≥4.5:1，可操作图标和边界 ≥3:1；不能仅凭单个色值宣称所有组合通过。

应用外观支持明暗（跟随系统 / 浅 / 深）和主题色（青绿 / 蓝灰 / 暖棕 / 淡粉，默认青绿）。主题色由应用与 Reader 控件共用，保留现有布局、字体和纸张色；Reader 明暗、浅色纸色继续独立保存。Reader 支持纸白 / 暖纸 / 夜间预览，跟随系统时保留所选浅色纸色；不要以应用主题覆盖阅读偏好。颜色、圆角及动画参数留在 presentation，不持久化 ThemeData / TextStyle。系统动态取色不覆盖当前品牌调色板。

### 排版、尺寸与可访问性

- 系统字体与 CJK fallback；UI 中文 letterSpacing 为0，品牌名可独立调整。正文、章节标题、次级标题采用不同层级，并让测量与绘制消费同一套样式。
- Reader 默认18sp、行高1.7、段距8dp、左右20dp，宽屏单列最大680；不强求所有屏幕固定汉字数。保留已保存设置，恢复默认只重置排版项。源起始已有空白时不再加 UI 缩进，UI 首行缩进最多2em，标题不缩进；不改写源文本及位置身份。
- 书架标题15sp / w500 / 最多两行；搜索标题15sp / w600 / 最多两行；详情书名约20sp，可自然换行。作者缺失可省略，长标题保留完整语义或可访问的详情入口。
- 常用间距8 / 12 / 16 / 20 / 32，细节可用4 / 24；手机页面水平留白通常20。封面比例2:3、默认圆角8，普通控件约12，Sheet顶部约20。按内容层级取值，不把所有控件做成大胶囊。
- 缺封面、加载和成功保持相同展示尺寸；详情完整封面与正文插图避免裁切。网格随可用宽度和文字缩放调整列数，长列表懒构建。宽屏限制内容宽度，不另建平板业务模型。
- 支持中英、日文内容、横竖屏和系统文字缩放；至少覆盖1.0 / 1.3 / 2.0，关键操作可滚动到达，不全局 clamp 字号。触控目标至少48×48，图标有标签，状态不只靠颜色，手势动作须有可访问替代。
- 动效采用短反馈（约180ms）和页面 / Sheet过渡（约240ms），减少动画时停用非必要动效。颜色过渡不驱动正文尺寸动画；页面保留 Material / Cupertino 返回习惯。

### 页面与交互

| 页面 | 当前约定 |
| --- | --- |
| 根导航 | 书架为唯一首页，无底部标签导航；保留搜索与导入入口，不提供发现 / 推荐页，正常冷启动不自动进入正文或发在线请求。外部打开文件属于显式意图，按导入任务处理。 |
| 书架 | Shiori + 搜索 + 更多；更多包含历史 / 外观，不放 Debug 或未实施功能占位。继续阅读标题紧贴卡片，仅显示有事实依据的卷章和章内近似进度。默认网格，单个切换图标表示当前布局，点击同位置换成另一模式；tooltip 说明切换目标。 |
| 书架操作 | 点击书直接开始 / 继续阅读；网格长按提供详情 / 移除，封面无常驻更多按钮；列表左滑展开详情 / 移除，长按也可访问。滑动本身不删除。移出书架可撤销，保留进度 / 缓存；未来删除本地文件须与移出书架分开。 |
| 搜索 | 输入及停顿零请求，文字按钮 / 键盘 Search / Enter 显式提交，保留 IME 处理。浅底圆角输入框，结果采用68dp封面、书名和次级作者的紧凑浅底行；来源小 badge，提示文字低于结果主信息。区分初始 / 加载 / 空 / 错误 / 翻页失败 / 无更多，翻页失败保留已展示内容。 |
| 详情 | 克制的浅色封面区，完整书名 / 元信息 / 简介；阅读是唯一 filled CTA，收藏是次要操作。“目录 + 全部章节”作为内容区入口，不再做巨大目录按钮。 |
| 目录 | 区分分卷 / 特典列表与当前文章内目录；显示源提供的真实顺序与身份，卷内纯文本标题识别允许不完整，不伪造结构。轻量分组底色、序号 / 当前书签、清楚间距；背景裁剪在本行，随内容滚动。长标题可查看完整文本。 |
| Reader | 默认左右翻页，保留上下滚动。顶部返回 / 章节标题 / 更多，底部目录 / 进度 / Aa；详情和失败重试在更多，前后章在进度面板。隐藏时不留应用按钮，中部点击或 F2 唤回；系统栏仍保留。Chrome 不改变正文布局边界，进度为章内语义近似值，不冒充全书百分比或精确页数。 |

未保存或局部失败保留低干扰且可访问的恢复入口。加载优先保留已有内容，插图失败不阻塞正文；角色只用于克制的品牌 / 空状态，不出现在正文或掩盖错误。导入、额外设置、更新标记及离线完整度按相应任务和真实能力接入，不能因界面预留而标记功能完成。

### 原生启动屏与 Flutter 加载页

- 两个平台原生屏使用完整品牌原图和 Shiori，不复用低分辨率 AppIcon 裁切图；资源维护见 [品牌素材](../assets/branding/README.md)。无强制停留、运行时进度、版本号或口号。
- Android：112dp Logo + 约22sp静态字标，纸白 / 深色底。组合画布288dp，图层采用比例 inset，适配系统预渲染和缩放，不能回退为固定 dp 偏移。位置与掩模受系统约束。
- iOS：LaunchScreen.storyboard 使用标准视图与 Auto Layout；128pt aspect-fit Logo，24pt间隔，22pt Semibold 字标；160×184pt组中心位于屏幕高度45%，named colors 适配系统深浅色。布局已配置，尚未完成 Xcode / 设备验证。
- Flutter LaunchView 仅在真实初始化期间显示：128dp原图、轻光晕 / 边框、Shiori、双语短文案及加载指示；减少动画时使用静态指示。它与原生屏是不同阶段，不以第二阶段截图代替原生验收。

### UI 验证记录摘要

以下为历次交付证据摘要，不代表本次文档整理重新执行测试，也不意味着全页面真机验收通过。

| 范围 | 已有证据及边界 |
| --- | --- |
| UI-001 | 145项离线测试、analyze通过；MuMu核对中文书架 / 详情及英文夜间 Reader 样板；截图位于 `.tooling/evidence/theme-lab/`。样板不是生产业务验收。 |
| UI-002 | 正式主题 / 阅读偏好拆分及迁移见 [Reader](reader.md)，不重复维护第二份恢复矩阵。 |
| 页面收敛 | 历次完整离线回归272 / 276 / 281通过；272轮核对生产首页、发现及目录，目录截图 `.tooling/evidence/ui-production-current.png`。其他页面主要为 widget 证据。 |
| 手势与菜单 | 书架 / 首页 / 详情往返专项20通过，菜单专项7通过，模式图标与间距专项8通过。 |
| Flutter加载页 | 双语大字 / 小横屏 / 减少动画专项2通过；此前完整既有回归282通过。 |
| Android原生屏 | debug编译 / 覆盖安装、桌面冷启动截图 `.tooling/evidence/native-splash-final.png` 确认 Logo 完整及字标可见；直接 am start 的空白截图不算 Logo 验收。 |
| iOS原生屏 | XML、约束引用、asset JSON、图片尺寸及原图哈希检查通过；未执行 ibtool / actool / iOS runtime。 |
| 搜索封面与样式 | 搜索 / 媒体离线34项及analyze通过，Android debug编译安装通过；未新增源站探针。稳定 cover 引用按现有详情链路解析，不能据此断言搜索响应已返回封面 URL。 |

## 装配与范围

以下装配及验证段落保留 CORE-004 / UI-002 交付时的历史范围，不代表当前生产功能仍为占位；当前业务装配与完成状态见 [任务计划](TASK_PLAN.md) 和 [生产闭环](reading-flow.md)。

`lib/main.dart` 调用 `lib/app/bootstrap.dart` 的 `createApp`，组装 `ShioriApp`、应用级 `AppController` 和 `AppRoutes`。依赖通过构造器和页面工厂闭包传入；没有 Get 服务注册、Get.find、GetMaterialApp 或站点常量。

当前 production 尚未装配数据库或生产 Repository。UI-002 在 main / main_dev 中分别注入对应环境的 PreferencesAppSettingsStore，提供应用外观入口；createApp 可显式注入 AppSettingsStore，省略时为内存默认。应用明暗异步加载、即时预览，写入有界合并，失败保留当前预览并允许重试；加载晚结果不覆盖用户选择。完整服务装配仍归 CORE-005。

`AppRoutes` 接受 home/search/novel/reader 页面工厂。组装者在工厂闭包中捕获所需 Repository，再传入页面和 Controller；没有要求页面访问全局服务容器。SearchDestination、NovelDestination、ReaderDestination 分别携带不透明 SourceId、NovelKey、ChapterKey。路由名称只用固定 `/search`、`/novel`、`/reader`，不将身份或定位符放入日志可见的 route name / settings.arguments。

当前默认首页明确显示功能开发中，未注入的功能页面也是占位提示；没有提前完成 HOME/SEARCH/DETAIL/READER，也没有将测试 fake 注册到 release。后续 DEV-001/DEV-002 可通过同一装配入口传入开发专用工厂。

## Controller 所有权

Controller 的 GetX 用法限定为局部 GetxController / update 通知。`ControllerScope<T>` 在 initState 调用 create 一次并启动 onStart；重建保留同一实例。需要更换依赖时使用新 Key 或新的 route 实例，不能在 build 中重新创建 Controller，也不能把一个实例交给两个 owner。

Scope 退出时先移除自身 listener，再调用 onDelete 和 notifier dispose。`ScopedController` 的 onClose 取消生命周期 token 与已登记的 StreamSubscription，`resourcesReleased` 可供需要等待异步清理的测试或上层流程使用。借用的共享 Repository 不由页面关闭。

子类通过 listenTo 登记订阅，收到晚事件时基类检查 isClosed。普通 Future 的完成处理仍必须检查 isClosed、取消状态及请求代次；AppController 以独立请求 token 和实例身份实现覆盖旧请求的保护。覆盖 onClose 时调用 super；其他定时器、媒体 lease 等资源由实际拥有它们的子类释放，本轮没有媒体加载器或 ReaderController。GetX 的 onReady 是延迟回调，后续如使用它启动工作也必须先检查关闭状态。

## 导航与状态组件

- Flutter Navigator push/pop；iOS 使用 CupertinoPageRoute，Android 使用 MaterialPageRoute，保留原生平台的返回行为。页面工厂在 route builder 内执行，使 Controller 生命周期绑定页面。
- AppScaffold 提供 AppBar、SafeArea 和 Scaffold 默认键盘避让。主题采用 Material 3、系统明暗模式与粉色种子色；不锁死系统文字缩放。
- LoadingView、EmptyView、FailureView 使用可滚动布局及 Wrap 操作区，避免小屏、较大字体或键盘占位导致溢出。
- FailureView 只接收 AppFailure、动作回调及重试可用性。取消静默；never 不显示重试；其他可重试失败只有 owner 提供回调才出现操作。访问限制没有绕过入口；缓存/返回按钮也只由 owner 明确提供。
- rateLimited 在未知或尚未到期的冷却期禁用重试，owner 还可通过 retryAvailable 禁用。组件不自动轮询或重发请求，也不自建冷却计时器；后续 owner 在资格变化时重建，数据层仍须强制执行 NET-002 的预算和冷却。

## 多语言规范

2026-09-07 按用户最终选择采用 Flutter 官方 **gen-l10n + ARB**。当前界面支持 **中文（简体，zh）和英文（en）**，语言资源为 `lib/l10n/app_en.arb` 和 `lib/l10n/app_zh.arb`。`l10n.yaml` 以英文为模板，将类型安全的 `AppLocalizations` 生成至 `lib/l10n/generated/`。Widget 在 build 或 route builder 内使用 `AppLocalizations.of(context).retryAction` 等取值，不写死中文或英文，也不将翻译后的字符串存进 Controller / Domain。

MaterialApp 使用生成的 supportedLocales 和 localizationsDelegates，继续承载 Navigator。locale 为 null 时由 Flutter 按系统语言偏好列表匹配，zh 地区/脚本变体使用当前简体中文文案，en 地区变体使用英文；均不支持时回退 supportedLocales 首项英文。系统语言变化通过 Localizations 更新依赖它的界面，导航栈及 Controller 实例保留。

根组件的可选 locale 参数用于显式装配和测试。手动切换时由拥有语言偏好的上层更新该参数：英文使用 `Locale('en')`，中文使用 `Locale('zh')`，null 恢复跟随系统。不要为了语言切换重新运行 runApp、创建新 Controller 或清空路由。本轮没有新增语言选择页面或持久化偏好；未来增加时应明确手选语言的优先级，再接存储。业务服务继续显式注入，无 GetX 全局翻译状态。

ARB 使用两空格缩进、每个键单独一行，不在文件末尾零散追加逗号和键。新增文案同时补齐两份 ARB，键有含义而非直接拿中文当键；有歧义时补充 description。参数、复数及选择表达采用 ARB 的 ICU 语法和 placeholder 元数据，避免拼接句子；日期和数字按所选语言格式化并补测试。保留可伸缩/换行布局，不以中文短文案宽度固定英文按钮。

修改资源后运行 `flutter gen-l10n`，将 ARB 与生成的 Dart 文件一同提交，不手动修改生成文件。`pubspec.yaml` 启用 `flutter.generate`；CI 重新生成并检查生成目录是否存在差异。双语键完整性测试要求两份 ARB 的消息键一致、值非空，避免缺失中文时静默使用英文。

本轮已提取应用名、开发中提示、搜索/详情/阅读标题、设置加载提示、LoadingView 默认文本、所有领域失败提示以及重试/缓存/返回按钮。自定义 EmptyView.message 或 LoadingView.message 由调用者传入已经本地化的文案；品牌名 Shiori 两种语言保持一致。小说原始标题、作者、正文、来源标识和固定路由名称不自动翻译，领域模型与 AppFailure 不依赖 GetX。

实现对照固定 Flutter 3.38.4 的生成器；参考 [Flutter 官方国际化说明](https://docs.flutter.dev/ui/internationalization)。生成文件直接从应用源码目录导入。

## 依赖与平台审查

多语言使用 Flutter SDK 自带 `flutter_localizations`，生成代码直接使用 `intl 0.20.2`，因此将其声明为直接依赖，版本与固定 SDK 保持一致；GetX 仍为 4.7.3，仅用于局部 Controller。SDK delegates 提供 Material / Cupertino 标准控件及无障碍标签的中英文文案，应用文案由 gen-l10n 生成的 delegate 提供。iOS Info.plist 声明 en / zh，最低 OS 不变，实际 iOS 验证仍延期。

新增并精确锁定 `get 4.7.3`；本轮 lockfile 只新增该包，已有传递依赖版本未变。依据 [GetX 4.7.3](https://pub.dev/packages/get/versions/4.7.3) 及实际下载包的 pubspec，Dart 约束为 `>=2.15.0 <4.0.0`、Flutter `>=3.13.0`，与固定 Flutter 3.38.4 / Dart 3.10.3 相容。包声明 Android/iOS 支持；发布包无额外原生插件、CocoaPods / SwiftPM 或 build hook 集成，也未改变项目最低 OS。

手动生命周期对照安装包的 `lib/get_instance/src/lifecycle.dart` 和 `lib/get_state_manager/src/simple/list_notifier.dart` 检查。未采用其全局 DI / 路由功能，未来升级需要回归当前 Scope 的创建与释放测试。[上游项目](https://github.com/jonataslaw/getx) 为维护与升级参考，当前固定稳定 4.x。

iOS Level A：领域边界未改变，无 dart:io 平台分支或 Android-only 核心实现，Cupertino 导航路径有宿主 widget 验证。该验证不代表 iOS 编译、系统手势或设备运行通过；最终 SDK 链接、SafeArea、键盘和 swipe-back 实测仍归 IOS 任务。

## 验证记录

**多语言补充（2026-09-07，已迁移 gen-l10n）**：完整 `flutter test --no-pub --reporter expanded` **50 项通过**（下述原 44 项 + 6 项本地化测试），`flutter analyze --no-pub` 无问题。新增覆盖 ARB 双语键完整性、系统语言列表/地区变体/英文回退、显式 locale 参数和系统语言变化对已打开页面的更新、Controller/路由保留、双语错误与操作、长文案大字布局及 Material/Cupertino 内置返回标签。Info.plist XML 校验通过，iOS 仅兼容性审查。本次未重复尝试先前只读模拟器上的安装，不新增设备 runtime 通过声明。

迁移后的 `flutter gen-l10n` 重复生成哈希一致，全部 lib/test 格式检查通过（36 个文件，0 修改）；Android Debug build PASS（assembleDebug 5.7 秒）。CI 已加入生成一致性检查；尚未以本地结果宣称 GitHub runner 已运行通过。

以下为 CORE-004 初次交付记录：

- `dart --suppress-analytics format lib/app lib/shared test/widgets/app`：通过。
- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub --reporter expanded`：**44 项通过**，包括 33 项既有领域测试、1 项启动测试及本轮 10 项 widget 测试。覆盖设置依赖替换、失败保留首页与恢复、请求覆盖/晚结果丢弃、Android 返回、Cupertino 边缘滑动返回、重复 push 的独立 Controller、实际订阅数归零、取消与共享仓库存活、类型化参数、错误动作/冷却、小屏大字布局。
- widget 测试用 test/support 的合成依赖及局部可控替身，不访问源站。平台返回的异步资源释放通过 tester.runAsync 等待，不把虚拟时钟等待误判为资源泄漏。
- `flutter build apk --debug --no-pub`：PASS，Gradle assembleDebug 10.9 秒；APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。保留历史记录中的 Gradle launcher Java native-access warning，实际构建成功。
- 已连接设备 `emulator-5554`：型号报告 V2366GA，x86_64，API 32。`adb install -r` 失败：无法创建 `/data/app/vmdl…tmp`；随后 `install --no-streaming -r` 失败：`/data/local/tmp/app-debug.apk` 为只读文件系统。`df` 报可用约 99 GB，未将问题误归为磁盘满。未卸载应用、清理设备数据或修改挂载。第一次安装失败后启动命令打开了设备上的旧版本，这不计为本轮新包 smoke PASS。当时新包运行验收待模拟器恢复可写后补测；该待项现已按下文 DEV-002 记录补齐。ARM64 真机验收仍归 ANDROID-002。

### 后续补验：DEV-002（2026-09-07）

连接 MuMu `127.0.0.1:16384` 后，本轮新开发包 `adb install -r` 返回 Success，冷启动 Status ok；截图确认 singleImage 场景通过同一 ShioriApp 应用壳显示摘要和真实 PNG，系统返回后显示开发菜单，当前应用日志未见所检查的 Flutter/Android 致命错误。CORE-004 的新包安装/启动待项据此关闭，证据见 [DEV-002 验证](dev-entry.md)。这是后续开发入口对共享应用壳的 smoke，不将早期失败改写为成功，也不宣称重新安装运行了当时的旧 APK；普通入口本轮已独立编译通过。ARM64 真机和 iOS runtime 验收仍按原任务保留。

### 本机 Flutter 启动阻塞的处理

本轮重现了早前 Flutter 命令无输出的问题，临时诊断将等待范围缩小到 `globals.analytics` 初始化；没有确定其内部更深层原因。SDK 的 `packages/flutter_tools/lib/src/reporting/unified_analytics.dart` 提供进程级抑制变量，启用后恢复正常：

```powershell
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
flutter gen-l10n
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
. ./tool/android-env.ps1
flutter build apk --debug --no-pub
```

本轮实际通过固定 SDK `dart.exe` 执行 `bin/cache/flutter_tools.snapshot` 的对应命令，等价进入 Flutter 工具；未修改 SDK 源码、删除锁文件或改全局 analytics 设置。gen-l10n 的 format 子进程也曾等待，增加进程级 `CI=true` 后生成正常完成。本次诊断启动的等待进程和本地 VM 调试服务均已停止。这些变量可用于其他本机验证，历史任务的未运行记录仍保留为当时事实。

下一建议 DEV-001，构建完整的离线 Fixture Source / Media / Repository 场景，再由 DEV-002 接入开发入口。CORE-005 仍依赖 DB-002 和 NET-002；本轮不提前领取后续任务。

UI-001 已交付开发菜单中的“视觉样板”：三页共享候选 tokens，中英 / 明暗 / 大字 / 状态 / 全屏预览。实现与 Android 截图记录见本文 UI 验证记录摘要；指定 `themeLab` 场景不打开数据库，正式主题现已接入。


UI-002 的应用外观按钮位于当前首页 / 开发菜单右上方，打开独立 Sheet。ShioriApp 的 homeBuilder 显式把 AppController 传入页面工厂，再传递操作回调；无 Get.find 或新的全局服务。应用主题变更不做颜色补间；阅读 Sheet 在系统减少动态效果时关闭过渡。主入口仅新增应用偏好装配，不代表完整设置页 / 生产 Source 已完成。

TEST-001：新增 SourceServices 作为显式在线数据装配，Source注册、NovelRepository和ImageRepository共用预算与生命周期；构造不联网。普通App页面/开发菜单尚未自动切换到此装配，Android独立验证入口已使用该工厂完成真实生产链路。验收见 [Source报告](source/lightnovel.md)，页面接线仍按后续任务执行。

2026-09-07 HOME-001 / SHELF-002 / PROGRESS-001 后续接线：普通 main 现通过 ProductionApp 打开正式数据库、SourceServices 和独立应用/阅读偏好，默认展示本地书架，搜索/详情/目录/跨章阅读/收藏/历史/继续阅读均已接通。ContinueDestination 使用固定 `/continue` 路由名，不记录身份。开发首页使用相同页面但仅注入 Fixture 数据；此前“普通页面尚未装配”的段落为历史记录。资源边界、Android runtime 与剩余范围见 [六项闭环验收](reading-flow.md)。


## LOCAL-002 文件导入入口（2026-09-08）

正式应用装配 ImportController + PlatformImportSource + 现有 LocalBookStore，首页入口打开根级 ImportOverlay。外部文件只触发待处理提示，用户确认 / 稍后不会替换现有导航或阅读会话。退出先取消并等待导入，再关闭本地库。LOCAL-002 验收时注册表为空；LOCAL-003 / 004 已接入实际 BookDecoder，fake parser 仅用于测试。详细生命周期、App Group 及验证边界见 [本地导入](local-import.md)。


LOCAL-003 / 004（2026-09-08）：ProductionApp 注入实际 BookDecoder；TXT 编码不确定时导入面板展示预览与选择，等待期间允许取消；EPUB 显示流式图文支持 / 降级范围。严格解码、格式拒绝和限额错误有中英文反馈。成功表示托管入库，书架与 Reader 连接仍由 LOCAL-005 交付。详见 [解析支持范围](local-parsers.md)。


## LOCAL-005 补充（2026-09-08）

LOCAL-005：导入完成提供“立即阅读”；首页更多菜单增加“本地文件”，可继续阅读、重新上架或确认删除。删除说明明确区分托管文件 / 书架 / 进度与外部原文件。中英文文案统一置于 ARB；目录页保留 EPUB 层级与当前章高亮。

### 2026-09-08 首页与书源展示调整

按用户确认移除正式应用的发现页面及底部导航。搜索默认使用当前装配的首个在线来源，不新增来源切换或聚合搜索。应用自有文案不展示来源品牌名或域名，搜索页统一显示本地化“在线书源”；开发环境仍显示明确的测试环境说明。内部 Source ID、适配器、托管数据身份和既有发现契约保留，方便未来替换来源；不修改返回的书籍正文、作者或版权信息，此调整不代表内容授权或发布审查已完成。

验证：`test/widgets/home_test.dart` 4 项通过（中英大字、无底部导航、无自动推荐请求、搜索中性来源标签），analyze PASS，Android ARM64 Release 构建成功。日志为 `.tooling/evidence/home-simple-{tests,analyze,build}.log`。共享首页仅移除 Flutter 页面与导航状态，无新增平台接口；iOS runtime 本轮未执行。
真机更新安装成功，界面节点确认首页无底部标签，搜索页显示“在线书源”；未执行实际在线搜索请求。已有书架条目仍显示，未清应用数据。

### 首页试版回退（2026-09-08，用户确认）

撤回「栞」印章、27sp 字标及随后首页精简试版，恢复原纯文字 Shiori、顶栏高度、书架标题与宣传副标题、继续阅读卡片、原有自适应封面网格及完整书名展示；删除 displayTitle 规则。仅保留导入入口移至“更多 → 导入书籍”。四种主题色、无发现页和中性书源文案保持已确认状态。历史 `wordmark-*` / `home-refine-*` 截图不作为当前设计，回退验证使用 `home-revert-*`。

### 图形字标接入（2026-09-08，用户确认）

用户认可 imagegen 的折页书签 + Shiori 组合后，仅替换首页标题为 `ShioriLogo`；其他已回退布局不变。使用 `assets/brand/shiori.png` 透明母版，顶栏呈现区域 128×34dp，裁去原图透明留白。暗色模式只在文字区域渲染暖白，保留书签颜色和统一几何，避免不透明背景及模式切换时错位；颜色独立于四种可选强调色。图片语义朗读本地化应用名，无点击行为。8 项首页 / 双倍字体横竖屏回归与 analyze 通过，ARM64 Release 构建成功。概念图和原始提示词保留在 `design/brand-concepts/`，未使用两次存在边缘缺陷的暗色透明生成稿。iOS 本轮无 runtime 验证。

### 书架封面等高修正（2026-09-08）

iPhone 截图发现单行 / 双行标题对应的封面高度不同：网格卡片的封面使用 Expanded，标题多占一行会压缩封面。改为按列宽固定 2:3 AspectRatio，标题继续使用统一预留空间；网格高度计算与实际 10px 间距对齐。保留现有列数、字体和首页样式。书架 / 首页 7 项组件回归通过；本轮未重新安装 iPhone，Release 需重新编译运行查看。
