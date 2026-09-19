# 开发与维护

## 工具链

| 工具 | 固定配置 |
| --- | --- |
| Flutter / Dart | 3.38.4 stable / 3.10.3；精确 SDK 见 [.fvmrc](../.fvmrc) |
| Android | JDK 17、AGP 8.11.1、Gradle 8.14、Kotlin 2.2.20 |
| Android SDK | compile / target 36、min 24、NDK 28.2.13676358 |
| iOS | macOS / Xcode，deployment target 15.0 |
| Windows | Visual Studio C++ 桌面构建工具、Windows SDK、PATH 中可用的 NuGet CLI；特殊 EPUB HTML 页使用 WebView2 Runtime |

不通过 `flutter upgrade` 或删除 lockfile 修复环境。FVM 可让本仓库使用独立 Flutter；Android SDK 的 NDK 可并存。机器路径只放忽略的本地配置，不提交到应用配置。

## 首次安装与启动

macOS / Linux shell：

```sh
fvm install 3.38.4
export PUB_HOSTED_URL=https://pub.flutter-io.cn
fvm flutter pub get --enforce-lockfile
(cd tools/source_probe && fvm dart pub get --enforce-lockfile)
(cd tool/db_codegen && fvm dart pub get --enforce-lockfile)
fvm flutter devices
fvm flutter run --target lib/main.dart
```

三个包的 hosted 源使用 `pub.flutter-io.cn`；严格安装报下载源变化时，先对照锁文件与环境，不去掉严格检查。根分析器会扫描独立工具包，因此也要安装其依赖。可用 Flutter 自带的匹配 Dart 替代 FVM 命令。

Windows PowerShell 设置 `$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'`，用 `Push-Location` / `Pop-Location` 切换工具目录；已有本地 Android 工具环境可通过 [android-env.ps1](../tool/android-env.ps1) 加载。macOS 选择 JDK 17，Android SDK 路径由 `android/local.properties` 的 `sdk.dir` 指定，不覆盖全局配置。

Windows 拉取固定提交的 WebView Git 依赖需要 Git 支持长路径；可用 `git config --global core.longpaths true` 启用，以完整检出包含多个平台的仓库。

iOS 安装依赖后在 `ios` 目录执行 `pod install`，打开 `ios/Runner.xcworkspace`。不要打开单独的 `.xcodeproj` 来构建 CocoaPods 工程。选择实际设备，给 Runner 和 ShareExtension 配置自己的 Team、匹配的 App Group 与唯一 Bundle ID；不要借用公司 Team。签名及个人安装边界见[发布说明](release/README.md)。

更改 pubspec 版本后，直接在 Xcode 构建前先同步本地 Flutter 参数，避免 Runner 使用旧构建号而 ShareExtension 已更新：

```sh
fvm flutter build ios --config-only --release --no-codesign --no-pub
```

此命令只准备配置和 Pods，不完成签名安装。生成的 `Generated.xcconfig` 与 `flutter_export_environment.sh` 保持忽略，不手工提交。

## 本地检查

提交前按改动范围运行相关 UT；跨模块或发布准备时运行完整离线测试。日常 GitHub CI 不运行 UT，保留格式、分析及生成一致性检查；不要将 CI 成功当作本地测试证据。修改发布工具时另运行 `python3 -m unittest discover -s tool -p 'test_release_android.py'`（Windows 可使用本机 Python 命令）。

```sh
fvm dart tool/check_ci_yaml.dart
fvm flutter gen-l10n
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze --no-pub
fvm flutter test --no-pub
(cd tools/source_probe && fvm dart format --output=none --set-exit-if-changed bin lib test)
(cd tools/source_probe && fvm dart analyze && fvm dart test && fvm dart bin/source_probe.dart)
```

默认测试与 Source 调查工具不发真实书源请求；安装 SDK / 依赖本身需要网络。真实书源验收必须显式授权并限制请求，见[调查工具](../tools/source_probe/README.md)。

改 ARB 后提交 `lib/l10n/generated/` 的对应生成变化。改数据库后执行 `bash tool/generate_database.sh`；Windows 用 `tool/generate_database.ps1`。Drift 生成器隔离在 `tool/db_codegen`，不要把它的 analyzer / build_runner 依赖加进主应用。生成结果与 schema 快照一起核对，见[数据库](architecture.md)。

原生改动按需构建 `fvm flutter build apk --debug --no-pub` 或 `fvm flutter build ios --release --no-pub`；构建成功不代表安装或运行通过。普通 CI 不打包，见[CI](ci.md)。

## 离线开发入口与样本

```sh
fvm flutter run --target lib/main_dev.dart
fvm flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=singleImage
fvm flutter run --target lib/main_dev.dart --dart-define=SHIORI_SCENARIO=longChapter
```

场景值区分大小写，未知值在启动时报错；修改 dart-define 后重启。菜单使用独立 `FixtureEnvironment`，生产入口不导入 `lib/dev/`，也不注册 fixture Source。开发入口和正式入口共用应用 ID，安装前留意现有数据与签名。

[场景定义](../lib/dev/fixtures.dart)覆盖短章、十万字长章与单段、20 图、单图、慢图 / 失败 / 未知尺寸、长标题、排版、多卷、无卷、空搜索、重复游标、删章和内容修订。数据由固定 seed 合成，不附带真实小说正文或插图。故障通过 controls、取消 token 和可控异步完成，不靠真实网络或任意 sleep。

调用方拥有环境、订阅和媒体 lease：退出先取消请求与订阅，关闭 lease，最后关闭环境。Fixture 的内存缓存不代替生产持久化 / 重启验收。Parser 的脱敏样本及 SHA-256 / LF 约定见[样本说明](../test/fixtures/lightnovel/README.md)。

## 升级与排障

已发布版本的 schema 快照必须保留；迁移用旧快照和自制数据测试，检查事务失败回滚与未知版本拒绝。不要删除用户数据库来处理升级失败。先退出应用，保全数据库及 WAL / SHM、preferences、托管原件和 manifest，在副本上检查。

设备探针使用隔离目录，入口留在 `integration_test/`。本机 `.tooling/evidence/` 是忽略目录，不承诺随仓库提供；历史测量查 Git 或对应操作记录。旧滚动性能数据不能作为新翻页动画的性能结果。
