# 发布操作

本文件只维护通用流程，不记录当前版本进度。版本变化写入 `notes/vX.Y.Z.md`，测试结果在提交 / PR 或发布操作反馈中说明，不单独维护历史验收文档。

## 每次先读

| 文件 | 核对内容 |
| --- | --- |
| [pubspec.yaml](../../pubspec.yaml)、[iOS 工程](../../ios/Runner.xcodeproj/project.pbxproj) | 当前版本、内部构建号、ShareExtension 一致性；Runner 使用 Flutter 变量 |
| `notes/vX.Y.Z.md`、上个 tag 到 develop 的 Git diff | 实际变更、升级提醒、已知限制 |
| [开发说明](../development.md) | 固定工具链和本地验证命令 |
| [CI](../ci.md)、Android / iOS 工作流 | 签名配置、触发规则和上传方式 |
| [依赖与分发边界](dependencies.md) | 依赖变化时更新许可清单；分发范围变化时核对许可与隐私 |
| [发布脚本](../../tool/publish_release.dart) | prepare / publish 检查与行为 |

## 1. 准备

在干净的 develop 上使用项目 Dart SDK：

```sh
dart tool/publish_release.dart prepare patch
dart tool/publish_release.dart prepare patch --apply
```

支持 patch / minor / major，内部构建号递增，同步 pubspec 与全部 ShareExtension 配置。已 prepare 的版本不要重复执行，先检查 diff；提交后再次 prepare 会继续递增。

按输出版本编写 `notes/vX.Y.Z.md`，执行与改动相关的本地测试及必要分析、构建，记录实际结果和未测项。prepare 不提交、不推送、不打标签。

## 2. 提交和发布

审阅并提交必要文件、推送 develop，再将 `vX.Y.Z` 替换为已准备版本：

```sh
dart tool/publish_release.dart vX.Y.Z
dart tool/publish_release.dart vX.Y.Z --publish
```

第一条只预览；第二条用于已获授权的正式发布。要求工作区干净、develop 与 origin/develop 一致、标签不存在、包内与扩展版本一致。脚本优先快进 master，创建附注标签并原子推送 master / tag，成功后回到 develop。

master 仅是发布中间分支。tag 同时触发 Android 签名 APK 与 iOS 签名 / TestFlight 上传，不等待日常 CI，也不重复 UT / analyze。CI 绿色不能替代本地测试记录。

GitHub Release 优先读取 `notes/<tag>.md`，缺失时自动生成；已有 Release 重跑只更新附件，手动编辑过的正文需在 GitHub 单独更新。

## 3. 验收

- Android：核对 Actions、APK、SHA256SUMS、release-info、版本与签名，验证覆盖安装保留数据。
- iOS：核对上传、App Store Connect 处理和 TestFlight 分发，再验证设备安装。构建成功不代表测试者已可安装。
- 在发布操作反馈中说明实际结果和未测项。脚本成功仅表示 Git 推送成功。

失败先核对远端 refs 与工作流。冲突时不打标签；网络失败可能已被远端接收，不直接重建或覆盖标签。不要通过卸载或换签名解决升级问题。
