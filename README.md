<p align="center">
  <img src="assets/branding/shiori-chibi-logo-v1.png" alt="Shiori：捧着书的粉发 Q 版角色" width="160" />
</p>

<h1 align="center">Shiori · 栞</h1>

<p align="center">一个正在开发中的 Flutter 轻小说阅读器，让找到一本书、继续阅读变得简单。</p>

<p align="center">
  <a href="#项目状态">项目状态</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#开发路线">开发路线</a> ·
  <a href="#项目文档">项目文档</a>
</p>

## 关于 Shiori

Shiori（栞，书签）面向 Android 和 iOS，计划提供小说发现与搜索、原生图文阅读、本地书架、阅读进度恢复和缓存离线阅读。项目优先打磨阅读体验，并将数据源接入与阅读界面分离，方便后续维护。

当前优先开发和验证 Android；iOS 保留为正式目标，等待 macOS / Xcode 环境进行构建和运行验证。Windows 是开发宿主，不是应用目标平台。

## 项目状态

**项目处于早期开发阶段，尚未完成可日常使用的阅读器。** 当前启动后显示最小 Shiori 页面，搜索、目录、阅读和书架功能尚未接入应用。

截至 2026-09-07：

| 模块 | 当前进展 |
| --- | --- |
| Flutter 基础工程 | 已建立 Android / iOS 工程、应用图标和 VS Code 启动配置 |
| Android 验证 | Debug APK 构建及 MuMu 最小应用启动验证通过；ARM64 真机验收待完成 |
| iOS 验证 | 已做基础代码与配置兼容性审查；尚未构建或运行 |
| 首个数据源调查 | LightNovel.fun 样本图文链路已验证，技术可行性审查通过 |
| 调查工具与样本 | 独立 Dart 调查包、离线测试及 fixture 已建立 |
| 产品功能 | 生产数据源、阅读器、书架、进度和缓存仍在规划中 |

数据源调查工具独立于应用，调查通过不代表移动端功能已经实现。具体进展见[任务计划](docs/TASK_PLAN.md)。

## 快速开始

### 环境要求

| 工具 / 平台 | 项目基线 |
| --- | --- |
| Flutter | **3.38.4 stable**，由 `.fvmrc` 固定 |
| Dart | **3.10.3**，随上述 Flutter SDK 提供 |
| Android | 最低 API 24；编译 / 目标 API 36 |
| Java | JDK 17 |
| iOS | 项目最低版本 15.0；构建需要 macOS 与 Xcode，当前未验证 |
| 编辑器 | VS Code + Flutter / Dart 扩展，或其他 Flutter 开发环境 |

请使用固定的 Flutter 版本。Android SDK、NDK、Gradle 与本地 JDK 的完整配置见[开发环境说明](docs/development.md)。

### 获取代码与依赖

```powershell
git clone https://github.com/Memory1031/shiori-reader.git
cd shiori-reader
flutter --version
flutter pub get --enforce-lockfile
```

仓库不包含 `.tooling/` 下的 SDK、JDK 或构建缓存。首次克隆需要先准备开发工具；依赖安装需要网络。

### 启动 Android 应用

启动模拟器，或连接已开启 USB 调试的 Android 设备。如果使用[开发环境说明](docs/development.md)中的项目本地工具布局，先在当前 PowerShell 终端加载环境：

```powershell
. ./tool/android-env.ps1
```

然后检查设备并运行：

```powershell
flutter devices
flutter run
```

已自行配置系统工具链时，无需加载上述本地环境脚本。存在多个设备时，使用 `flutter run -d "设备ID"` 指定 `flutter devices` 列出的目标。

### 在 VS Code 中启动

1. 打开仓库根目录，安装 Flutter / Dart 扩展。
2. 启动模拟器或连接设备，在状态栏选择目标设备。
3. 打开“运行和调试”，选择 **Shiori (Debug)**，按 **F5**。

[launch.json](.vscode/launch.json) 还提供 `Shiori (Profile)` 和 `Shiori (Release)`。Windows 配置使用项目 `.tooling/` 下的 Android SDK、JDK 与 Gradle 缓存；如果使用系统工具链，请相应调整其中的 `windows.env`。

### 构建 APK

在准备好 Android 环境的终端中运行：

```powershell
flutter build apk --debug --no-pub
```

生成文件：`build/app/outputs/flutter-apk/app-debug.apk`。当前签名配置用于开发验证，正式发布配置尚未完成。

## 开发与验证

在仓库根目录运行应用检查：

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

数据源调查包有独立的依赖与测试，在仓库根目录另开终端运行：

```powershell
cd tools/source_probe
dart pub get --enforce-lockfile
dart --suppress-analytics analyze
dart --suppress-analytics test
dart bin/source_probe.dart
```

安装依赖后，调查程序默认离线运行，使用本地样本且不请求源站。显式联网验证的参数、请求预算和报告说明见[调查工具文档](tools/source_probe/README.md)。

## 开发路线

- [x] 建立移动端基础工程与应用图标。
- [x] 完成首个数据源的样本调查与技术可行性验证。
- [ ] 建立领域模型、基础网络与本地存储。
- [ ] 实现生产数据源、搜索、详情和卷章节目录。
- [ ] 实现原生垂直滚动阅读器、插图与排版设置。
- [ ] 实现本地书架、阅读历史和进度恢复。
- [ ] 实现有容量限制的缓存与离线续读。
- [ ] 完成 Android ARM64 真机验证与发布准备。
- [ ] 完成 iOS 构建、设备验证与发布准备。

首版聚焦在线轻小说阅读，暂不包含账号同步、TTS、EPUB / PDF 导入或桌面端。任务依赖和验收标准以[任务计划](docs/TASK_PLAN.md)为准。

## 目录结构

```text
shiori-reader/
├── lib/                       # Flutter 应用，当前为最小启动页面
├── android/                   # Android 原生工程
├── ios/                       # iOS 原生工程
├── assets/branding/           # Logo 原图、生成提示词与说明
├── test/                      # 应用测试与数据源样本
│   └── fixtures/lightnovel/   # 调查记录、结构摘要和合成输入
├── tool/                      # 本地 Android 环境与图标生成脚本
├── tools/source_probe/        # 独立 Dart 数据源调查包
├── docs/                      # 任务计划、开发基线与源站调查
└── .vscode/                   # VS Code 启动配置
```

## 项目文档

| 文档 | 内容 |
| --- | --- |
| [任务计划](docs/TASK_PLAN.md) | 产品范围、架构设计、任务依赖与验收标准 |
| [开发环境](docs/development.md) | 固定工具链、Windows 配置、构建记录与已知问题 |
| [数据源调查](docs/source/lightnovel.md) | LightNovel.fun 访问证据、协议观察与可行性审查 |
| [调查工具](tools/source_probe/README.md) | 离线检查、显式联网验证与报告 |
| [测试样本](test/fixtures/lightnovel/README.md) | 样本来源、删减范围与合成数据说明 |
| [Logo 维护](assets/branding/README.md) | 原图位置及 Android / iOS 图标更新方式 |

## 反馈与贡献

欢迎通过 [Issues](https://github.com/Memory1031/shiori-reader/issues) 提交问题或建议。报告问题时，请附上复现步骤、预期与实际行为、设备信息及 Flutter 版本；提交日志前请移除凭据和个人信息。

较大的功能改动建议先讨论范围，并对照任务计划。提交 PR 时说明具体变化及验证结果，将未完成的验证明确列出。

## 许可证

仓库目前尚未添加 `LICENSE` 文件，项目许可证待确定。
