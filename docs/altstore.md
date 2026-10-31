# AltStore 侧载

在 AltStore Classic 中添加 Shiori 订阅源，即可安装和更新本项目发布的 IPA。AltStore 负责签名与安装，支持 iOS / iPadOS 15.0+。

## 添加源

先按 [AltStore 官方教程](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)安装 AltServer 和 AltStore，再在设备上选择一个渠道：

| 渠道 | 一键添加 | 源地址（可复制到 AltStore 的 Sources 中手动添加） |
| --- | --- | --- |
| 正式版 | [添加正式版源](https://altstore.io/source/raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store.json) | [alt_store.json](https://raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store.json) |
| Beta | [添加 Beta 源](https://altstore.io/source/raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store_beta.json) | [alt_store_beta.json](https://raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store_beta.json) |

正式版源只收录正式版；Beta 源同时收录正式版和测试版。两个源使用相同的应用 ID，选择一个即可。添加后，在 AltStore 中选择 Shiori 安装。

## 更新与续签

新版本完整发布后，源会自动更新，AltStore 检测到新版时会提示更新。请通过 AltStore 执行覆盖更新，保持原有账号和应用身份；从 Beta 切回正式版时应等待构建号更高的正式版本。

免费账号的应用通常每七天需要续签。AltStore 会尝试在后台刷新签名，常规配置需能连接运行中的 AltServer。安装新版需另行执行更新操作，具体条件见 [AltStore 使用说明](https://faq.altstore.io/altstore-classic/your-altstore)。

应用内选择 EPUB / TXT 或通过系统直接打开文件均可导入。使用系统分享扩展时，主应用和扩展还需获得匹配的 App Group 授权；是否可用取决于实际签名配置。更改 Bundle ID、卸载或更换签名方式前请先备份数据。配置要求见[未签名 IPA 说明](release/README.md#ios-未签名-ipa)。

## 发布维护

发布流程在完整 GitHub Release 公开后执行 `tool/publish_altstore.py --publish`，复验 IPA 的回执、包内身份和公开附件摘要，再更新 `develop` 中的 JSON：正式版更新两个源，测试版只更新 Beta 源。版本、构建号、最低系统和隐私权限来自实际 IPA；版本列表按内部构建号降序排列，重跑不会重复添加同一构建或将旧版置顶。源更新失败不撤回已公开的 Release，修正后重跑工作流。

机器人以最新 `develop` 为基础，只提交对应的源文件，遇到并发修改会重新读取并重试，不强推。发布 job 的 `GITHUB_TOKEN` 需要向 `develop` 写入内容的权限；若分支保护阻止机器人提交，需按仓库规则配置发布权限。
