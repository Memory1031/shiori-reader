# Windows / Desktop 支持计划

本计划用于 `feat/windows-support` 分支。首个交付目标仍是 Windows，但共享实现按 Desktop 能力设计，避免把文件导入、宽屏布局、键盘交互等逻辑写成 Windows 专属代码；后续 macOS 应尽量复用同一套 Desktop 适配。

第一阶段目标不是完整桌面产品化，而是让 Shiori 在 Windows 上稳定提供核心阅读能力：在线阅读、本地 TXT / EPUB、书库、阅读进度与原生阅读器。

## 范围

Windows v1 目标：

- Windows Flutter runner 可正常构建与启动
- 支持 TXT / EPUB 文件导入
- 支持本地书库、SQLite、缓存与阅读进度
- 支持现有原生 EPUB / TXT 阅读能力
- 支持 LightNovel.fun 在线搜索、目录与阅读
- 提供 Windows / macOS 可复用的基本桌面交互与宽屏适配
- 提供 Windows CI 与 GitHub Release ZIP 产物

共享 Desktop 设计目标：

- Windows 与未来 macOS 共用 `DesktopImportSource`
- 宽屏布局、键盘翻页、Esc、鼠标 / 滚轮等按 desktop capability 设计，不散落 `Platform.isWindows` 分支
- Parser、Reader、Repository、SQLite、缓存与在线书源继续保持平台无关
- WebView 保留平台差异：macOS 可继续使用官方 `webview_flutter`，Windows v1 使用 fallback，不让少量特殊 HTML 页面阻塞桌面支持

首版不纳入：

- Microsoft Store / MSIX
- Windows 代码签名与自动更新
- `.epub` / `.txt` 文件关联和 Explorer “Open with Shiori”
- macOS runner、签名、公证与正式发布
- 多窗口
- 完整桌面三栏 UI
- 为少量特殊 EPUB HTML 页面单独升级 Flutter 或引入复杂 WebView2 方案

## 计划表

| 阶段 | 工作内容 | 实现方向 | 验收标准 | 优先级 |
| --- | --- | --- | --- | --- |
| 0. 基线 | 建立并维护 Windows 开发分支 | 使用 `feat/windows-support`，只同步 `develop` 必要修复 | Android / iOS 不受影响 | P0 |
| 1. Windows 工程 | 添加 Flutter Windows runner | 生成 `windows/`，保留现有移动端工程配置 | `flutter build windows` 能完成基础编译 | P0 |
| 2. 依赖兼容审计 | 检查 direct dependencies 和平台调用 | 区分 shared / desktop / Windows-only 边界；重点检查 `webview_flutter`、MethodChannel、文件系统、SQLite、`path_provider` | 除已知平台边界外无 Windows compile blocker | P0 |
| 3. Desktop 文件导入 | Windows 支持选择 TXT / EPUB，同时为 macOS 留复用路径 | 保留 `ImportSource` contract；新增 `DesktopImportSource`，优先使用 Dart + `file_selector`；Android / iOS 继续原生桥接 | Windows 可选择 TXT / EPUB 并进入现有 import → managed copy → parse 流程；实现不依赖 Windows 专属 API | P0 |
| 4. App 组装 | 根据平台选择 ImportSource | Android / iOS 使用 `PlatformImportSource`；Windows / macOS 使用 `DesktopImportSource` | 平台组装边界清晰，共享层不引用不存在的平台实现 | P0 |
| 5. WebView 隔离 | 隔离 desktop 平台差异 | `EpubLayoutPage` 做平台实现分离；macOS 保留官方 WebView 路径，Windows v1 对特殊 authored HTML page 提供明确 fallback | Windows 不因 WebView 初始化崩溃；普通 EPUB / TXT 阅读可用；不破坏 Android / iOS / macOS 可用实现 | P0 |
| 6. 核心阅读验证 | 验证现有 Reader 在桌面 viewport 下行为 | 复用 rich reflow、inline image、fixed-image、links、pagination、restore | TXT、EPUB、在线章节均可正常翻页和恢复位置 | P0 |
| 7. Desktop 阅读体验 | 做可复用于 Windows / macOS 的最低限度桌面适配 | 正文限制最大宽度；方向键 / PageUp / PageDown 翻页；Esc 关闭弹层；鼠标滚轮；窗口 resize 后重新分页 | 1080p / 1440p 窗口布局自然，键盘与鼠标可完成主要阅读操作 | P1 |
| 8. Desktop 书库 UI | 检查宽屏布局 | 基于 viewport / breakpoint 限制内容宽度，必要时自适应双列；避免 Windows 专属布局条件 | 1280px+ 窗口无超宽卡片或明显移动端拉伸感 | P1 |
| 9. 数据持久化 | Windows SQLite / AppSupport smoke | 复用现有 Drift `NativeDatabase`、Application Support 与缓存目录 | 重启后书架、进度、设置和缓存正常保留 | P0 |
| 10. 在线书源 | Windows 网络能力 smoke | 复用现有 `NovelSource` / LightNovel.fun adapter | 搜索 → 详情 → 目录 → 阅读完整走通 | P0 |
| 11. CI | 增加 Windows build CI | `windows-latest` + 项目固定 Flutter 版本；外部 Actions 继续完整 SHA pin | Windows release build 可在 CI 稳定完成 | P1 |
| 12. 发布产物 | GitHub Release 增加 Windows | 第一版直接发布 `shiori-reader-vX.Y.Z-windows-x64.zip` | Release 同时提供 Android APK 与 Windows ZIP | P1 |
| 13. 发布前回归 | Windows 专项验收 | 覆盖启动、导入、重启、在线阅读、EPUB 阅读、resize、键盘 / 鼠标操作 | 无阻止 Windows beta 发布的问题 | P0 |
| 14. macOS 跟进 | Windows 稳定后补齐第二个 Desktop target | 生成 macOS runner，复用 `DesktopImportSource` 与 Desktop UI；补 sandbox entitlement、签名 / notarization 与 macOS CI | 核心阅读逻辑不再做结构性重构即可支持 macOS | P2 |

## 推荐实现顺序

```text
Windows runner
    ↓
基础编译通过
    ↓
DesktopImportSource
    ↓
WebView 平台隔离
    ↓
启动 + 导入一本 EPUB / TXT
    ↓
核心 Reader 回归
    ↓
Desktop 键盘 / 鼠标 / 宽屏体验
    ↓
Windows CI
    ↓
ZIP Release
    ↓
复用 Desktop 层补 macOS
```

第一里程碑以“Windows 上成功打开一本 EPUB 并持续阅读”为准，不先投入完整桌面 UI。Windows 稳定后，macOS 应以复用 Desktop 层为主，而不是再建立一套独立桌面架构。

## 架构约束

- Domain 保持纯 Dart，不引入 Windows 或 macOS 平台依赖。
- Parser、Reader、Repository、SQLite、缓存与在线书源逻辑优先复用现有实现。
- 桌面文件导入统一实现为 `DesktopImportSource`，放在 data/platform 边界，不改变 `ImportSource` 的领域语义。
- Android / iOS 的现有 MethodChannel / EventChannel 导入桥保持不变；桌面端不为文件选择另写 Windows C++ 或 macOS Swift bridge，优先使用 Flutter/Dart 桌面插件与 `dart:io`。
- UI 以 mobile / desktop capability 或 viewport breakpoint 分层，避免在共享 Widget 中散落大量 `Platform.isWindows` / `Platform.isMacOS` 条件。
- WebView 是允许保留平台差异的边界：支持的平台继续使用官方实现，Windows v1 可以降级特殊 authored HTML page，但不得阻塞普通 EPUB / TXT / 在线阅读。
- Windows 相关共享改动必须继续检查 Android / iOS 兼容性；Desktop 层设计同时考虑未来 macOS 复用。
