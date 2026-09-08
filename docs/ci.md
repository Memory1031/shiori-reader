# 持续集成

工作流：[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)。CI-001 已完成验收（2026-09-08）；CI-002 已按用户调整后的范围标记 DONE：仅 tag 打包，质量检查通过；正式签名发布链路的远端实跑归发布阶段验收。tag 触发的发布工作流见[发布工作流](#发布工作流)一节（[`.github/workflows/release.yml`](../.github/workflows/release.yml)）。

## CI-001 验收补齐（2026-09-08）

用户在本次会话确认已人工验证两项剩余要求：GitHub Actions 工作流成功运行；测试失败会使对应 job 失败。结合下方已有配置及本地验证记录，CI-001 标记 DONE。

远端运行结果的证据来源为用户人工确认；未提供具体 run URL / commit，本轮代理没有独立检查远端记录，也没有重复运行或注入故意失败代码。下方 2026-09-07 的待验描述保留为历史记录，不代表当前 CI-001 状态。此确认不扩展为 CI-002、签名发布或 iOS 编译验收。

## 触发方式

| 事件 | 行为 |
| --- | --- |
| 创建 / 更新 PR、推送至 `main` / `develop`、手动运行 CI | 仅运行格式、静态分析、离线测试、锁文件与生成一致性检查 |
| 推送 `v*` tag | 运行独立 Release 工作流，检查通过后构建签名 Release APK 并创建 / 更新 GitHub Release |

按用户 2026-09-08 的调整，取消日常 Debug 与 Release smoke 打包 job。普通 CI 不安装 Android 构建用 JDK、不打包或上传 APK；手动 CI 也只做质量检查。需要本地验证原生改动时仍可自行构建。

打包统一由下方 tag 发布工作流负责，需提前配置签名 secrets。注意该现有流程会创建 GitHub Release，并非只生成临时检查包。

## 发布工作流

工作流：[`.github/workflows/release.yml`](../.github/workflows/release.yml)，**仅在推送 `v*` 标签时触发**；普通推送、PR 和手动入口都不产出发布包。结构校验脚本为 [`tool/check_ci_yaml.dart`](../tool/check_ci_yaml.dart)（tag-only 触发、发布任务依赖检查）。

| 任务 | 行为 |
| --- | --- |
| `checks` | 应用级复核：两份严格锁定安装、gen-l10n、analyze、test；不重复调查包检查 |
| `android-release` | 依赖 `checks`；从仓库 secrets 还原签名密钥，构建 release APK，以 `shiori-reader-<tag>-android.apk` 为名创建 GitHub Release 并附上产物。重跑时若 Release 已存在则覆盖上传同一资产 |

发版步骤：把 `pubspec.yaml` 的 `version` 与标签对齐（如 `0.2.0+3` 对应 `v0.2.0`，`+3` 为递增的 versionCode）→ 提交并推送 → `git tag v0.2.0 && git push origin v0.2.0`。产物名取自标签，与 `pubspec.yaml` 的 versionName 由人工保持一致。

签名需要一次性配置 4 个仓库 secrets（GitHub **Settings → Secrets and variables → Actions**）：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 上传密钥库文件的 base64（Git Bash：`base64 -w 0 release-keystore.jks`） |
| `ANDROID_STORE_PASSWORD` | 密钥库口令 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥口令 |

密钥库用项目固定 JDK 生成，口令与 `.jks` 文件自行离线备份——密钥丢失后无法以同一签名身份发布更新：

```powershell
& ".tooling/jdk/jdk-17.0.20.1+1/bin/keytool.exe" -genkey -v -keystore release-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias shiori-upload
```

`android/key.properties` 与 `*.jks` 已被 `android/.gitignore` 忽略，不会进入版本库。`build.gradle.kts` 在缺失 `key.properties` 时回退 debug 签名，本地 `flutter run --release` 不需要任何配置；要在本地复验发布签名，可手工放置 `android/key.properties` 与密钥库后执行 `flutter build apk --release --no-pub`。

工作流缺 secrets 时会在写入签名配置前失败，不产出无法安装或签名不一致的包。当前应用尚未执行 TASK_PLAN 的 RELEASE-001 渠道 / 许可审查，**对外公开分发（真实发版）前先完成该任务**；打测试标签验证流水线不受此限制，验证后删除对应 Release 与标签即可。

## 依赖锁定

Flutter 固定为 **3.38.4**。应用、独立调查包与数据库生成器均使用 `pub get --enforce-lockfile`；Flutter 后续检查和构建使用 `--no-pub`。

应用多语言采用 gen-l10n + ARB，生成的 `lib/l10n/generated/` Dart 文件随资源一起提交。CI 在格式检查前运行 `flutter gen-l10n` 和 `git diff --exit-code -- lib/l10n/generated`，检查提交的代码与资源是否一致；修改文案后应在本地重新生成。

数据库通过 `bash tool/generate_database.sh` 重新生成 Dart 与 schema 快照，随后检查 tracked diff 和新增未跟踪快照；生成器依赖隔离在 `tool/db_codegen`，不改应用依赖。Windows 继续使用原有 PowerShell 入口。

Flutter SDK / Pub 缓存沿用 [flutter-action 的缓存能力](https://github.com/subosito/flutter-action#caching)，Pub 缓存键包含三份锁文件哈希及平台、SDK 版本。即使命中缓存也不跳过严格安装，并通过 `git diff` 检查锁文件。缓存仅加速安装，不作为依赖版本来源。

根目录 `flutter analyze` 会扫描独立调查包，因此必须在分析前完成应用与调查包的依赖安装；新增的数据库生成检查还需先安装隔离生成器依赖。仅安装主应用依赖不会生成 `tools/source_probe/.dart_tool/package_config.json`；干净的 runner 会因此找不到调查包自身以及 `html`、`image` 等依赖。不要通过忽略诊断或把调查依赖加入主应用来解决。

三份 `pubspec.lock` 的 hosted URL 均为 `https://pub.flutter-io.cn`，因此工作流统一设置：

```yaml
env:
  PUB_HOSTED_URL: https://pub.flutter-io.cn
```

Pub 默认使用 `pub.dev`，可通过 [`PUB_HOSTED_URL`](https://dart.dev/tools/pub/environment-variables) 选择镜像。源地址也属于依赖解析的一部分：若锁文件记录镜像、运行环境却使用默认源，即使版本号完全相同，严格锁定安装仍可能报 `Would change ... dependencies`。

遇到此类错误，先核对三份锁文件的源地址及 CI 环境；不要直接删除锁文件或移除严格检查。将来切换源时需同步更新本地配置、三份锁文件和工作流，重新验证版本与内容哈希。

## 本地复验

在已配置 Flutter SDK 的 PowerShell 终端、仓库根目录运行：

```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
flutter pub get --enforce-lockfile
Push-Location tools/source_probe
dart pub get --enforce-lockfile
Pop-Location
Push-Location tool/db_codegen
dart pub get --enforce-lockfile
Pop-Location
New-Item -ItemType Directory -Force tool/db_codegen/lib | Out-Null
./tool/generate_database.ps1
git diff --exit-code -- lib/data/local/database pubspec.lock tools/source_probe/pubspec.lock tool/db_codegen/pubspec.lock
dart tool/check_ci_yaml.dart
flutter gen-l10n
git diff --exit-code -- lib/l10n/generated
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub

Set-Location tools/source_probe
dart format --output=none --set-exit-if-changed bin lib test
dart --suppress-analytics analyze
dart --suppress-analytics test
dart bin/source_probe.dart
```

SDK / 依赖安装需要网络；上述测试和样本检查不启用 `--live`，不访问源站。

工作流结构校验（[`tool/check_ci_yaml.dart`](../tool/check_ci_yaml.dart)，依赖根项目的 `yaml` 开发依赖提供；先按上文完成严格锁定安装）：

```bash
dart tool/check_ci_yaml.dart
```

## 样本完整性与换行符

调查包先按原始字节校验 fixture SHA-256，失败时不会进入任何模拟 / 真实 HTTP 阶段。因此多个网络测试同时出现 `Expected: 1, Actual: 0` 时，应先查看 `fixture_integrity` 报告。CI 现在先运行默认离线检查，再用 `--reporter expanded` 执行测试，以保留明确的失败原因。

样本文本由根目录 `.gitattributes` 固定为 LF，manifest 哈希与 LF 字节对应；不通过放宽哈希检查兼容不同换行。Git 的检出换行规则见 [gitattributes 文档](https://git-scm.com/docs/gitattributes)。

## 本次验证记录（2026-09-07）

- YAML 解析、预期事件、手动 APK 条件、任务依赖和工作目录检查通过。
- 主应用的格式检查通过；指定镜像后，通过 Flutter 配套 Dart 3.10.3 包管理器及 `FLUTTER_ROOT` 完成严格锁定安装，未升级依赖。
- 调查包严格锁定安装、格式和静态分析通过；23 项测试通过；默认离线检查通过，15 项 manifest 校验成功，HTTP 请求数为 0。
- 本机 Flutter 启动命令无输出，已中断本次等待；未以这些结果宣称完整 Flutter 测试或 Android 构建通过。
- 用户提供的首次 GitHub 运行在依赖源不一致时安装失败；统一源后，后续运行因调查包依赖安装晚于根目录分析而失败。现已将两份依赖安装都提前到分析前。
- 调整顺序后，本地两份严格锁定安装及根目录 `dart --suppress-analytics analyze` 通过（No issues found）。这是 Dart 分析器验证，修正后的 GitHub `flutter analyze --no-pub` 仍待新提交运行；重新运行旧提交不会包含本次修正。
- 后续调查包测试失败已定位为 CRLF / LF 哈希差异：通过 `git -c core.autocrlf=false archive` 导出仓库内容，复现 9 个样本哈希不符。将样本固定为 LF 并修正 manifest 后，在独立 LF 导出目录执行 23 项测试全部通过，15 项样本哈希及默认离线检查通过，HTTP 请求数为 0。验证宿主仍为 Windows，未冒称实际 Linux runner 已通过。

## 本次验证记录 — 发布工作流（2026-09-07）

- 扩展 `.tooling/check-ci-yaml.dart` 校验 release.yml：两份 YAML 解析、tag-only 触发、`android-release` 依赖 `checks`、工作目录检查通过。
- `build.gradle.kts` 签名改造后本地复验：无 `key.properties` 时 debug 构建 PASS（29.1s，回退 debug 签名路径）；用临时测试密钥库走 CI 同款路径（`key.properties` + `release-keystore.jks`）构建 release APK PASS（53.8s），`apksigner verify --print-certs` 确认签名者为测试证书 `CN=Shiori Local Test`。测试密钥库与 `key.properties` 验证后已删除，未提交；正式密钥库尚未生成，4 个仓库 secrets 尚未配置。
- 未验证：GitHub Actions 上的实际运行（需提交并推送标签后观察）；iOS 发布链路不在本工作流范围。runner 上的 `gh release create` / base64 解码步骤仅为源码审查通过，无本机等价执行。

## CI-002 验证记录（2026-09-08）

历史记录：以下为调整前的 Debug / Release smoke 本地验证。用户随后要求仅 tag 打包，日常打包 job 已移除；这些记录不表示现行 tag 发布链路已验收。

| 本地检查 | 结果 |
| --- | --- |
| 工作流 YAML / 触发条件 / Linux / 只读权限与无 secrets 引用 / 发布 tag 边界 | PASS；`dart tool/check_ci_yaml.dart`，该脚本已加入 CI |
| Bash 语法与 `pipefail` + `tee` 失败传播 | PASS；模拟失败返回非零 |
| 数据库生成器 | 严格锁定安装后重新生成 Dart 与 User v3 / Cache v2 快照，与提交一致，无新增快照 |
| 缓存安装 | 三个包使用已有 Pub 缓存执行 `pub get --offline --enforce-lockfile`，三份锁文件不变；这是本地缓存复验，不是 Actions cache restore 证据 |
| 本地化与静态分析 | `flutter gen-l10n` 无 diff；`flutter analyze --no-pub` 无问题；工作流校验脚本单独 analyze 通过 |
| Debug APK | PASS，45.8 秒，183855950 字节 |
| Release smoke APK | PASS，66.0 秒，67697360 字节；`apksigner verify --print-certs` 为 `CN=Android Debug` |

两次构建均在 macOS 使用固定 Flutter 3.38.4 / JDK 17，未限制 target-platform；APK 中确认包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`。Release 构建仍提示本机 SDK `android-36/data/annotations.zip` ZIP 损坏，但最终退出码为 0；本轮未修改全局 SDK。没有安装到手机，也没有执行真实 Source 请求。本轮仅调整 CI / 工具 / 文档，未重复上一任务已通过的 393 项离线测试；CI 保留完整离线测试门禁。

本地日志：`/tmp/shiori-ci002-debug.log`、`/tmp/shiori-ci002-release.log`、`/tmp/shiori-ci002-analyze.log`（临时文件，不提交）。APK SHA-256：

- Debug：`9ded947397e39aa2cbaac55f335936b7b5281dcd40eb39387cb3c824e0119a45`
- Release：`ac9def321c436ed15e1f9b3f5be98fa6978928bb34d855dd6130a5f775d13ed9`

当前证据：用户后续截图确认“格式、静态分析与离线测试”job 已通过；截图未包含 run / commit，不能据此确认删除打包 job 的最新配置已运行。正式 tag 签名发布的远端运行证据留待发布阶段补齐，不再要求 PR / main 的 Debug 或 Release smoke 记录。

### 远端格式失败修正

用户提供的 Actions 截图显示格式检查因 `test/data/media/persistent_image_repository_test.dart` 一处 `expect` 换行不符合格式而退出 1，后续静态分析与测试未执行。已使用固定 Dart 3.10.3 格式化该文件，仅调整换行，无逻辑改动；本地复跑同款 `dart format --output=none --set-exit-if-changed lib test`，220 个文件、0 changed，通过。本轮未重复运行行为测试。后续用户提供该质量检查 job 的绿色成功截图，确认质量检查已通过，此前格式失败不再列为未解决问题。截图未包含 run URL / commit，不推断具体运行版本、缓存命中或 tag 签名发布结果。

### 打包触发策略调整（2026-09-08）

按用户要求删除普通 CI 的 Android 打包 job，保留质量检查及锁文件缓存；现有 `release.yml` 的 `v*` tag 签名发布流程保持不变。更新工作流结构校验，防止普通 CI 再加入打包命令。本地 YAML / 触发边界检查通过；未创建 tag、未触发发布，本次仅删除日常构建路径，不重复 APK 构建。

### 旧工作流 Android job 远端成功（2026-09-08）

用户补充 Actions 截图，确认此前运行的“格式、静态分析与离线测试”和“Android Debug 与 Release smoke”两个 job 均为绿色成功。记录为旧 Android 构建 job 的远端 PASS，补齐此前只有本地构建结果的证据。截图未展示 run URL / commit、各步骤状态或缓存命中信息，因此不单独断言条件执行的 Release smoke 步骤是否运行；这也不是正式 tag 签名发布验收。

CI-002 保持 DONE；现行“普通 CI 仅质量检查、`v*` tag 才打包”的用户约定不变。
