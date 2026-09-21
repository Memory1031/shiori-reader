# 发布操作

本文件只维护通用流程，不记录当前版本进度。版本变化写入 `notes/vX.Y.Z.md`，测试结果在提交 / PR 或发布操作反馈中说明，不单独维护历史验收文档。

## 每次先读

| 文件 | 核对内容 |
| --- | --- |
| [pubspec.yaml](../../pubspec.yaml)、[iOS 工程](../../ios/Runner.xcodeproj/project.pbxproj) | 当前版本、内部构建号、ShareExtension 一致性；Runner 使用 Flutter 变量 |
| `notes/vX.Y.Z.md`、上个 tag 到 develop 的 Git diff | 实际变更、升级提醒、已知限制 |
| [开发说明](../development.md) | 固定工具链和本地验证命令 |
| [CI](../ci.md)、Android / Windows / iOS 工作流 | 签名配置、触发规则和上传方式 |
| [依赖与分发边界](dependencies.md) | 依赖变化时更新许可清单；分发范围变化时核对许可与隐私 |
| [发布脚本](../../tool/publish_release.dart) | prepare / publish 检查与行为 |

## 1. 准备

正式版本在干净的 develop 上使用项目 Dart SDK：

```sh
dart tool/publish_release.dart prepare patch
dart tool/publish_release.dart prepare patch --apply
```

支持 patch / minor / major，内部构建号递增，同步 pubspec 与全部 ShareExtension 配置。已 prepare 的版本不要重复执行，先检查 diff；提交后再次 prepare 会继续递增。

同一基础版本从 beta 转为首次正式发布时使用 `prepare stable`，保持 `X.Y.Z` 并递增构建号；目标正式标签必须尚未发布。发布检查要求构建号高于已公开的所有正式 / beta 包。

按输出版本编写 `notes/vX.Y.Z.md`，执行与改动相关的本地测试及必要分析、构建，记录实际结果和未测项。prepare 不提交、不推送、不打标签。

### 同版本 beta

日常测试版本使用 `prepare beta`，保留当前 `X.Y.Z`，递增内部构建号并同步全部 ShareExtension 配置：

```sh
dart tool/publish_release.dart prepare beta
dart tool/publish_release.dart prepare beta --apply
```

脚本读取当前版本的本地及 origin 标签，选择下一个 beta 序号。每个版本从 `beta.1` 开始，beta 序号与内部构建号独立，例如：

| 标签 | 包版本与内部构建号 |
| --- | --- |
| `v1.2.1-beta.1` | `1.2.1+11` |
| `v1.2.1-beta.2` | `1.2.1+12` |

切换到新的 `X.Y.Z` 后，beta 序号从 1 开始，内部构建号继续递增。预览会显示建议标签；审阅、提交并推送 develop，通过质量检查后，使用输出标签发布：

```sh
dart tool/publish_release.dart v1.2.1-beta.1
dart tool/publish_release.dart v1.2.1-beta.1 --publish
```

beta 附注标签直接指向已同步的 develop 提交。Android APK 与 Windows ZIP 进入 GitHub 预发布，Latest 指向正式发布；iOS 使用相同版本号和递增构建号上传 TestFlight。可在 `notes/<beta-tag>.md` 提供说明，缺失时由 GitHub 自动生成。

## 2. 提交和发布

审阅并提交必要文件、推送 develop，再将 `vX.Y.Z` 替换为已准备版本：

```sh
dart tool/publish_release.dart vX.Y.Z
dart tool/publish_release.dart vX.Y.Z --publish
```

第一条只预览；第二条用于已获授权的正式发布。要求工作区干净、develop 与 origin/develop 一致、标签不存在、包内与扩展版本一致。脚本优先快进 master，创建附注标签并原子推送 master / tag，成功后回到 develop。

master 仅是发布中间分支。tag 同时触发 Android 签名 APK、Windows x64 ZIP 与 iOS 签名 / TestFlight 上传；APK 和 ZIP 均构建成功后统一发布到 GitHub Release，不等待日常 CI，也不重复 UT / analyze。CI 绿色不能替代本地测试记录。

GitHub Release 优先读取 `notes/<tag>.md`，缺失时自动生成。新 Release 先建立草稿，资产完整上传后公开；重跑核对已有附件的大小与摘要，只补齐缺失附件，内容变化需分配新的构建号和标签。手动编辑过的正文需在 GitHub 单独更新。

## 更新清单签名配置

Android / Windows 的 tag 构建将发布身份与更新公钥写入 `assets/release/build-info.json`。发布 job 核对两端包内身份、生成 `update-manifest.json` 并签署原始字节，另附二进制 `update-manifest.sig`。签名协议为 RSA-3072 / PKCS#1 v1.5 / SHA-256，公钥指数为 65537，Windows 使用系统 CNG 验签。

在安全的本地目录通过 OpenSSL 生成一次独立更新密钥：

```sh
python tool/update_manifest.py keygen --private-key /secure/update-private.pem --public-key /secure/update-public.json
```

GitHub Actions 需要以下仓库配置：

| 配置 | 内容 |
| --- | --- |
| Variable `UPDATE_PUBLIC_KEY_JSON` | 生成的 public JSON 原文，包含算法、模数、指数及 keyId |
| Secret `UPDATE_SIGNING_KEY_PEM_B64` | private PEM 完整字节的 Base64 |

公钥供构建与签名 job 读取，私钥仅供发布 job 签名。配置缺失或密钥不匹配时终止发布。私钥单独备份，公钥变更需要安排受旧公钥信任的过渡版本。开发构建使用仓库中标为 development 的身份文件；本地生成正式身份后，应恢复该文件再提交代码。

清单生成与发布规则测试使用隔离目录和测试密钥；Windows 原生验签互通测试入口为 `tool/test_update_signature.ps1`。

## 3. 验收

- Android：核对 Actions、APK、SHA256SUMS、release-info、版本与签名，验证覆盖安装保留数据。
- Windows：核对 ZIP、SHA256SUMS-windows-x64、release-info-windows-x64 与 EXE 版本，解压后启动、正常关闭并检查升级保留数据。
- iOS：核对上传、App Store Connect 处理和 TestFlight 分发，再验证设备安装。构建成功不代表测试者已可安装。
- 在发布操作反馈中说明实际结果和未测项。脚本成功仅表示 Git 推送成功。

失败先核对远端 refs 与工作流。冲突时不打标签；网络失败可能已被远端接收，不直接重建或覆盖标签。不要通过卸载或换签名解决升级问题。

## Windows ZIP 使用

下载 `shiori-reader-<tag>-windows-x64.zip`，可用 PowerShell `Get-FileHash -Algorithm SHA256 <ZIP 路径>` 与随包发布的 `SHA256SUMS-windows-x64.txt` 对照。完整解压到可写目录后运行 `shiori.exe`，不要只复制 EXE 或在压缩包内启动。包内包含 Flutter / 插件 DLL、资源、VC++ 运行库及许可文件；WebView2 Runtime 由系统提供，未安装时原版式 EPUB 页面会提示运行环境不可用。

当前提供未签名的 x64 ZIP，不包含安装器、自动更新或 Windows ARM64 构建。更新前关闭应用，将新版完整解压到独立目录；书架、阅读进度与设置使用应用数据目录，不随 ZIP 目录更换而清除。正式发布前仍需核对依赖许可及目标系统运行表现。
