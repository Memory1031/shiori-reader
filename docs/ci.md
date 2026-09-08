# 持续集成

## 触发规则

| 事件 | 工作流与行为 |
| --- | --- |
| PR、推送 main / develop、手动 CI | [ci.yml](../.github/workflows/ci.yml)：质量检查，不打包 APK |
| 推送 `v*` tag | [release.yml](../.github/workflows/release.yml)：检查后构建签名 Release APK，创建 / 更新 GitHub Release |

用户已取消日常 Android Debug / Release smoke。手动运行普通 CI 也不打包。tag 流程会实际发布仓库 Release 资产，不是临时构建检查。

## 质量检查

固定 Flutter 3.38.4，应用、`tools/source_probe`、`tool/db_codegen` 三份依赖严格按 lockfile 安装。统一 `PUB_HOSTED_URL=https://pub.flutter-io.cn`，缓存只加速安装，不能替代锁文件校验。

CI 检查工作流结构、锁文件变化、数据库生成与新 schema、gen-l10n 生成一致性、Dart 格式、静态分析、应用离线测试，以及独立 Source 调查包的格式 / 分析 / 样本预检 / 离线测试。根分析会扫描工具包，必须提前完成其依赖安装。

本地命令见[开发说明](development.md)。工作流结构校验入口为 [check_ci_yaml.dart](../tool/check_ci_yaml.dart)。样本哈希按原始字节计算，`.gitattributes` 固定 LF；哈希失败先修样本完整性，不放宽校验或把网络请求数为零误判为网络故障。

## Android tag 发布

`checks` 执行应用复核，`android-release` 在其成功后使用 JDK 17 构建。签名需要四个仓库 Actions secrets：

| Secret | 内容 |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | 发布密钥库文件的 Base64 |
| ANDROID_STORE_PASSWORD | 密钥库密码 |
| ANDROID_KEY_ALIAS | 签名别名 |
| ANDROID_KEY_PASSWORD | 私钥密码 |

工作流还原 `android/app/release-keystore.jks` 与 `android/key.properties`，执行 Release APK 构建，产物名为 `shiori-reader-<tag>-android.apk`；重跑可能覆盖同名资产。缺签名配置应失败，不用 Debug 签名冒充发布包。

本地缺少 `key.properties` 时构建配置可回退 Debug 签名，因此 **Release 编译不等于正式签名**。密钥和密码需自行安全备份，不提交 Git。换电脑需要恢复同一密钥才能保持 Android 更新身份。

标签不会自动修改包内版本；发版时人工对齐 `pubspec.yaml`、build number、iOS 扩展版本和 tag。发布准备与许可边界见[发布说明](release/README.md)。当前没有 iOS CI 发布链路。

## 已有证据

2026-09-08 用户截图确认质量 job，以及旧工作流的「Android Debug 与 Release smoke」job 成功，CI-001 / CI-002 按调整范围完成。截图未包含 run URL / commit，不能定位到某次最终配置，也不能证明正式 tag 签名发布通过。

本地曾验证 YAML、生成一致性、Debug / Release 构建；锁文件 hosted 源漂移修复后严格安装通过。正式 tag 工作流远端运行、签名产物安装仍待发版阶段验证，见[验收摘要](validation/README.md)。
