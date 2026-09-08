# LOCAL-002 验证记录

状态：LOCAL-002 本阶段验收完成；后续平台矩阵和解析 / 阅读任务边界见下文。

日期：2026-09-08。范围：文件选择、原生外部文件接收、托管交接和可取消导入流程。实际 TXT / EPUB 解析留给 LOCAL-003 / 004，本地 Reader 路由留给 LOCAL-005。

## 验证口径

- 流程测试注入 fake parser，使用真实 ManagedLocalBooks、SQLite 和临时文件系统，验证暂存、摘要去重、解析提交与取消。fake parser 仅位于测试目录。
- 正式应用解析器注册表为空。可接收及确认文件，但确认后明确提示暂未支持解析；不能把文件接收成功记为书籍导入 / 阅读成功。
- Android 测试辅助 APK 位于 `tool/local_import_provider/`，独立包名、私有 ContentProvider，仅给接收 Intent 临时读取授权。EPUB 测试输入只有 ZIP 头，用于入口测试，不是合法 EPUB 解析样本。
- iOS XCTest 在独立 iPhone 17 / iOS 26.5 Simulator 上运行；不更改此前用户正在操作的 iPhone 17 Pro / iOS 26.2 会话。

## 自动化证据

| 检查 | 结果 |
|---|---|
| Flutter analyze | PASS |
| 完整离线回归 | PASS，330 项 |
| 导入流程 | PASS，10 项，含外部复制完成 / resume、多文件错误恢复 |
| iOS Simulator debug 主应用 + Share Extension 构建 | PASS |
| iOS 原生 XCTest | PASS，7 项：原文件移除后副本读取、陈旧 ack、单槽保护、取消清理、中断回收、实际字节超限 / 重试、跨 owner 锁 |
| Android debug 构建 | PASS，arm64 APK，NDK 28.2.13676358 / JDK 17；当前模拟器架构 |
| Android 私有 Provider 临时 URI 打开 / 分享 | PASS，TXT / EPUB × VIEW / SEND 四组；含冷启动 / 重开、重复 receipt 保护、源文件移除后副本读取、解析器缺省提示及取消回收 |
| Android 错误恢复及原生选择取消 | PASS，多文件、失效文件、错误扩展名；取消原生选择器返回原面板 |
| Android 系统 Downloads 实际选中文件 | PASS，DocumentProvider 选择、界面交接、36 字节一致性及取消回收 |
| Android 系统 Files 外部打开方式 | PASS，分别将 TXT / EPUB 交给 Shiori，托管副本字节一致并可取消回收 |
| iOS 正式应用系统文件 URL 接收 / 副本重启恢复 | PASS，iOS 26.5；App Group 已建立，34 字节副本在源删除后仍可读，重启仍显示同一 receipt |
| iOS 实际分享面板 / Share Extension 冷启动交接 / 原生选择取消 | PASS，独立 UIKit 宿主分别分享 TXT / EPUB；主应用关闭时扩展接收，手动打开主应用确认，解析缺省提示及取消回收正常；原生文件选择取消返回原面板 |
| iOS Files 实际选中文件、签名真机及完整生命周期矩阵 | NOT_RUN；归 IOS-005 |
| 真机与 Release / 签名分发 | NOT_RUN |

完整回归首次暴露既有媒体清理在 macOS 路径别名上的错误：租约保存 canonical 路径，目录扫描得到 /var 别名，导致活跃文件被误判为未占用。维护时统一文件身份后，原有“清理不删除活跃租约”测试及完整回归通过。

本机原始日志在 Git 忽略的 `.tooling/evidence/local002-*.log`；不提交机器路径、模拟器数据、SDK 或构建产物。

## 重现与待验

Flutter 使用仓库 FVM 3.38.4，命令使用锁文件包源：

```sh
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter analyze --no-pub
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter test --no-pub
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=iOS Simulator,id=<设备 ID>' \
  -only-testing:RunnerTests CODE_SIGNING_ALLOWED=NO
```

Android 用 JDK 17 构建。设置本机实际 `ANDROID_HOME`、`JAVA_HOME`，执行 `sh tool/local_import_provider/build.sh`；安装 `.tooling/import-provider/provider.apk` 和应用 debug APK 到指定模拟器。辅助 Activity `dev.shiori.importfixture/.SendActivity` 接受 `--es mode view|send|multiple|missing|delete`、`--es name fixture.txt|fixture.epub`。辅助 APK 不加入生产应用或发布流程。删除原文件测试必须在接收副本完成后执行。

IOS-005 仍须从 Files / 第三方文档提供者分别选择 TXT 与合法 EPUB，验证冷启动、运行中接收、分享扩展取消 / 终止、同一文件重投、App Group 交接和源文件移除；签名真机还需注册主应用 / 扩展标识及共享 App Group。扩展测试不得假设扩展能够直接拉起主应用。

### iOS 真实分享 UI 测试

独立辅助宿主和 XCTest 位于 `tool/ios_import_probe/`，不编入生产应用。先安装正式应用到专用模拟器，执行 `ruby tool/ios_import_probe/generate.rb` 生成 Git 忽略的测试工程，再运行：

```sh
xcodebuild test -project .tooling/ios-import-probe/ImportProbe.xcodeproj \
  -scheme ImportFixture -configuration Debug \
  -destination 'platform=iOS Simulator,id=<设备 ID>' \
  -parallel-testing-enabled NO -testLanguage zh-Hans -testRegion CN
```

生成器使用本机 `xcodeproj` Ruby gem。测试通过真实 UI 清除专用模拟器上的待导入文件，勿对正在使用的设备执行。首轮测试曾匹配到 Flutter 面板的取消按钮，修正为等待原生导航栏并在该栏中定位取消后 PASS；这是测试定位修正，未据此修改生产行为。

Android 首次构建在 Google 存储下载 Flutter 引擎 JAR 超时；改用单次环境变量 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`，并指定 `--target-platform android-arm64` 后构建通过（172.3 秒）。这不是全架构 APK / Release 验证；未修改全局镜像或代理配置。

### Android 验收脚本

在专用 Android 16 / API 36 arm64 模拟器、英文系统 UI 下，安装应用与辅助 APK 后运行（按本机填写 adb 路径和设备 ID）：

```sh
python3 tool/local_import_provider/verify.py --device <设备ID> --adb <adb路径>
python3 tool/local_import_provider/verify.py --system-picker --device <设备ID> --adb <adb路径>
python3 tool/local_import_provider/verify.py --files-only --device <设备ID> --adb <adb路径>
```

第一条验证私有 provider 与错误恢复；后两条分别验证系统选择器与 Files 应用“打开方式”。应用控件同时匹配中英文；系统文件管理器的自动化定位以本次英文模拟器为准。脚本只操作自己的样本和该模拟器的待导入槽，不对日常使用的真机运行。首次冷启动等待窗口调整为 45 秒；目录抽屉与后台页面可能同时包含 Downloads 文本，测试选取抽屉中的项；打开方式弹窗兼容首次选择和系统已预选 Shiori 两种状态。相关失败重跑属于自动化定位修正，生产功能未因此改变。

最终 Android 运行日志：`local002-android-runtime.log`、`local002-android-system.log`、`local002-android-files-final.log`。最终 iOS 分享 / 选择取消日志：`local002-ios-ui-final.log`。均位于忽略的 `.tooling/evidence/`；不以早期失败尝试覆盖这些最终结果。
