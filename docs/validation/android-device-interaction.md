# Android 真机基础交互试验

日期：2026-09-08。用户授权对当前连接的 Android 手机尝试交互。本轮仅确认自动化能力，不标记 ANDROID-002 完成。

设备：BMH-AN10，系统报告 Android 12，arm64-v8a，USB 调试已授权，测试时未锁屏。

实际结果：

- 检查时未安装 `dev.shiori.reader`；通过 ADB 安装当前 LOCAL-005 Debug APK 成功。
- 启动应用，显示中文书架首页；可读取应用界面节点并截屏。
- 通过触控注入打开“更多 → 本地文件”，确认目标页面显示本地文件说明与空状态。
- 注入系统返回键后回到书架，核对首页标题和空书架文案成功。
- 保留已安装应用，未清应用数据、未修改网络或系统设置；本次设备临时 UI XML 已清理。

本机截图：`.tooling/evidence/android-device-interaction.png`、`android-device-local-files.png`（不纳入 Git）。本轮未验证导入、阅读、滑动、性能、离线、强杀恢复或 release 安装；这些仍属于 ANDROID-002 / TEST-003 的后续验收。
