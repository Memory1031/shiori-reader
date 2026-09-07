# DEV-002：离线开发入口与生产隔离

2026-09-07。DEV-002 DONE。73 项完整 Flutter 测试、静态分析、Android Debug 编译及 MuMu 新包启动通过。当前入口是场景数据检查页；真实 Reader 由 READER-001 / READER-002 实现。

## 日常启动

在仓库根目录使用固定 Flutter 3.38.4：

```powershell
# 普通入口：保持现有应用壳，不包含开发菜单。
flutter run --target lib/main.dart

# 开发入口：17 个场景的中英文菜单。
flutter run --target lib/main_dev.dart

# 直接进入指定场景；返回仍可到菜单。
flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=singleImage
flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=longChapter
flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=failingImage
```

场景参数使用 [Fixture 目录](fixtures.md) 中的稳定枚举名，区分大小写；空值打开菜单，未知值在启动阶段报 ArgumentError，避免拼写错误时默默打开另一场景。dart-define 改动后重新启动进程，不依赖 hot reload 改编译常量。无参数和带参数都走同一 DevMenu；直达仅首次 push，不因系统语言变化再次打开。

本机环境需要时先设置进程级 `FLUTTER_SUPPRESS_ANALYTICS=true`、`CI=true`，执行 `. ./tool/android-env.ps1`。MuMu 当前已验证地址为 `127.0.0.1:16384`：先 `adb connect 127.0.0.1:16384`，再加 `-d 127.0.0.1:16384`。其他设备使用 `flutter devices` 返回的实际 ID。

## 检查页的边界

每次选择场景创建独立 FixtureEnvironment，页面通过正式 Repository 接口加载初始章。可搜索（空查询列出全部场景）、继续分页、打开结果的目录、选择章节、查看详情；revisedContent 可选 revision=0/1 后刷新。deletedChapter 直达旧章 Key 会显示不存在，可从目录选择其他章。

检查页展示段落/字符/图片数量、摘要、revision 和最多 160 个 code point 的首段预览，避免把十万字章直接渲染成一个 Text。媒体预览读取真实合成 PNG，支持慢加载、流失败重试和未知比例；使用独立 lease，页面离开和被替换的请求均取消/释放。下一步将真实 Reader 接在现有正式模型和 Repository 上，不将检查页当作 Reader 完成。

页面内的新请求取消旧调用者并校验请求代次，避免旧响应覆盖新选择。页面关闭释放环境；应用根节点不注册 Fixture singleton。短生命周期 UI 状态使用 StatefulWidget，生产 Controller、路由和 DI 规则未改变。

菜单显示名沿用 FixtureScenario 的 labelZh/labelEn；操作复用官方 AppLocalizations，并补齐通用「目录 / Contents」「加载更多 / Load more」ARB。原始合成内容和开发诊断字段保留数据本身语言，支持复制检查结果。

## 生产隔离与构建

- 唯一新增可执行入口是 `lib/main_dev.dart`，开发菜单、路由 `/dev/scenario` 和检查页都位于 `lib/dev/ui/`。
- `lib/main.dart` → `app/bootstrap.dart` 的生产依赖图不导入开发代码。没有隐藏按钮、运行时 source 特判或 production registry 注册 fixture。
- 图片按需生成字节，没有新增 assets、原生插件、依赖或 pubspec dev 资源声明。只有两条通用 ARB 操作文案可被生产页面复用。
- 回归测试从生产入口递归检查本项目 import/export/part，拒绝 dev 目录和 main_dev；同时检查 production route 和 assets 中无 fixture。实际发布包审计仍归 RELEASE-001，本轮未宣称发布 APK 内容扫描或正式签名通过。

```powershell
flutter build apk --debug --target lib/main_dev.dart
flutter build apk --release --target lib/main.dart
```

当前两种入口共用开发 applicationId，因此安装 dev 包会更新同 ID 的已安装应用；无新增 flavor。本轮保留 `build/app/outputs/flutter-apk/shiori-dev-debug.apk` 为 singleImage 直达开发包，最终 app-debug.apk 重新构建为普通入口。设备恢复为开发包供继续查看。

## 验证记录

- 完整 `flutter test --no-pub --reporter expanded`：73 项通过，新增 8 项覆盖参数选择、生产依赖图、菜单/返回、语言切换保留路由、空搜索/重放游标、目录选章、revision、图片失败重试和销毁取消。`flutter analyze --no-pub` 无问题。
- gen-l10n 已重新生成，格式检查通过。沿用固定 SDK、GetX 和 intl 版本，无依赖升级。
- Android dev Debug build PASS；`adb install -r` 返回 Success，singleImage 新包冷启动 Status ok，实际截图确认数据摘要和 PNG。系统返回后截图确认 Shiori DEV 菜单；本次应用进程日志检查未见 E/flutter、FATAL、Unhandled 或 AndroidRuntime 错误。截图在忽略目录 `.tooling/evidence/dev002-single-image.png` 和 `dev002-menu.png`。
- 利用当前设备补验 DEV-001：安装原 codec 探针后，新进程日志输出 `FIXTURE_CODEC_PASS count=20`。该探针没有 runApp/首帧，`am start -W` 随后等待首帧超时，不计 UI 启动成功；20 图解码结果来自探针自身日志。随后已恢复开发入口。
- 设备报告 V2366GA / PD2366，本次为 MuMu，不是 ARM64 真机性能证据。iOS 使用 CupertinoPageRoute、无平台插件或最低系统版本变化，Level A compatibility review PASS；实际 iOS runtime 仍 DEFERRED_NO_MAC。

下一建议 READER-001：使用已有离线长章和图文场景开展懒布局与深位置恢复实验。本轮未自动领取。
