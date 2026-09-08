# 持续集成

## 触发规则

| 事件 | 工作流与行为 |
| --- | --- |
| PR、推送 main / develop、手动 CI | [ci.yml](../.github/workflows/ci.yml)：质量检查，不打包 APK |
| 推送 `v*` tag | [release.yml](../.github/workflows/release.yml)：检查后构建签名 Release APK，创建 / 更新 GitHub Release |

用户已取消日常 Android Debug / Release smoke。手动运行普通 CI 也不打包。tag 流程会实际发布仓库 Release 资产，不是临时构建检查。

## 质量检查

固定 Flutter 3.38.4，应用、`tools/source_probe`、`tool/db_codegen` 三份依赖严格按 lockfile 安装。统一 `PUB_HOSTED_URL=https://pub.flutter-io.cn`，缓存只加速安装，不能替代锁文件校验。

CI 检查工作流结构、锁文件变化、数据库生成与新 schema、gen-l10n 生成一致性、Dart 格式、静态分析，以及独立 Source 调查包的格式 / 分析 / 样本完整性预检。根分析会扫描工具包，必须提前完成其依赖安装。

按用户约定，应用单元 / 组件测试、调查包 UT、Python 发布工具 UT 均在提交前本地执行，日常 CI（含 PR 和手动运行）不再重复运行。测试代码仍保留，格式和静态分析仍覆盖测试文件；远端 CI 绿色不代表 UT 已通过，应在提交或 PR 中记录实际本地验证。未添加强制 Git hook。

本地命令见[开发说明](development.md)。工作流结构校验入口为 [check_ci_yaml.dart](../tool/check_ci_yaml.dart)。样本哈希按原始字节计算，`.gitattributes` 固定 LF；哈希失败先修样本完整性，不放宽校验或把网络请求数为零误判为网络故障。

## Android tag 发布

APK 校验固定使用 runner 预装的 Build Tools **35.0.0**，发布构建前执行 `release_android.py tools` 预检，不依赖 PATH 中的 sdkmanager，也不自动选 runner 上最高版本。2026-09-08 的 v1.0.0 首次发布已构建出 68.6 MB APK，但校验失败：runner 预装 37.0.0，其 `apksigner --print-certs` 输出 `V2 Signer: certificate SHA-256 digest`，与校验器预期的 `Signer #1 certificate SHA-256 digest` 不同。已用官方 37 Windows 工具和同一测试 APK 复现格式差异；固定 35 后合成密钥签名 / 校验 / 元数据冒烟通过，6 项 Python 回归通过。未绕过签名检查；真实 v1.0.0 Release 尚未产出，修复待新的发布运行验证。

已知校验错误现在输出受控原因（版本、证书、工具），不会输出工具参数、原始 stderr 或签名秘密；未知异常仍使用通用提示。

按用户最新约定，tag 发布直接进入 `android-release`，不查询或等待 CI、不重复执行格式 / 分析 / UT。develop 日常 CI 保持独立；master 仅作为发布中间分支，不因推送触发 CI 或 Release。发布脚本优先快进 master，保留最终提交与标签的可追溯性。Android 构建仍保留工具预检、版本一致性、签名和 APK 校验；失败时不上传 Release。签名需要四个仓库 Actions secrets：

| Secret | 内容 |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | 发布密钥库文件的 Base64 |
| ANDROID_STORE_PASSWORD | 密钥库密码 |
| ANDROID_KEY_ALIAS | 签名别名 |
| ANDROID_KEY_PASSWORD | 私钥密码 |

工作流检查四项 Secret 非空、Base64 有效并还原 `android/app/release-keystore.jks` 与 `android/key.properties`。密码按 Java Properties 规则转义，支持空格、反斜杠等字符；密钥库密码与别名通过 keytool 导出证书验证，私钥密码在签名构建时验证。密钥只在签名步骤注入，不回显；无论构建成功与否都清理签名文件。

本地缺少 `key.properties` 时构建配置可回退 Debug 签名，因此 **Release 编译不等于正式签名**。密钥和密码需自行安全备份，不提交 Git。换电脑需要恢复同一密钥才能保持 Android 更新身份。

标签不会自动修改包内版本；发版时人工对齐 `pubspec.yaml`、build number、iOS 扩展版本和 tag。发布准备与许可边界见[发布说明](release/README.md)。当前没有 iOS CI 发布链路。

## 已有证据

2026-09-08 用户截图确认质量 job，以及旧工作流的「Android Debug 与 Release smoke」job 成功，CI-001 / CI-002 按调整范围完成。截图未包含 run URL / commit，不能定位到某次最终配置，也不能证明正式 tag 签名发布通过。

本地曾验证 YAML、生成一致性、Debug / Release 构建；锁文件 hosted 源漂移修复后严格安装通过。正式 tag 工作流远端运行、签名产物安装仍待发版阶段验证，见[验收摘要](validation/README.md)。

## RELEASE-002 工作流补齐（2026-09-08）

发布工具为 `tool/release_android.py`（Python3标准库，无额外包）；普通CI与tag检查均运行 `tool/test_release_android.py`。普通CI仍不打包，发布仍仅推送 `v*` tag触发。仅发布job获得 contents:write。

正式入口明确为 `lib/main.dart`。构建后用 Android SDK apksigner 验证签名有效，再对比配置密钥导出的证书SHA-256；aapt检查 applicationId=dev.shiori.reader、versionName / versionCode与pubspec一致且不可调试。检查通过才生成并上传：

- `shiori-reader-<tag>-android.apk`
- `SHA256SUMS.txt`（APK校验值）
- `release-info.json`（tag、commit、包版本、APK哈希、证书指纹，不含私钥 / 密码）

产物先保存为14天的 Actions artifact，再写入 GitHub Release。已存在Release才走覆盖上传；创建失败不使用无条件上传fallback。新建带预发布后缀的tag（如v1.0.0-rc.1）标为prerelease。重跑仍可能覆盖同名资产。

本地验证：发布工具4项离线测试通过，覆盖tag/版本/非法build、缺Secret/错误Base64、密码转义、错误包身份/可调试包/错误或多个签名证书；工作流YAML与步骤顺序 / Secret绑定 / 清理检查通过，Dart检查工具分析通过。另用临时合成JKS和已有本地Release APK完成实际keytool → Java Properties读取 → apksigner签名与验证 → aapt版本检查 → 哈希文件生成冒烟，错误证书拒绝通过。未使用用户正式密钥，未重新构建并发修改中的应用，未推tag、未发布、未验证远端Secrets或runner。首次正式签名发布及设备安装仍待完成。

参考：[apksigner](https://developer.android.com/tools/apksigner)、[GitHub job权限](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)。
