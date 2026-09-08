# RELEASE-001 Android 私下测试审计

日期：2026-09-08。用户确认本次用途为“仅自己使用 / 私下测试”，且 GitHub 仓库为 private；不申请应用商店上架或公开分发。仓库可见性依据用户确认，本轮未独立访问仓库设置。审计已执行；许可项目未关闭，任务按验收要求保留 BLOCKED，不把技术检查通过等同许可通过。无需为私下测试推断商店政策合规。

## 实际产物

检查既有 `build/app/outputs/flutter-apk/app-release.apk`，未重新构建或安装；SHA-256 为 `ac9def321c436ed15e1f9b3f5be98fa6978928bb34d855dd6130a5f775d13ed9`，67697360 字节。当前仓库 HEAD 为 `9a8cb44be1d512beb29929d1800e95c00223bcf2`，工作区有 CI / 文档变更；此 HEAD 不是 APK 内置的构建来源证明，产物以哈希定位。

| 检查 | 结果与边界 |
| --- | --- |
| 身份 | aapt 实读：`dev.shiori.reader`，Shiori，0.1.0，versionCode 1；私下测试沿用现值，正式发布身份尚未确认 |
| 平台 | min SDK 24，target / compile SDK 36；arm64-v8a、armeabi-v7a、x86_64 |
| 签名 | CI-002 apksigner 记录为 Android Debug 证书；这是 Release 模式测试包，不是正式签名 RC |
| Manifest | 无 debuggable=true；INTERNET 与 `dev.shiori.reader.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` 两项 uses-permission，后者在合并 Manifest 中声明为 signature；无存储 / 联系人 / 相机危险权限 |
| 开发隔离 | 生产 main 只启动 ProductionApp，开发 main 单独引用 dev；APK 没有 fixture、main_dev、keystore、key.properties、.env 文件名。三架构 libapp.so 未命中 FixtureSource / createDevApp / SHIORI_SCENARIO 标记。静态检查支持隔离判断，不替代页面交互验收；不得以 main_dev.dart 构建候选包 |
| 密钥 | APK 文件名和 AOT 未命中检查的私钥标记；不表示已对所有字节完成通用 secret 检测。未读取或复制本机签名密码 |
| 资源 | Flutter 资源包含两个品牌 PNG、WHATWG 许可、MaterialIcons 字体、两个 Flutter shader、manifest / NOTICES；没有打包小说、封面 fixture 或开发场景文件 |
| 日志 | 现有 Release 构建日志 90 行，构建成功，无私钥标记。SDK annotations.zip 损坏警告已知；日志为构建输出，不是设备运行日志。本轮未新增真机日志验收 |

## 依赖与资源许可

[Dart 100 个锁定包及 Android 86 个 Maven 坐标清单](dependencies.md)已生成。97 个包有独立 LICENSE，三个 Flutter 子包适用 SDK 根 BSD-3-Clause；本机 APK NOTICES 解压后 1362584 字节，WHATWG 许可单独打包且由生产入口注册。包许可证不证明业务内容或角色图获得授权，也不保证所有原生附带 NOTICE 已完整覆盖。Maven POM 直接许可声明在当前本机缓存仅找到 1/86 项，其余需要补查原始依赖许可；本轮不将其归为无许可或擅自指定许可类型。

用户确认品牌素材来自《更衣人偶坠入爱河》的**乾纱寿叶**。图标提示词明确要求保持参考角色身份；首页品牌图与图标均按该用户说明记录来源，AI 生成 / 缩放 / 提取不作为授权证明。未收到权利人授权材料，许可状态 UNKNOWN。保留现有 UI，不擅自换图；如将来分发，可提供适用授权或另行设计不沿用该角色的原创品牌资产。

书源现有证据见 [Source 记录](../source/lightnovel.md)：技术访问曾通过，接入 / 内容使用及再分发许可仍 UNKNOWN。本轮未请求源站、未复用历史 live 授权，不把界面隐藏源名称当作许可解决方案。普通联网阅读仍会向第三方服务器请求内容；未声称官方合作关系。

## 数据、备份与说明

生产路径分为 users（用户库、导入文件）与 disposable（可清缓存）；AppLogger 仅保留最多 200 条内存结构化事件，Release 跳过网络 info，未提供任意正文、URL、Cookie 或异常原文日志接口。依赖 / 生产代码扫描未发现接入 Firebase / Sentry / Crashlytics 或分析 SDK；这不是网络抓包证明。

Android 导入走系统文件选择 / 分享入口，无需广泛文件读取权限。系统备份规则排除 import-staging、disposable、development 文件目录，保留用户数据库、导入文件及偏好设置；备份可能由系统云备份 / 设备迁移机制处理。Android 12+ 使用 dataExtractionRules，旧版使用 fullBackupContent，依据 [Android Auto Backup 官方说明](https://developer.android.com/identity/data/autobackup)。本轮只复核配置，未恢复整机备份，不将开发偏好设置也宣称全部排除。

[私下测试说明与版本说明](private-test-notes.md)可随测试包提供；它是当前行为说明，不是应用商店隐私政策或许可证明。首次首页不自动请求源；主动在线搜索 / 阅读会把查询和请求信息发给内容 / 媒体服务，服务器可见网络连接信息。用户自行导入的内容留在应用存储，但可能被系统备份；不可保证“绝不离开设备”。

## 分发边界与待项

1. **品牌许可 UNKNOWN**：作品角色来源已确认，尚无授权证明。
2. **OQ-12 接入 / 内容许可 UNKNOWN**：保留历史问题，不因个人用途判为已授权。
3. **原生依赖通知待核对**：Maven 坐标已列，原始 LICENSE / NOTICE 全量保留情况未验完。
4. **私有仓库 tag 分发**：用户确认仓库为 private，现有 `release.yml` 的 `gh release create` / upload 与私下测试用途一致，保留现有流程。Release 访问受仓库权限约束，不等同公开分发；本轮未推 tag、未创建 Release。若将来改为公开仓库，需重新审查此边界。GitHub 发布访问规则见[官方说明](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。
5. 正式密钥、版本递增、升级保留数据、候选包安装归 RELEASE-002；本轮不生成密钥，不启动后续任务。

OQ-12 Android 结论：私下测试渠道已确认，测试身份已核对；内容 / 角色许可仍未关闭，不能宣布具备公开发布条件。iOS 仅复核共享代码未改、主应用与 Share Extension 元信息仍保留；iOS privacy metadata / bundle identity / 签名及真机发布验收归 IOS-006，不阻塞本次 Android 审计执行，也未宣称 iOS 验收通过。

本轮为只读产物审查及文档变更，没有业务代码修改、无新增依赖，无需重复离线行为测试或构建。文档差异通过 `git diff --check`。
