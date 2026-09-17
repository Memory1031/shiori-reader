# Windows 支持计划

本计划用于 `feat/windows-support` 分支。第一阶段目标不是完整桌面产品化，而是让 Shiori 在 Windows 上稳定提供核心阅读能力：在线阅读、本地 TXT / EPUB、书库、阅读进度与原生阅读器。

## 范围

Windows v1 目标：

- Windows Flutter runner 可正常构建与启动
- 支持 TXT / EPUB 文件导入
- 支持本地书库、SQLite、缓存与阅读进度
- 支持现有原生 EPUB / TXT 阅读能力
- 支持 LightNovel.fun 在线搜索、目录与阅读
- 提供基本桌面交互与宽屏适配
- 提供 Windows CI 与 GitHub Release ZIP 产物

首版不纳入：

- Microsoft Store / MSIX
- Windows 代码签名与自动更新
- `.epub` / `.txt` 文件关联和 Explorer “Open with Shiori”
- 多窗口
- 完整桌面三栏 UI
- 为少量特殊 EPUB HTML 页面单独升级 Flutter 或引入复杂 WebView2 方案

## 计划表

| 阶段 | 工作内容 | 实现方向 | 验收标准 | 优先级 |
| --- | --- | --- | --- | --- |
| 0. 基线 | 建立并维护 Windows 开发分支 | 使用 `feat/windows-support`，只同步 `develop` 必要修复 | Android / iOS 不受影响 | P0 |
| 1. Windows 工程 | 添加 Flutter Windows runner | 生成 `windows/`，保留现有移动端工程配置 | `flutter build windows` 能完成基础编译 | P0 |
| 2. 依赖兼容审计 | 检查 direct dependencies 和平台调用 | 重点检查 `webview_flutter`、MethodChannel、文件系统、SQLite、`path_provider` | 除已知平台边界外无 Windows compile blocker | P0 |
| 3. 文件导入 | Windows 支持选择 TXT / EPUB | 保留现有 `ImportSource` contract；新增 Desktop/Windows adapter，优先使用 Dart + `file_selector` | Windows 可选择 TXT / EPUB 并进入现有 import → managed copy → parse 流程 | P0 |
| 4. App 组装 | 根据平台选择 ImportSource | Android / iOS 继续 `PlatformImportSource`；Windows 使用桌面实现 | 三个平台不会引用不存在的平台实现 | P0 |
| 5. WebView 隔离 | 解决 Windows 无官方 `webview_flutter` backend | 把 `EpubLayoutPage` 做平台隔离；Windows v1 为特殊 authored HTML page 提供明确 fallback | Windows 不因 WebView 初始化崩溃；普通 EPUB / TXT 阅读可用 | P0 |
| 6. 核心阅读验证 | 验证现有 Reader 在桌面 viewport 下行为 | 复用 rich reflow、inline image、fixed-image、links、pagination、restore | TXT、EPUB、在线章节均可正常翻页和恢复位置 | P0 |
| 7. 桌面阅读体验 | 做最低限度桌面适配 | 正文限制最大宽度；方向键 / PageUp / PageDown 翻页；Esc 关闭弹层；窗口 resize 后重新分页 | 1080p / 1440p 窗口布局自然，键盘可完成主要阅读操作 | P1 |
| 8. 本地书库 UI | 检查宽屏布局 | 限制内容宽度，必要时自适应双列，不重做桌面三栏架构 | 1280px+ 窗口无超宽卡片或明显移动端拉伸感 | P1 |
| 9. 数据持久化 | Windows SQLite / AppSupport smoke | 复用现有 Drift `NativeDatabase`、Application Support 与缓存目录 | 重启后书架、进度、设置和缓存正常保留 | P0 |
| 10. 在线书源 | Windows 网络能力 smoke | 复用现有 `NovelSource` / LightNovel.fun adapter | 搜索 → 详情 → 目录 → 阅读完整走通 | P0 |
| 11. CI | 增加 Windows build CI | `windows-latest` + 项目固定 Flutter 版本；外部 Actions 继续完整 SHA pin | Windows release build 可在 CI 稳定完成 | P1 |
| 12. 发布产物 | GitHub Release 增加 Windows | 第一版直接发布 `shiori-reader-vX.Y.Z-windows-x64.zip` | Release 同时提供 Android APK 与 Windows ZIP | P1 |
| 13. 发布前回归 | Windows 专项验收 | 覆盖启动、导入、重启、在线阅读、EPUB 阅读、resize、键盘操作 | 无阻止 Windows beta 发布的问题 | P0 |

## 推荐实现顺序

```text
Windows runner
    ↓
基础编译通过
    ↓
ImportSource 平台化
    ↓
WebView 平台隔离
    ↓
启动 + 导入一本 EPUB / TXT
    ↓
核心 Reader 回归
    ↓
键盘 / 宽屏体验
    ↓
Windows CI
    ↓
ZIP Release
```

第一里程碑以“Windows 上成功打开一本 EPUB 并持续阅读”为准，不先投入完整桌面 UI。

## 架构约束

- Domain 保持纯 Dart，不引入 Windows 平台依赖。
- Parser、Reader、Repository、SQLite 与缓存逻辑优先复用现有实现。
- Windows 文件导入实现放在 data/platform 边界，不改变 `ImportSource` 的领域语义。
- 不为 Windows 首版编写新的 C++ MethodChannel 文件导入桥，优先使用 Flutter/Dart 桌面插件与 `dart:io`。
- 不为了特殊 WebView 页面而阻塞普通 EPUB / TXT / 在线阅读能力。
- Windows 相关共享改动必须继续检查 Android / iOS 兼容性。
