# 持续集成

工作流：[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)。当前是提前引入的基础质量检查，不代表任务计划中的 CI-001 / CI-002 已完成全部验收。

## 触发方式

| 事件 | 行为 |
| --- | --- |
| 推送至 `main` / `develop`，或创建 / 更新 PR | 运行应用与调查包的格式、静态分析及离线测试 |
| 手动 `workflow_dispatch` | 先执行相同检查，通过后构建并上传 Android Debug APK |

仅修改文档时也运行基础检查。普通推送和 PR 不构建 APK。

手动构建入口为 GitHub **Actions → CI → Run workflow**；工作流进入默认分支后可使用该入口。产物名为 `app-debug-apk`，保留 7 天，仅用于开发验证。工作流没有发布、签名密钥或 iOS 构建步骤。

## 依赖锁定

Flutter 固定为 **3.38.4**。应用和独立调查包都使用 `pub get --enforce-lockfile`；Flutter 后续检查和构建使用 `--no-pub`。

应用多语言采用 gen-l10n + ARB，生成的 `lib/l10n/generated/` Dart 文件随资源一起提交。CI 在格式检查前运行 `flutter gen-l10n` 和 `git diff --exit-code -- lib/l10n/generated`，检查提交的代码与资源是否一致；修改文案后应在本地重新生成。

根目录 `flutter analyze` 会扫描独立调查包，因此必须在分析前完成两份依赖安装。仅安装主应用依赖不会生成 `tools/source_probe/.dart_tool/package_config.json`；干净的 runner 会因此找不到调查包自身以及 `html`、`image` 等依赖。不要通过忽略诊断或把调查依赖加入主应用来解决。

两份 `pubspec.lock` 的 hosted URL 均为 `https://pub.flutter-io.cn`，因此工作流统一设置：

```yaml
env:
  PUB_HOSTED_URL: https://pub.flutter-io.cn
```

Pub 默认使用 `pub.dev`，可通过 [`PUB_HOSTED_URL`](https://dart.dev/tools/pub/environment-variables) 选择镜像。源地址也属于依赖解析的一部分：若锁文件记录镜像、运行环境却使用默认源，即使版本号完全相同，严格锁定安装仍可能报 `Would change ... dependencies`。

遇到此类错误，先核对两份锁文件的源地址及 CI 环境；不要直接删除锁文件或移除严格检查。将来切换源时需同步更新本地配置、两份锁文件和工作流，重新验证版本与内容哈希。

## 本地复验

在已配置 Flutter SDK 的 PowerShell 终端、仓库根目录运行：

```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
flutter pub get --enforce-lockfile
Push-Location tools/source_probe
dart pub get --enforce-lockfile
Pop-Location
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
