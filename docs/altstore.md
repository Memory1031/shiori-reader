# AltStore 侧载

Shiori 提供 AltStore Classic 订阅源，使用 GitHub Release 的未签名 IPA，由 AltStore 完成重签和安装。适用于 iOS / iPadOS 15.0+。

## 添加源

先按 [AltStore 官方教程](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)安装 AltServer 和 AltStore，再在设备上选择一个渠道：

| 渠道 | 一键添加 | 源地址（可复制到 AltStore 的 Sources 中手动添加） |
| --- | --- | --- |
| 正式版 | [添加正式版源](https://altstore.io/source/raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store.json) | [alt_store.json](https://raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store.json) |
| Beta | [添加 Beta 源](https://altstore.io/source/raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store_beta.json) | [alt_store_beta.json](https://raw.githubusercontent.com/Memory1031/shiori-reader/develop/alt_store_beta.json) |

正式版源只提供正式版，Beta 源同时提供正式版与测试版，按内部构建号从新到旧排列；两者使用相同的应用 ID，请选择其中一个。源收录已完整发布并通过校验的 IPA。添加源后，在 AltStore 中选择 Shiori 安装。

## 更新与续签

新版本完整发布后，源会自动更新，AltStore 检测到新版时会提示更新。请通过 AltStore 执行覆盖更新，保持原有账号和应用身份；从 Beta 切回正式版时应等待构建号更高的正式版本。

免费账号的应用通常需要每七天续签；AltStore 会尝试后台刷新签名，常规配置需能连接运行中的 AltServer。续签不等于安装新版，订阅源不保证后台自动升级。具体条件见 [AltStore 使用说明](https://faq.altstore.io/altstore-classic/your-altstore)。

应用内选择 EPUB / TXT 或系统直接打开文件的导入方式不依赖 App Group；系统分享扩展需要主应用和扩展获得匹配的 App Group 授权。AltStore 重签后的分享与升级数据保留仍需真机验证。更改 Bundle ID、卸载或更换签名方式可能影响原有数据，请先保全。完整权限边界见[未签名 IPA 说明](release/README.md#ios-未签名-ipa)。

## 发布维护

发布流程在完整 GitHub Release 公开后执行 `tool/publish_altstore.py --publish`，复验 IPA 的回执、包内身份和公开附件摘要，再更新 `develop` 中的 JSON：正式版更新两个源，测试版只更新 Beta 源。版本、构建号、最低系统和隐私权限来自实际 IPA；版本列表按内部构建号降序排列，重跑不会重复添加同一构建或将旧版置顶。源更新失败不撤回已公开的 Release，修正后重跑工作流。

机器人以最新 `develop` 为基础，只提交对应的源文件，遇到并发修改会重新读取并重试，不强推。发布 job 的 `GITHUB_TOKEN` 需要向 `develop` 写入内容的权限；若分支保护阻止机器人提交，需按仓库规则配置发布权限。
