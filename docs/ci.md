# 持续集成

## 触发规则

| 事件 | 工作流与行为 |
| --- | --- |
| PR、推送 main / develop、手动 CI | [ci.yml](../.github/workflows/ci.yml)：质量检查 |
| 推送 `v*` tag | [release.yml](../.github/workflows/release.yml)：并行构建签名 APK 与 Windows ZIP，二者通过后统一创建 / 更新 GitHub Release |

日常 CI 负责质量检查，tag 工作流负责应用构建与发布。

正式标签为 `vX.Y.Z`，beta 标签为 `vX.Y.Z-beta.N`。三端共用版本预检：标签基础版本与 pubspec 的 `X.Y.Z` 一致，包内使用 `X.Y.Z+build`；每个版本的 beta 序号从 1 开始，内部构建号独立递增。beta 的 APK / ZIP 标记为 GitHub 预发布，Latest 保持正式发布；iOS 上传 TestFlight。准备与发布命令见[发布操作](release/README.md)。

## 质量检查

固定 Flutter 3.38.4，应用、`tools/source_probe`、`tool/db_codegen` 三份依赖严格按 lockfile 安装。统一 `PUB_HOSTED_URL=https://pub.flutter-io.cn`，缓存只加速安装，不能替代锁文件校验。

CI 检查工作流结构、锁文件变化、数据库生成与新 schema、gen-l10n 生成一致性、Dart 格式、静态分析，以及独立 Source 调查包的格式 / 分析 / 样本完整性预检。根分析会扫描工具包，必须提前完成其依赖安装。

按用户约定，应用单元 / 组件测试、调查包 UT、Python 发布工具 UT 均在提交前本地执行，日常 CI（含 PR 和手动运行）不再重复运行。测试代码仍保留，格式和静态分析仍覆盖测试文件；远端 CI 绿色不代表 UT 已通过，应在提交或 PR 中记录实际本地验证。未添加强制 Git hook。

本地命令见[开发说明](development.md)。工作流结构校验入口为 [check_ci_yaml.dart](../tool/check_ci_yaml.dart)。样本哈希按原始字节计算，`.gitattributes` 固定 LF；哈希失败先修样本完整性，不放宽校验或把网络请求数为零误判为网络故障。

## Windows tag 构建

Windows 构建 job 仅在 tag 发布工作流运行，使用 `windows-2022` / Visual Studio 2022、同一固定 Flutter 版本及严格锁文件安装；构建前检查 VS 主版本。Git 长路径配置覆盖检出和 Pub 子进程，以支持固定提交的 WebView fork；仅缓存 SDK 和 Pub 依赖，不复用本机构建目录。构建入口固定为 `lib/main.dart`，检查 EXE、Flutter / WebView DLL、AOT 与资源文件是否存在且非空。CI 不启动应用或执行在线探针，编译成功不代表运行验收通过。

## Windows ZIP 与统一发布

`tool/package_windows.ps1` 查找 Visual Studio 2022 的 x64 VC++ 运行库，调用标准库脚本 `tool/release_windows.py` 打包。脚本核对 tag / pubspec、EXE 的 x64 架构、产品身份、版本与非 Debug 标志，验证必需 DLL / AOT / 资源文件，保留完整 data 目录及许可声明。ZIP 根目录直接包含 `shiori.exe`；不带 PDB 或包含构建机路径的 native_assets.json。

Windows 产物为 `shiori-reader-<tag>-windows-x64.zip`、`SHA256SUMS-windows-x64.txt` 和 `release-info-windows-x64.json`（版本、commit、摘要及未签名状态），与 Android 文件名分开。tag 构建产物保留 14 天；`publish` job 等待两个平台构建成功，下载当前运行的两个 artifact、核对两份 SHA-256 后统一上传同一 GitHub Release。只有该 job 获得 Release 写权限。任一构建或校验失败，都不进入发布。

本地可在正式入口 Release 构建后调用 `tool/package_windows.ps1 -Tag <tag> -Commit <完整提交 SHA>` 验包。Windows 使用方式与分发边界见[发布说明](release/README.md)。

## Android tag 发布

APK 校验固定使用 runner 预装的 Build Tools **35.0.0**，发布构建前执行 `release_android.py tools` 预检，不依赖 PATH 中的 sdkmanager，也不自动选 runner 上最高版本：更高预装版本的 `apksigner --print-certs` 输出 `V2 Signer: certificate SHA-256 digest`，与校验器预期的 `Signer #1 certificate SHA-256 digest` 格式不同，会导致校验失败。该差异已用官方工具复现确认；固定版本是规避手段，未绕过签名检查。

已知校验错误现在输出受控原因（版本、证书、工具），不会输出工具参数、原始 stderr 或签名秘密；未知异常仍使用通用提示。

按用户约定，tag 发布直接并行进入 `android-release` 与 `windows-release`，不查询或等待 CI、不重复执行格式 / 分析 / UT。develop 日常 CI 保持独立；master 仅作为发布中间分支，不因推送触发 CI 或 Release。发布脚本优先快进 master，保留最终提交与标签的可追溯性。Android 构建仍保留工具预检、版本一致性、签名和 APK 校验；失败时不上传 Release。签名需要四个仓库 Actions secrets：

| Secret | 内容 |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | 发布密钥库文件的 Base64 |
| ANDROID_STORE_PASSWORD | 密钥库密码 |
| ANDROID_KEY_ALIAS | 签名别名 |
| ANDROID_KEY_PASSWORD | 私钥密码 |

工作流检查四项 Secret 非空、Base64 有效并还原 `android/app/release-keystore.jks` 与 `android/key.properties`。密码按 Java Properties 规则转义，支持空格、反斜杠等字符；密钥库密码与别名通过 keytool 导出证书验证，私钥密码在签名构建时验证。密钥只在签名步骤注入，不回显；无论构建成功与否都清理签名文件。

本地缺少 `key.properties` 时构建配置可回退 Debug 签名，因此 **Release 编译不等于正式签名**。密钥和密码需自行安全备份，不提交 Git。换电脑需要恢复同一密钥才能保持 Android 更新身份。

标签不会自动修改包内版本；发版时人工对齐 `pubspec.yaml`、build number、iOS 扩展版本和 tag。发布准备与许可边界见[发布说明](release/README.md)。iOS 发布链路见[iOS TestFlight 发布](#ios-testflight-发布)。

## iOS TestFlight 发布

签名构建显式选择 runner 上的 Xcode 26.3，并在安装依赖前验证 iOS SDK 主版本至少为 26，避免默认 Xcode 变化或旧 SDK 到上传阶段才失败。最低运行系统仍由 deployment target 决定，不随构建 SDK 提高到 iOS 26。要求来源：[Apple 上传要求](https://developer.apple.com/news/upcoming-requirements/)。

工作流：[`.github/workflows/ios-release.yml`](../.github/workflows/ios-release.yml)。推送 `v*` tag 时与 Android 发布并行，在 macOS runner 上构建签名 IPA 并上传 App Store Connect（TestFlight）。手动入口只做签名构建冒烟（不上传 ASC，且无标签上下文时跳过版本预检）。质量检查不在发布工作流重复；tag 与 pubspec 版本一致性复用 `release_android.py version` 预检（仅 tag 触发时执行）。

签名链路：分发证书 p12 导入临时钥匙串（runner 钥匙串每次重建，不能依赖 xcodebuild 自动建证——Apple 每团队仅允许 2 张分发证书，重复建证第三次即失败）；profile 由 `xcodebuild -allowProvisioningUpdates` 配合 App Store Connect API 密钥现场下载。导出配置为 [`ios/ExportOptions.plist`](../ios/ExportOptions.plist)，teamID 与工程 `DEVELOPMENT_TEAM` 一致（个人团队）。共 5 个 secrets：

| Secret | 内容 |
| --- | --- |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8` | App Store Connect API 团队密钥（个人团队上下文生成，Admin 角色） |
| `IOS_DIST_CERT_P12` | Apple Distribution 证书 p12 的 base64 |
| `IOS_DIST_CERT_PASSWORD` | p12 口令（可为空） |

Apple 侧一次性准备（都在个人团队上下文操作，注意右上角团队切换器）：

1. 注册 App ID `dev.shiori.reader` 与 `dev.shiori.reader.ShareExtension`，均启用 App Groups 并分配 `group.dev.shiori.reader.import`；
2. App Store Connect 新建 App（Bundle ID 选 `dev.shiori.reader`）；
3. 生成 App Store Connect API 密钥（`.p8` 仅能下载一次）；
4. 生成分发证书：在有 Xcode 的机器上创建 Apple Distribution 并从钥匙串导出 p12，base64 后存入 secret。工作流不在 runner 上自动建证——证书产物含未加密私钥，而公开仓库的 Actions 产物任何登录用户都能下载。

发版与安装：与 Android 相同，人工对齐版本后推 tag（ASC 要求同一 versionName 下 CFBundleVersion 严格递增）；构建经数分钟至一小时处理后出现在 TestFlight，内部测试不走 Beta 审核，构建 90 天未安装会过期。iOS runtime 证据从此具备来源（真机 TestFlight 使用），但 CI 构建成功不等于 runtime verified；对外分发前 RELEASE-001 审查同样适用。

## 已有证据

2026-09-08 用户截图确认质量 job，以及旧工作流的「Android Debug 与 Release smoke」job 成功，CI-001 / CI-002 按调整范围完成。截图未包含 run URL / commit，不能定位到某次最终配置，也不能证明正式 tag 签名发布通过。

本地曾验证 YAML、生成一致性、Debug / Release 构建；锁文件 hosted 源漂移修复后严格安装通过。正式 tag 工作流远端运行、签名产物安装仍待发版阶段验证。

## RELEASE-002 工作流补齐（2026-09-08）

发布工具为 `tool/release_android.py`（Python3标准库，无额外包）；`tool/test_release_android.py` 在提交前本地执行。普通 CI 只做质量检查，发布仍仅推送 `v*` tag 触发。仅发布 job 获得 contents:write。

正式入口明确为 `lib/main.dart`。构建后用 Android SDK apksigner 验证签名有效，再对比配置密钥导出的证书SHA-256；aapt检查 applicationId=dev.shiori.reader、versionName / versionCode与pubspec一致且不可调试。检查通过才生成并上传：

- `shiori-reader-<tag>-android.apk`
- `SHA256SUMS.txt`（APK校验值）
- `release-info.json`（tag、commit、包版本、APK哈希、证书指纹，不含私钥 / 密码）

产物先保存为 14 天的 Actions artifact。发布 job 签署更新清单、核对历史构建号和已有资产摘要，通过草稿完成上传后再公开 Release；重跑只补齐内容一致的缺失附件。beta 标签标为 prerelease，Latest 指向正式版本。更新签名配置见[发布操作](release/README.md#更新清单签名配置)。

本地验证：发布工具4项离线测试通过，覆盖tag/版本/非法build、缺Secret/错误Base64、密码转义、错误包身份/可调试包/错误或多个签名证书；工作流YAML与步骤顺序 / Secret绑定 / 清理检查通过，Dart检查工具分析通过。另用临时合成JKS和已有本地Release APK完成实际keytool → Java Properties读取 → apksigner签名与验证 → aapt版本检查 → 哈希文件生成冒烟，错误证书拒绝通过。未使用用户正式密钥，未重新构建并发修改中的应用，未推tag、未发布、未验证远端Secrets或runner。首次正式签名发布及设备安装仍待完成。

参考：[apksigner](https://developer.android.com/tools/apksigner)、[GitHub job权限](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)。

## iOS 发布工作流记录（2026-09-09）

- `tool/check_ci_yaml.dart` 扩展并通过：ios-release.yml 解析、tag 触发、证书引导任务不存在、archive → export → upload 顺序、版本预检与 altool 上传的 tag 门控、分发证书导入步骤存在、无测试 / 分析步骤混入、工作目录存在。
- 未验证：macOS runner 实际执行。`xcodebuild -allowProvisioningUpdates` 自动签名、`pod install`、`fastlane cert`、`altool` 上传均为官方 / 社区文档依据的源码审查；首次真实运行需 Apple 侧（App ID、App 记录、API 密钥、分发证书）与 5 个 secrets 就绪，可能需按实际报错微调（runner Xcode 版本、ExportOptions `method` 取值等）。本机为 Windows，无法本地执行 iOS 构建。
