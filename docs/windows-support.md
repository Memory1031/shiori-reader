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
- 特殊 EPUB HTML 页统一使用 `flutter_inappwebview`，覆盖 Android / iOS / macOS / Windows；共用页面封装，平台差异集中在初始化和能力配置，初始化失败时保留 fallback

首版不纳入：

- Microsoft Store / MSIX
- Windows 代码签名与自动更新
- `.epub` / `.txt` 文件关联和 Explorer “Open with Shiori”
- macOS runner、签名、公证与正式发布
- 多窗口
- 完整桌面三栏 UI
- 为 WebView 单独升级 Flutter，或自行维护原生 WebView2 bridge

## 计划表

状态：✅ 表示本阶段所述实现或基础适配已完成；◐ 表示部分完成、验收未闭环；☐ 表示尚未完成。Windows 本地构建或组件测试通过不等于 Android / iOS / macOS 运行验收通过。

目前核心阅读、桌面阅读交互、书库宽屏布局、Windows 真进程重启持久化与真实在线核心流程已完成验收。Windows WebView 使用固定提交的 fork 补丁处理退出生命周期；后续仍需补齐 Windows CI、ZIP 发布及发布前回归。完整桌面 UI 重设计和字体自由选择仍是后续专项。

| 阶段 | 工作内容 | 实现方向 | 验收标准 | 优先级 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 0. 基线 | 建立并维护 Windows 开发分支 | 使用 `feat/windows-support`，只同步 `develop` 必要修复 | Android / iOS 不受影响 | P0 | ✅ 分支已建立；Android 基础运行已验收，iOS 待验收 |
| 1. Windows 工程 | 添加 Flutter Windows runner | 生成 `windows/`，保留现有移动端工程配置 | `flutter build windows` 能完成基础编译 | P0 | ✅ 已完成，Windows 本地构建通过 |
| 2. 依赖兼容审计 | 检查 direct dependencies 和平台调用 | 区分 shared / desktop / Windows-only 边界；重点检查 `webview_flutter`、MethodChannel、文件系统、SQLite、`path_provider` | 除已知平台边界外无 Windows compile blocker | P0 | ✅ 已完成 Windows 编译兼容检查 |
| 3. Desktop 文件导入 | Windows 支持选择 TXT / EPUB，同时为 macOS 留复用路径 | 保留 `ImportSource` contract；新增 `DesktopImportSource`，优先使用 Dart + `file_selector`；Android / iOS 继续原生桥接 | Windows 可选择 TXT / EPUB 并进入现有 import → managed copy → parse 流程；实现不依赖 Windows 专属 API | P0 | ✅ 已完成，另支持 Windows 文件拖入 |
| 4. App 组装 | 根据平台选择 ImportSource | Android / iOS 使用 `PlatformImportSource`；Windows / macOS 使用 `DesktopImportSource` | 平台组装边界清晰，共享层不引用不存在的平台实现 | P0 | ✅ 已完成平台分流 |
| 5. WebView 统一迁移 | 特殊 EPUB HTML 页统一迁移至 `flutter_inappwebview` | 保持固定 Flutter 工具链，移除现有 `webview_flutter` 依赖；共用 `EpubLayoutPage` 封装，保留禁用脚本、导航限制、主题及翻页行为；Windows 检测 WebView2 Runtime，并使用应用可写的数据目录 | Android / Windows 完成构建与页面运行验证；iOS / macOS 单独记录可用环境下的验收；Runtime 缺失或初始化失败可降级，不阻塞普通 EPUB / TXT / 在线阅读 | P0 | ✅ 迁移及 Windows / Android 基础运行验收完成；iOS / macOS 待独立验收 |
| 6. 核心阅读验证 | 验证现有 Reader 在桌面 viewport 下行为 | 复用 rich reflow、inline image、fixed-image、links、pagination、restore | TXT、EPUB、在线章节均可正常翻页和恢复位置 | P0 | ✅ Windows 原生 smoke 与阅读器回归通过；TXT、EPUB、在线章节离线样本的翻页和恢复已验收，真实联网流程见第 10 项 |
| 7. Desktop 阅读体验 | 做可复用于 Windows / macOS 的最低限度桌面适配 | 正文限制最大宽度；方向键 / PageUp / PageDown 翻页；Esc 关闭弹层；鼠标滚轮；窗口 resize 后重新分页；双页为宽度驱动，大屏平板横屏同样启用，属预期而非桌面专属 | 1080p / 1440p 窗口布局自然，键盘与鼠标可完成主要阅读操作 | P1 | ✅ 实现与专项验收完成；1080p / 1440p 组件回归通过，用户确认 Windows 原生键鼠翻页、Esc 关闭弹层及图片预览、单双页 resize 恢复和 WebView 页内滚动均通过 |
| 8. Desktop 书库 UI | 检查宽屏布局 | 基于 viewport / breakpoint 限制内容宽度，必要时自适应双列；避免 Windows 专属布局条件 | 1280px+ 窗口无超宽卡片或明显移动端拉伸感 | P1 | ✅ 宽屏组件验收通过，覆盖 1280 / 1920 / 2560、显示缩放、中英文、长书名、滚轮及网格 / 列表 resize；用户确认 Windows 原生窗口布局、悬停反馈和阅读返回均通过 |
| 9. 数据持久化 | Windows SQLite / AppSupport smoke | 复用现有 Drift `NativeDatabase`、Application Support 与缓存目录 | 重启后书架、进度、设置和缓存正常保留 | P0 | ✅ 隔离数据目录下，正常退出重启及强制终止后的书架、设置、ContinueReading 位置、缓存与本地媒体恢复通过；采用固定提交的 Windows WebView fork，普通关闭、特殊页关闭、重复开关及 Release ZIP 验收通过 |
| 10. 在线书源 | Windows 网络能力 smoke | 复用现有 `NovelSource` / LightNovel.fun adapter | 搜索 → 详情 → 目录 → 阅读完整走通 | P0 | ✅ Windows Release 真进程通过生产页面回调完成真实在线搜索、详情、目录、正文、往返翻页及首张插图显示验收；搜索封面与其余插图未纳入本轮 |
| 11. CI | 增加 Windows build CI | `windows-latest` + 项目固定 Flutter 版本；外部 Actions 继续完整 SHA pin | Windows release build 可在 CI 稳定完成 | P1 | ☐ 未开始 Windows 构建工作流 |
| 12. 发布产物 | GitHub Release 增加 Windows | 第一版直接发布 `shiori-reader-vX.Y.Z-windows-x64.zip` | Release 同时提供 Android APK 与 Windows ZIP | P1 | ☐ 未开始 Windows ZIP 发布接入 |
| 13. 发布前回归 | Windows 专项验收 | 覆盖启动、导入、重启、在线阅读、EPUB 阅读、resize、键盘 / 鼠标操作 | 无阻止 Windows beta 发布的问题 | P0 | ☐ 待前置项完成后统一验收 |
| 后续专项：Desktop UI 重设计 | 核心能力稳定后，设计适合桌面的应用界面与阅读工作区 | 先确定交互原型，再实现桌面导航、书库、阅读器与设置面板；加入独立的正文字体选择与导入 | 鼠标、键盘和宽窗口下的主要流程自然；移动端体验保持独立适配；字体切换不丢失阅读位置 | P2 | ☐ 已列入计划，尚未开始；含字体自由选择 |
| 14. macOS 跟进 | Windows 稳定后补齐第二个 Desktop target | 生成 macOS runner，复用 `DesktopImportSource` 与 Desktop UI；补 sandbox entitlement、签名 / notarization 与 macOS CI | 核心阅读逻辑不再做结构性重构即可支持 macOS | P2 | ☐ 未开始 |
| 15. 合并收尾 | 合入 develop 前同步对外表述 | README 定位语句与安装表补 Windows；`pubspec.yaml` description 去除 "mobile" 限定；AGENTS.md 平台目标已更新为 Android / iOS / Windows | 合并后仓库对外描述与实际支持平台一致 | P0 | ◐ AGENTS.md 已改；README 与 pubspec 待合并前更新 |

## 推荐实现顺序

```text
Windows runner
    ↓
基础编译通过
    ↓
DesktopImportSource
    ↓
WebView 统一迁移
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

## 后续专项：桌面端界面重设计与字体选择

这是 Windows 核心能力稳定后的独立设计与实现工作，不作为首版兼容适配的前置条件。现有桌面适配用于保障功能可用；后续以桌面上的阅读、查找和管理流程重新设计界面，同时保留移动端适合触摸和窄屏的布局。

### 设计范围

- **应用导航与书库**：设计桌面侧栏、搜索与工具栏，优化宽窗口下的书籍网格 / 列表、信息密度和批量操作；不只是放大移动端卡片。
- **阅读工作区**：保留限宽、单 / 双页切换和整页插图展示，设计目录侧栏、阅读工具栏及设置面板；明确面板展开、收起和窗口缩放时的内容宽度与阅读位置行为。
- **桌面交互**：统一键盘快捷键、焦点顺序、鼠标悬停提示、右键菜单和滚轮行为。按内容与操作需要选择侧栏、浮层或对话框，减少直接沿用移动端底部弹层。
- **字体自由选择**：正文与界面字体独立配置。支持可用系统字体及用户导入的字体文件，优先覆盖 TTF / OTF，字体集合格式按平台能力确认；提供同一段文字的即时预览、字体名称与可用字重，并记住选择。
- **字体与原书样式**：普通正文遵循用户字体偏好；明确特殊 EPUB 页面中原书嵌入字体与用户设置的优先级，默认保留原版式。字体切换重新分页并保持语义阅读位置，不通过拉伸字形改变观感。

### 字体实现约束

- 系统字体的发现与加载放在平台适配边界，Windows 与未来 macOS 共用选择界面和偏好语义。
- 用户导入的字体复制到应用管理目录，不依赖原文件一直存在。处理无效文件、缺失字体及缺字回退，提供恢复默认入口。
- 不将本机安装路径或本机字体直接打包发布；如提供内置字体，先确认再分发许可与安装包体积。
- 预览覆盖中文、英文、日文与常用标点；字号、行高、字重的测量与最终阅读渲染保持一致。

### 实施顺序与验收

1. 梳理桌面主要流程，确定书库、阅读器、目录与设置的设计稿及交互原型，再进入实现。
2. 实现桌面应用外壳与书库布局，再接入阅读工作区；共享数据、解析和阅读进度逻辑，不另建桌面业务层。
3. 接入正文字体选择、导入、预览、偏好持久化及回退。
4. 验证窄 / 宽窗口、常见显示缩放、明暗主题、键盘与鼠标操作；覆盖字体切换、窗口重排、重启恢复和特殊 EPUB 页面，并分别检查移动端兼容性。

完成标准：主要桌面流程不依赖移动端操作习惯；正文可自由选择可用字体，重启后保留偏好，字体切换或缺失时均能继续阅读且不丢失位置。

## 架构约束

- Domain 保持纯 Dart，不引入 Windows 或 macOS 平台依赖。
- Parser、Reader、Repository、SQLite、缓存与在线书源逻辑优先复用现有实现。
- 桌面文件导入统一实现为 `DesktopImportSource`，放在 data/platform 边界，不改变 `ImportSource` 的领域语义。
- Android / iOS 的现有 MethodChannel / EventChannel 导入桥保持不变；桌面端不为文件选择另写 Windows C++ 或 macOS Swift bridge，优先使用 Flutter/Dart 桌面插件与 `dart:io`。
- UI 以 mobile / desktop capability 或 viewport breakpoint 分层，避免在共享 Widget 中散落大量 `Platform.isWindows` / `Platform.isMacOS` 条件。
- WebView 共用 `flutter_inappwebview` 页面封装，允许在该边界集中处理各平台初始化、能力和生命周期差异；保留初始化失败时的降级，不改变普通 EPUB / TXT / 在线阅读的原生渲染路径。
- Windows 相关共享改动必须继续检查 Android / iOS 兼容性；Desktop 层设计同时考虑未来 macOS 复用。
