# ANDROID-002 Android 真机兼容与存储验证

日期：2026-09-08。状态：**DONE（按用户确认的验收范围）**。核心真机兼容检查通过，主题色功能已交付。用户明确决定不再执行完整系统备份恢复及文件系统空间耗尽验证，并将 ANDROID-002 标记完成；两项保留 NOT_RUN 记录，不计为测试通过，也不再阻塞本任务关闭。

## 环境与构建

| 项目 | 实际证据 |
| --- | --- |
| 真机 | BMH-AN10，系统报告 Android 12 / API 31，arm64-v8a，1080 × 2400，density 480 |
| 官方模拟器 | Android 16 / API 36.1，arm64；Profile 存储探针交叉通过，Release 安装启动成功 |
| 工具链 | 项目 FVM Flutter 3.38.4 / Dart 3.10.3，JDK 17，NDK 28.2.13676358 |
| Profile | 独立 `integration_test/android_storage_smoke.dart` 入口，最终构建 24.4 秒 |
| Release | 正式 `lib/main.dart` 入口，构建 76.4 秒，ARM64 APK 29.4 MB；真机与官方模拟器安装启动成功 |
| 签名 | 本地未配置正式签名，Release 使用现有 debug 证书回退；不是正式签名 RC |

Release 构建发现 SDK `platforms/android-36/data/annotations.zip` 的 `zip END header not found` 警告，构建最终成功。该警告属于本机 SDK 文件，未在本轮重新下载工具链，保留供环境治理跟踪。

## 修复与主题色

- 主 Manifest 原先没有 `INTERNET`，权限仅存在于 debug / profile。补入主 Manifest，修复正式包缺少联网权限的问题。检查编译后的 Release APK，确认有 INTERNET，无外部存储或所有文件访问权限。
- “更多 → 应用外观”增加青绿、蓝灰、暖棕三项，默认青绿；保留布局、字体与纸张背景。阅读器操作控件继承强调色，阅读纸张仍由阅读设置独立控制。
- AppSettings 升为 schema v2，v1 保留原明暗选择并默认青绿。快速连续切换仍采用既有有序偏好保存机制。
- 真机 Release 实际点击三项成功；选蓝灰、强制停止、重启后再次打开面板，蓝灰仍选中。测试结束选回青绿。
- 完整离线测试 **375 项通过**，`flutter analyze` 无问题；覆盖三种颜色的明暗对比度、偏好迁移与保存。新增探针格式检查通过。

## 真机执行结果

探针使用自写 TXT、测试 EPUB 和自制图片，独立存储于应用私有的 `android002-probe-v1` 目录，内部使用 development 环境；不操作正式用户书库，不作为生产入口。

| 检查 | 结果与范围 |
| --- | --- |
| 文件 / SQLite | TXT 与 EPUB 解析、托管导入、相同字节去重、索引重开通过；不是本轮系统文件选择器验收 |
| 缓存清理 | 写入自制章节及持久图片后清缓存，用户库两本书与已存进度仍保留 |
| 离线图片 | 关闭并重开数据库，使用仅本地 Repository 读取 EPUB 图片并执行真实图片解码通过 |
| 低存储错误 | 独立故障库限制 SQLite max_page_count，触发真实 SQLITE_FULL；返回 database 失败、索引及托管文件回滚，其他书库不受影响。未填满手机文件系统，不代证文件写入 ENOSPC |
| TLS | 真机与官方模拟器各一次 HTTPS example.com 请求通过系统证书校验并返回 200，无重试、无绕过证书校验；未发起生产 Source 请求，不代证源站会话链路 |
| 滚动 / 旋转 | 真机触控滚动、横屏、恢复竖屏及后台切换完成，阅读正文没有观察到溢出；仅当前阅读样例，非全页面 UX 矩阵 |
| 杀进程 / 离线冷启动 | 关闭 Wi-Fi 和移动数据后 force-stop，再启动成功显示本地正文；SQLite 中 blockIndex=40、blockFraction=0 与关闭前一致 |
| 内存 | Release 首页外观面板单次 PSS 71,557 KB、RSS 148,324 KB；不是阅读压力、泄漏或性能门槛通过依据，定量测量留 TEST-003 |
| 正式入口 | Release 安装、书架启动、主题切换和系统返回成功；替换安装保留已有应用数据 |

首版探针冷启动失败来自重新生成 EPUB 的 ZIP 时间戳变化，导致样例不再满足按字节去重；已修为复用托管原件。修正后的真机冷启动报告 `cold: true, status: PASS`，并独立核对数据库和实际截图。旧失败截图、旧 `cold: false` 报告不能作为冷启动通过证据。官方模拟器本轮仅使用已确认的首次 Profile 成功与 Release 安装证据，不声称其第二次冷启动通过。

测试后已恢复手机原有 Wi-Fi、移动数据及自动旋转设置，未卸载或清除应用数据；手机保留正式 Release 入口。

## 备份与剩余验收

- 静态及编译配置核对：两代 Android 备份 XML 均排除 production import-staging、disposable 和常规 development 目录，Android 12 的 cloud-backup / device-transfer 均配置；原生导入 inbox 使用 noBackupFilesDir。生产会话维持既有 no-op 基线，本轮未增加凭据持久化。
- **完整系统 backup / restore 未执行**。设备仅列出 LocalTransport；本轮没有切换备份 transport、清应用数据或恢复用户书库。该 Android 验证项按用户决定跳过，配置检查不能替代恢复实测；OQ-08 的 iOS 部分仍按 IOS-005 跟踪。
- 独立探针目录不等同于常规 development 根目录，可能在替换安装后保留；不得用包含探针数据的当前安装声称正式备份隔离已通过。
- 文件系统实际耗尽、长时间多图滚动与内存增长未测；CACHE-004 原有完整 ARM64 压力门槛不因本轮小样本自动关闭。
- 全页面大字、TalkBack、键盘和手势矩阵属于 UX-001；性能定量属于 TEST-003；正式签名 RC 属于 RELEASE-002。本轮未自动启动这些任务。
- iOS 共享改动使用既有 Flutter 主题、纯 Dart 设置模型及现有偏好存储，无新增依赖或 iOS 原生接口；本轮仅做兼容代码审查，未进行 iOS 构建或 runtime 验证。

## 可复跑入口与本机证据

默认不联网：

```sh
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter build apk --profile \
  --target integration_test/android_storage_smoke.dart \
  --target-platform android-arm64 --no-pub
```

显式 TLS 检查需追加 `--dart-define=ANDROID002_TLS=true --dart-define=ANDROID002_RUN=<唯一运行标识>`。每个标识最多尝试一次 HTTPS；首次建立探针样例，再杀进程启动检查重开。读取报告前移除旧探针报告或核对 `cold`，不能只根据遗留 PASS 判断当前进程成功。设备安装需明确指定目标序列号；完成后换回正式入口 APK。

本机 `.tooling/evidence/`（不纳入 Git）：

- `android002-tests.log`、`android002-analyze.log`、`android002-release-build.log`、`android002-profile-build-v2.log`。
- `android002-phone-profile-report.json`、`android002-emulator-profile-report.json`、`android002-phone-cold-report.json`。
- `android002-phone-landscape.png`、`android002-phone-cold-v2.png`、`android002-phone-cold-v2.sqlite`。
- `android002-release-bluegrey-restart.png`、`android002-release-warmbrown.png`、`android002-release-teal.png`、`android002-release-memory.txt`。

此前的基础交互能力记录见 [android-device-interaction.md](android-device-interaction.md)。

## 2026-09-08 配色追加调整

按用户反馈，亮色模式将按钮、选中背景、色样与空书架装饰改为浅色填充，前景采用较深同色系；新增淡粉可选项，已有三套深色模式保持不变。四套配色的前景 / 容器对比度检查通过，外观及偏好回归 6 项通过，analyze 无问题。正式入口 Release 重建成功并替换安装到同一真机；本轮未重跑先前存储验收或 iOS runtime。日志为 `.tooling/evidence/accent-soft-{tests,contrast,analyze,build}.log`。
