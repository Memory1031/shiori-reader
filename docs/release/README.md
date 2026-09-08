# 发布状态与私下测试

更新：2026-09-08。当前分发范围由用户确认为**个人 / 私下测试**，GitHub 仓库为 private。应用及 ShareExtension 已对齐 `1.0.0+2`，已推送 master / v1.0.0（8821768）；首次发布 APK 构建成功但校验工具输出格式不兼容，未创建 GitHub Release。工具修复及证据见 [CI](../ci.md#android-tag-发布)，正式产物仍待修复后的远端验证。

## 版本与安装身份

正式发布前对齐 `pubspec.yaml` 的版本 / 递增 build number、原生扩展版本及 tag，确认产物来自预期提交。`v*` tag 会启动现有 Android 发布流程，配置见[CI](../ci.md)，不能仅为了查看结果随意创建发布标签。

Android 发布需保管自己的密钥库、别名和密码，并设置仓库 secrets。换电脑可以恢复同一密钥；丢失或换签名可能影响覆盖更新。现有本地 Release 曾使用 Debug 签名，不能将「构建成功」等同正式候选包。为安装新包直接卸载会丢应用数据，应先核对签名与数据保留方式。

iOS 当前使用用户自己的 Personal Team 进行个人设备安装，已有 Release arm64 构建、签名校验及安装 / 启动证据。Runner 和 ShareExtension 需匹配自己的签名与 App Group；不要使用公司 Team。个人开发安装仍受 Xcode 显示的描述文件有效期与能力限制，不是 App Store / TestFlight 分发证据；换电脑需重新配置个人签名环境。

## 发版时核对

- 对最终提交运行质量检查；确认生产入口 `lib/main.dart`，没有开发场景或秘密进入产物。
- 对最终锁文件更新[依赖许可清单](dependencies.md)，核对原生依赖与随包声明。
- 记录 tag / commit、包版本、SHA-256、签名证书标识；检查权限与扩展配置。
- 在目标设备安装 / 覆盖更新、冷启动，检查书架、导入文件、阅读进度与关键翻页行为。
- 确认当前分发范围；公开分发时重新处理以下许可事项。

这些是发版时的检查，不表示本轮文档治理已执行构建、签名或设备验收。

## 许可与隐私边界

代码尚未选定项目许可证。角色品牌素材参考《更衣人偶坠入爱河》的**乾纱寿叶**，用户确认来源，但当前没有授权证明。在线书源接入和小说内容许可尚未确认。private 仓库、隐藏书源品牌名或使用生成图片都不等于取得再分发授权。

应用不附带小说；在线查询与媒体请求会发送给对应第三方服务。书架、进度、偏好和导入原件存于应用本地，Android 系统备份 / 换机迁移可能包含用户数据；缓存与导入暂存按配置排除。iOS 备份排除行为未完成全面验证，因此不承诺所有数据永远只在单台设备上。

## 历史构建审查

2026-09-08 审查过一个 Android Release 编译、Debug 签名 APK：版本 `0.1.0+1`，67697360 字节，SHA-256：

```text
ac9def321c436ed15e1f9b3f5be98fa6978928bb34d855dd6130a5f775d13ed9
```

该包未启用 debuggable，观察到 INTERNET 与签名级动态 receiver 权限，没有所有文件 / 相机 / 联系人权限；检查未发现开发 fixture 入口与密钥标记。结论只适用于该产物，不是最近阅读器改动的重新审计。

Android 真机、iOS 模拟器与 iPhone 已有不同范围的运行证据；完整矩阵和跳过项统一见[验收摘要](../validation/README.md)。

## RELEASE-002 当前进度

2026-09-08：用户已生成个人Android发布密钥并确认四项仓库Secrets已配置；这里只记录用户确认，没有读取或验证真实秘密值。发布工作流已补齐依赖 / 生成 / 格式、tag与版本一致性、四项Secret检查、密码转义、APK签名证书与包版本校验、SHA-256及元数据产物，详见[CI验证](../ci.md#release-002-工作流补齐2026-09-08)。本地合成密钥冒烟通过，不等同正式签名发布验收。

下一步：提交已完成的 EPUB 修复、工作流及 `1.0.0+2` 版本变化，推送 develop 并确认该提交的 CI 通过，再执行下述发布脚本。尚未执行真实 tag 或远端 Release；原有 Debug 签名安装与新正式签名的更新身份不同，安装前核对数据保留方式。

## develop → master 发布脚本

最新发布约定：tag 直接进入 Android 构建，不等待 develop CI，也不在 Release 内重复 UT / analyze。下文“确认 CI”作为日常质量建议，不是发布门禁；版本、工具、签名及 APK 校验仍强制执行。

Release notes 优先读取 `docs/release/notes/<tag>.md`，例如 [v1.0.0](notes/v1.0.0.md)；没有对应文件时使用 GitHub 自动生成说明。说明随 develop 一起提交，tag 指向的内容即发布正文。重复运行已有 Release 只更新附件，保留在 GitHub 上编辑过的说明；需要修改已发布正文时在 GitHub Release 的 Edit 页面操作。

正式版本和标签使用 `1.0.0` / `v1.0.0`。pubspec 的 `+2` 是平台内部构建编号，不进入发布标签。后续支持 `patch`（1.0.0 → 1.0.1）、`minor`（1.0.0 → 1.1.0）、`major`（1.0.0 → 2.0.0）；minor 清零 patch，major 清零 minor / patch，内部构建编号每次递增。

```sh
# 下一版：在干净的 develop 上预览，再应用版本变化。
dart tool/publish_release.dart prepare patch
dart tool/publish_release.dart prepare patch --apply
# patch 可替换成 minor 或 major。
```

准备命令同步 pubspec 和全部 ShareExtension 配置，不提交、不推送、不打标签。审阅并提交版本改动、推送 develop、确认 CI 后，使用工具输出的版本执行发布。重复运行会因未提交改动而停止；版本改动提交后再执行 prepare 则会再次递增。当前已准备好 1.0.0，首次发布无需运行 prepare。

使用项目 Dart SDK，macOS / Windows 命令相同（安装 FVM 时可将 `dart` 换成 `fvm dart`）：

```sh
# 先将本次发布的完整改动提交并推送到 origin/develop，确认 CI 通过。
# 预览：只读取本地状态和远端 refs，不切换分支或创建标签。
dart tool/publish_release.dart v1.0.0

# 执行：合并、附注标签、原子推送，触发 Android Release 工作流。
dart tool/publish_release.dart v1.0.0 --publish
```

[脚本](../../tool/publish_release.dart)固定使用 `origin`、`develop`、`master` 和稳定版 `vX.Y.Z`。要求当前在 develop、工作区干净、本地 develop 与远端一致、标签不存在，且提交中的 pubspec 和所有 ShareExtension 配置版本 / build 一致。不自动提交、修改版本、运行应用测试或查询 CI 状态；应先确认 develop 对应提交的 CI。

- 首次没有 master 时，从 develop 创建 master；已有 master 时优先快进合并以保持已验证提交的 SHA；仅分支分叉时产生合并提交，标签指向 master 的最终提交。已有本地 master 必须与远端一致。
- 执行前 fetch 并核对分支没有变化，合并后再次检查版本配置。附注标签与 master 使用一次 `--atomic` 推送；master 使用明确旧提交的 lease 防止并发覆盖，并要求旧 master 是新提交的祖先，不用于改写历史。不支持 atomic push 或保护规则拒绝时停止，不降级为分开推送。
- 成功后回到 develop；不自动将 master 合并回 develop。后续版本继续在 develop 开发并递增版本 / build。
- 合并冲突时保留 master 冲突现场，不打标签、不推送；检查后可手动 `git merge --abort`。推送失败时保留本地 master / tag，不自动删除或重建；先检查远端 refs（网络中断可能发生在服务端已接收后），核对后再重试同一发布。原脚本会拒绝已有标签，不会重复发布或覆盖。
- 标签触发 Android 签名 APK 工作流；脚本退出成功表示 Git 推送成功，不能代替 Actions 产物、签名和设备验收，也不会发布 iOS 包。

验证：12 项临时本地 Git 仓库测试覆盖三种版本递增及扩展同步、准备失败不写入、只读预览、首次发布、双亲合并提交、重复标签、脏工作区、版本 / 扩展不一致、未推送 develop、master 不一致、冲突及远端拒绝标签的原子性。测试不接触真实 origin。
