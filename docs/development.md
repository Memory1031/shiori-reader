# Development baseline — CORE-001

当前基础 CI 的触发方式、依赖源配置及本地复验命令见[持续集成说明](ci.md)。DEV-001 的离线场景、故障控制和解码复验见 [Fixture 规范](fixtures.md)。DEV-002 的菜单、启动参数与普通/dev 构建命令见 [开发入口](dev-entry.md)。READER-001 的双模式阅读实验与复验见 [ADR-07](decisions/reader-viewport.md)。READER-002 的正式单章页面与验证见 [Reader 说明](reader.md)。NET-001 / NET-002 的预算和诊断见 [网络说明](network.md)，MEDIA-001 的租约及内存边界见 [媒体说明](media.md)。下文保留 CORE-001 的历史开发基线与验证记录。

记录日期：2026-09-06。当前只建立最小移动端启动工程，不包含 Source、导航、状态管理、领域模型或存储实现。README 原文保留。

## 固定工具链

| 项目 | 本次选择 / 证据 |
| --- | --- |
| Flutter | **3.38.4 stable**；framework `66dd93f9a27ffe2a9bfc8297506ce066ff51265f`；沿用已安装 SDK，没有执行 upgrade |
| Dart | **3.10.3**，随上述 Flutter 分发 |
| Engine | `a5cb96369ef86c7e85abf5d662a1ca5d89775053` |
| JDK | Microsoft OpenJDK **17.0.20.1+1 LTS**，Windows x64 ZIP |
| Android Gradle Plugin | **8.11.1** |
| Gradle wrapper | **8.14** |
| Kotlin plugin | **2.2.20**；Java / Kotlin target 17 |
| Android SDK | compile / target **36**（Platform r2）；Build Tools **35.0.0**；platform-tools **37.0.1**；min **24**（项目决定）；NDK **28.2.13676358**；CMake **3.22.1** |
| iOS | deployment target **15.0**（项目决定）；Swift target 保留；runtime **DEFERRED_NO_MAC** |
| 开发身份 | Android namespace / applicationId 与 iOS Bundle ID 均为 `dev.shiori.reader`；测试 bundle 加 `.RunnerTests`。这是本地开发占位，未注册发布身份 |
| 应用依赖 | 仅 Flutter SDK；dev-only Flutter test SDK + `flutter_lints 6.0.0`；实际传递解析由 `pubspec.lock` 固定 |

`.fvmrc` 指定精确 Flutter 3.38.4；FVM 不是必须安装的工具。手工安装也可以，从 [Flutter SDK archive](https://docs.flutter.dev/install/archive) 选择 3.38.4，并先检查 `flutter --version` 的版本和 revision。`pubspec.yaml` 的 Dart `>=3.10.3 <3.11.0` / Flutter `>=3.38.4 <3.39.0` 是包兼容范围，**不是 SDK 精确锁**，不能代替 `.fvmrc` / revision 检查。不要用 `flutter upgrade` 或 `pub upgrade` 作为日常启动步骤。

OS 交集审查：锁定 SDK 内的 `packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt` 给出 Android min 24、compile/target 36、NDK 版本；其生成 iOS target 和 CocoaPods 模板的最低版本是 13.0，本项目主动选择 15.0，并同步 Xcode build settings 和 `AppFrameworkInfo.plist`。当前 [Flutter 支持平台页](https://docs.flutter.dev/reference/supported-platforms) 已针对 3.47.2 描述 Android 24 / iOS 15，**不能拿该页冒充 3.38.4 的历史矩阵**。此处锁定版本的证据采用已安装官方 SDK 的源码与模板。目前没有第三方 runtime/native 插件需要进一步抬高下限。

## Windows 本地准备

初次调查识别到 Flutter 和 MuMu / MAA adb；`flutter doctor -v` 未找到 Android SDK，PATH 和当时检查的标准/软件目录未发现可用 JDK。随后构建复验发现 Flutter 选择了 `D:/Software/Android Studio/android.studio/jbr` 的 JBR **25.0.2**，这里不推断该目录何时安装。补齐的便携工具均放入 Git 忽略的 `.tooling/`，不修改系统 PATH、注册表或全局 Flutter 配置。

`tool/android-env.ps1` 设置当前进程环境，并在本项目专用 `.tooling/gradle/gradle.properties` 写入 `org.gradle.java.home`（保留其他键），将 **Gradle build JVM** 固定为 JDK 17。原因是 Flutter 可优先选择 Android Studio 的 JBR 而忽略 `JAVA_HOME`；仅设置 `JAVA_HOME` 无法确保构建使用 17。该配置只影响本项目缓存；其他项目和用户 Flutter 设置保持原样。

下载来源及校验（2026-09-06）：

| 文件 | 来源 | 字节数 | SHA-256 |
| --- | --- | --- | --- |
| JDK ZIP | [Microsoft 下载页](https://learn.microsoft.com/en-us/java/openjdk/download)，`https://aka.ms/download-jdk/microsoft-jdk-17.0.20.1-windows-x64.zip` | 186915383 | `3d9006956fc8af5601cd24ffc4f468bef48279c7ebd8171b9bdf90d0aabfbf1f` |
| Android CLI ZIP | [Google Android tools](https://developer.android.com/studio)，`https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip` | 155655386 | `90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a` |

JDK hash 与 Microsoft `.sha256sum.txt` 一致；Android CLI hash 与 Google 下载页一致。解压布局：`.tooling/jdk/jdk-17.0.20.1+1/bin/java.exe`、`.tooling/android-sdk/cmdline-tools/latest/bin/sdkmanager.bat`。CLI `source.properties` 实际为 22.0；它提示 sdkmanager 已 deprecated，仍可完成本次安装，后续迁移命令不属于本任务。

SDK Manager 的 NDK 下载曾低至约 30 KB/s；中断后改用同一 Google URL `https://dl.google.com/android/repository/android-ndk-r28c-windows.zip`，curl 下载完整 **748118221** 字节，与 [Google SDK 仓库清单](https://dl.google.com/android/repository/repository2-3.xml) / [Android NDK 官方发布](https://github.com/android/ndk/releases/tag/r28c) 的 SHA1 `086bba43ff2f5eb0e387b15c8278bb4e0d89ba1d` 一致，再解压到 `.tooling/android-sdk/ndk/28.2.13676358/`。其余 SDK 组件由 SDK Manager 安装；Gradle wrapper 下载 8.14-all（224116304 字节）。已下载的工具与缓存不提交 Git；首次构建需预留数 GB 磁盘和联网时间。

```powershell
# 在仓库根目录；进程环境 + 本项目忽略的 Gradle JVM 配置。
. ./tool/android-env.ps1
java -version

# 使用前阅读并接受实际展示的 Android SDK 许可。
& "$env:ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager.bat" `
  --sdk_root=$env:ANDROID_HOME `
  'platform-tools' 'platforms;android-36' 'build-tools;35.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1'

flutter --version
flutter doctor -v
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub

# 仅当出现下文所列 temporary workspace 错误时：
./android/gradlew.bat --stop
flutter build apk --debug --no-pub
```

本次沙箱禁止普通命令写工作区外 Flutter cache 锁，第一次 Flutter 启动因此挂起并已中断。后续 Flutter 命令通过自动审批允许的升权运行；下载网络和 SDK 安装也通过该审批。SDK 安装调用明确包含接受对应 SDK 许可并获准，执行中通过输入 `y` 接受已展示的 `android-sdk-license`。这不表示用户逐条阅读了许可；新环境应使用上面的交互安装命令审阅实际许可。

现有 Flutter 环境使用 `pub.flutter-io.cn` / `storage.flutter-io.cn` 下载镜像，本任务沿用已有设置。Android SDK / JDK 下载采用上述官方来源。网络代理不写入仓库。

环境脚本使用无 BOM UTF-8 写入项目 Gradle properties，避免 Windows PowerShell 5.1 默认 UTF-8 BOM 影响首个属性键。已在 PowerShell 7.6.5 执行并检查无 BOM、原有属性值保持不变。Windows PowerShell 5.1 的直接执行被本机脚本执行策略阻止，未修改该策略；其兼容性仅作源码审查，不标 runtime PASS。当前已验证的命令环境为 PowerShell 7.6.5。

## Android 验证与设备安排

- 初次 `flutter build apk --debug --no-pub`：确实失败，`No Android SDK found`；已据此补齐工具链。
- 补齐后 `flutter doctor -v` 正确识别项目本地 SDK/JDK、Android API 36 / Build Tools 35.0.0 及 MuMu `android-x64`（API 32）。它仍提示部分未使用的 Android SDK 许可未接受、Visual Studio 未安装；没有为消除这些提示安装无关目标。
- 首次 Gradle 构建在 `:gradle:compileKotlin` 遇到 Windows cache `Could not move temporary workspace ... to immutable location`；随后新 transform 在 AAR、manifest、resources 阶段也分别失败，共 4 次。与 [Gradle #31438](https://github.com/gradle/gradle/issues/31438) 症状一致，但本机具体文件占用根因未证实；每次 `./android/gradlew.bat --stop` 后可继续推进。单 worker / `org.gradle.vfs.watch=false` 的本地尝试没有消除问题，已撤销，最终没有这些实验参数。没有关闭安全软件、删除用户全局缓存或更换 SDK 主版本。这是当前 Windows 首次缓存构建的已知限制，不能把停止 daemon 后重试称为根治。
- `dart format lib test`：通过，2 个 Dart 文件；`flutter analyze`：No issues found；`flutter test --no-pub`：1/1 PASS，验证 shell 可不依赖外部服务启动。
- Android debug build：**PASS**，第 5 次 Gradle 构建成功（113.2s）；没有附加 Gradle 实验参数。CMake 3.22.1 在最终构建中由工具链使用已接受的 SDK 许可自动安装。生成 `build/app/outputs/flutter-apk/app-debug.apk`，**142993020** 字节，SHA-256 `decdffaa92e33b2b465fc5440dba2d9e94047da417c15a8ece78c37aee5c868c`。
- MuMu smoke：**PASS**，`adb install -r` 返回 Success；`am start -W -n dev.shiori.reader/.MainActivity` 返回 Status ok / COLD，activity 为 topResumed，后续进程仍存活。检查本进程日志未见 FATAL / AndroidRuntime / Unhandled / E/flutter；截图确认为带 SafeArea 的 Shiori 最小 shell。截图本地留在 `.tooling/evidence/core-001-mumu.png`（不提交生成证据）。调试冷启动返回 TotalTime 4099ms，仅安装启动证据，**不是 profile 性能验收**。
- 构建还显示 SDK XML v3/v4 格式警告，但最终 APK 构建与安装通过；这条工具版本警告保留为后续工具链升级检查项。
- 标准命令复验曾因 Flutter 选择 Android Studio JBR 25.0.2 而失败（Gradle 报 `25.0.2`）；随后使用上面的项目局部 Gradle JVM 固定方式处理，**标准 debug build 复验 PASS（11.8s）**，daemon 日志确认 `javaVersion=17` 和项目 JDK 路径。Gradle wrapper launcher 仍显示 Java 25 native-access warning，需与实际执行构建的 JDK 17 daemon 区分。此次只复验受影响构建，未重复无关测试。
- MuMu 现有实例的 Android 为 12；`ro.product.cpu.abilist` 实测 `x86_64,arm64-v8a,x86,armeabi-v7a,armeabi`。该兼容 ABI 列表不表示 ARM64 真机；模拟器不能替代最终 ARM64 手机验收。
- 连接使用本机 MuMu 已配置的 `127.0.0.1:16384`；可用 `adb connect 127.0.0.1:16384`、`flutter devices`、`flutter run -d 127.0.0.1:16384`。其他机器/实例必须先查实际 adb 地址，不照抄端口。
- Android ARM64 真机尚未连接；ANDROID-002 / TEST-003 / RELEASE-002 保留真机网络、存储、生命周期、性能及候选包验收。官方模拟器交叉验证留 ANDROID-001 安排，不用 MuMu 代证。

## iOS Level A review

保留 `ios/Runner.xcodeproj`、workspace、Swift AppDelegate、Info.plist 和 Flutter xcconfig；Debug/Profile/Release 的 deployment target 均为 15.0，App framework minimum 同步。最小 UI 只使用 Flutter `MaterialApp` / `Scaffold` / `SafeArea`，没有 Android-only API、硬编码文件路径或 Android back 假设。没有新增平台插件、ATS 例外、CookieManager 或 WebView。当前可记录 **Code / Configuration Compatibility Review PASS**。

本机 Windows 不运行 Xcode、CocoaPods 最终链接、iOS build、Simulator、iPhone 或签名；Swift 文件和 Xcode 工程保留不等于实际能链接/安装。iOS Compile = NOT_RUN；Runtime / Device / Release = **DEFERRED_NO_MAC**，归 IOS-001..006。后续加入每个 native plugin 时仍需复查 iOS 支持和最低 OS。

工程仅 Android / iOS，无 Windows/macOS/Linux/web target。默认 Flutter 启动图标及 debug signing 仅用于工程 smoke；发布图标、最终身份和正式签名属于后续发布任务。

CORE-001 结果：**DONE（2026-09-06，working tree，未提交 commit）**。Android build / MuMu startup PASS；iOS Level A PASS，Level B DEFERRED_NO_MAC。Windows 全新 Gradle transform 缓存需要停止 daemon 重试的限制仍须在 ANDROID-001 复核，不阻止当前已实际构建并启动的最小工程交给后续任务。当前没有执行 CORE-002。

本次 `.tooling/` 工具、下载归档和构建缓存合计约 **7.61 GB**（7608807846 字节快照）；全部被 Git 忽略。APK / 测试产物在单独忽略的 `build/`。不把这些路径或宿主绝对路径写入应用配置。

## DB-001 / DB-002 存储与代码生成

数据库路径、双库备份边界、固定依赖、隔离生成器和验证记录见 [本地存储](database.md)。首次代码生成前进入 `tool/db_codegen` 执行 `dart pub get`，返回根目录运行 `./tool/generate_database.ps1`；所有命令仍使用固定 Dart 3.10.3。不要在主工程加入生成器的 analyzer 约束或强制依赖覆盖。数据库 schema 快照属于源码，工具包工作目录和原生下载缓存不属于源码。
