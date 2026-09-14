# shiori-local-reader 同步记录

本地阅读器上游仓库 [shiori-local-reader](https://github.com/Memory1031/shiori-local-reader)（本地 `E:\Code\shiori-local-reader`，develop 分支）与本仓库共享本地阅读代码。其本地阅读功能的提交按需移植过来；本页只记录**当前已同步到的上游提交**与移植规则，后续同步直接从该提交之后核对，不必逐文件全量比对。每次同步的内容与对应关系通过提交信息回溯 git 历史，不在本页累积。

## 当前状态

- **已同步到上游提交：`60c9e77`**（2026-09-14）。
- 核对方法：在上游仓库 `git show <已同步提交>:<文件>` 取基线，与本仓库文件 `diff --strip-trailing-cr` 比对；一致的文件直接复制上游新版本，分化的文件只应用上游 hunks。

## 移植规则

- **基线核对**：以上方"已同步到"的提交为基线。上游新提交只改基线一致的文件时，整文件复制；遇两边分化（本仓库在线书源、缓存等）的文件，只应用上游 hunks 并保留本仓库侧内容。
- **命名替换**：`dev.shiori.localreader` → `dev.shiori.reader`，涉及 MethodChannel/EventChannel 名、iOS GCD 队列标签、Kotlin/Swift 包名与源码目录（`dev/shiori/reader/`）。替换会改变字符串字面量长度，复制后需跑 `dart format`。
- **不同步的内容**：上游仓库自身的发布准备与自有约定（版本号、截图、README、release 指南、其 AGENTS.md 等），以及本仓库在线书源模块（`lib/data/sources/`、`lib/data/network/`、`lib/data/cache/`）、pubspec 版本和 docs 中在线相关表述（`docs/source/`、reader.md / contracts.md 的在线段落）。
- **l10n**：arb 按键块合并后运行 `flutter gen-l10n` 重新生成，不直接复制 `lib/l10n/generated/`。
- **工程文件**：Android `build.gradle.kts` 与 iOS `project.pbxproj` 保留本仓库版本（namespace / applicationId / 签名 / 版本号），只应用上游新增内容。
- **提交说明**：本仓库提交信息注明对应上游提交 id；同步完成后更新上方"已同步到"的提交号。
