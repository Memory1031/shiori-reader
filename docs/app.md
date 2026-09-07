# CORE-004：应用装配、导航与通用状态

2026-09-07。CORE-004 DONE；完成应用壳和所需 widget 验收。Android Debug build PASS；初次模拟器安装失败的待项已在 DEV-002 补齐，同一应用壳的新开发包安装、冷启动和返回导航 smoke PASS，见下文补验记录。iOS Level A compatibility review PASS，实际 iOS runtime 仍为 DEFERRED_NO_MAC。

## 装配与范围

`lib/main.dart` 调用 `lib/app/bootstrap.dart` 的 `createApp`，组装 `ShioriApp`、应用级 `AppController` 和 `AppRoutes`。依赖通过构造器和页面工厂闭包传入；没有 Get 服务注册、Get.find、GetMaterialApp 或站点常量。

当前 production 没有数据库或生产 Repository。可选 SettingsStore 未注入时只使用领域默认设置，不请求网络、不伪造持久化结果。注入后异步加载设置并应用 system/light/dark 主题；失败保留首页和默认/已有设置，显示领域错误与允许的重试动作。这里只读取设置，设置编辑和持久化归后续任务。

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

新增文案同时补齐两份 ARB，键有含义而非直接拿中文当键；有歧义时补充 description。参数、复数及选择表达采用 ARB 的 ICU 语法和 placeholder 元数据，避免拼接句子；日期和数字按所选语言格式化并补测试。保留可伸缩/换行布局，不以中文短文案宽度固定英文按钮。

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
