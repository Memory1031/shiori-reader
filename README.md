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

Shiori（栞，书签）面向 Android 和 iOS，计划提供小说发现与搜索、原生图文阅读、本地书架、阅读进度恢复、缓存离线阅读，以及本地 TXT / 无 DRM EPUB 导入。项目优先打磨阅读体验，并将数据源接入与阅读界面分离，方便后续维护。

当前优先推进 Android；iOS 已于 2026-09-08 完成模拟器 Debug 构建、安装和启动验证，完整 iOS 功能、真机和发布验收仍待完成。Windows 与 macOS 是开发宿主，不是应用目标平台。

## 项目状态

**项目仍在开发，尚未完成全部平台与发布验收。** 生产入口可启动；实现进度与平台验收分别记录，模拟器启动成功不代表完整 iOS 验证通过。

截至 2026-09-08，功能状态依据[任务计划](docs/TASK_PLAN.md)，平台验证以各验收报告为准：

| 模块 | 当前进展 |
| --- | --- |
| Flutter 基础工程 | Android / iOS 工程、应用图标、中英多语言与 VS Code 启动配置已建立 |
| 领域层 | 纯 Dart 领域模型、内容身份摘要与 Source / Repository 契约已交付 |
| 本地导入 | TXT 编码 / 章节、EPUB 包 / 图文 / 目录锚点解析已接入托管入库；书架与阅读闭环留 LOCAL-005 |
| 数据层 | 受限网络客户端、内存图片仓库与 Drift 双库存储（书架 / 进度 / 缓存记录）已交付 |
| 阅读器 | 双模式阅读、图文、跨章与进度恢复已实现；iOS 阅读器专项仍待验 |
| 离线开发入口 | `main_dev.dart` 场景菜单与生产隔离已交付 |
| CI 与发布 | push / PR 离线检查、手动 APK 构建与 tag 触发的签名发布工作流已建立；发布密钥待配置 |
| Android 验证 | Debug APK 构建、MuMu 最小应用启动与 SQLite / preferences 重开探针通过；ARM64 真机验收待完成 |
| iOS 验证 | Simulator Debug 构建 / 安装 / 启动 PASS；IOS-001 部分完成，完整 runtime / 真机 / 发布未通过，见[报告](docs/validation/ios-001.md) |
| 首个数据源调查 | LightNovel.fun 样本图文链路已验证，技术可行性审查通过 |
| 生产数据源 | 在线搜索、详情、目录、正文与图片链路已实现；Android 历史证据见任务计划，iOS 实网专项未验 |

数据源调查工具独立于应用，调查通过不代表移动端功能已经实现。各模块的验证边界以对应文档为准，总览见[任务计划](docs/TASK_PLAN.md)。

## 快速开始

### 环境要求

| 工具 / 平台 | 项目基线 |
| --- | --- |
| Flutter | **3.38.4 stable**，由 `.fvmrc` 固定 |
| Dart | **3.10.3**，随上述 Flutter SDK 提供 |
| Android | 最低 API 24；编译 / 目标 API 36 |
| Java | JDK 17 |
| iOS | 项目最低版本 15.0；本次在 Xcode 26.5 + iOS 26.5 模拟器验证，iOS 15.0 runtime 未测 |
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

### 启动 iOS 模拟器应用

Mac 上使用项目 FVM SDK；先启动 Simulator 并按实际设备 ID 运行：

```sh
fvm flutter devices
fvm flutter run --debug --no-pub --target lib/main.dart -d <设备ID>
```

首次依赖安装、Xcode runtime 缺失处理和已知工具链提示见[开发环境](docs/development.md#macos-ios-模拟器启动验证2026-09-08)与[IOS-001 报告](docs/validation/ios-001.md)。

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

### 离线开发入口

阅读器与图片加载目前通过 fixture 场景体验，不请求源站：

```powershell
flutter run --target lib/main_dev.dart
```

启动后进入场景菜单，也可用 `--dart-define=SHIORI_SCENARIO=场景ID` 直达（场景清单见[离线入口文档](docs/dev-entry.md)）。开发 fixture 与生产入口隔离，不进入 release 构建。

### 构建 APK

在准备好 Android 环境的终端中运行：

```powershell
flutter build apk --debug --no-pub
```

生成文件：`build/app/outputs/flutter-apk/app-debug.apk`。debug 构建使用开发签名；签名 release APK 由推送 `v*` 标签触发的[发布工作流](docs/ci.md)构建，发布签名密钥尚未配置。

## 开发与验证

在仓库根目录运行应用检查：

```powershell
flutter pub get --enforce-lockfile
Push-Location tools/source_probe
dart pub get --enforce-lockfile
Pop-Location
flutter gen-l10n
git diff --exit-code -- lib/l10n/generated
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

根目录静态分析会扫描独立调查包，因此首次检查前也需要安装其依赖。修改文案后需重新生成 `lib/l10n/generated` 并提交。数据库生成代码与 schema 快照由 `tool/generate_database.ps1` 维护，变更方式见[本地存储文档](docs/database.md)。

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
- [x] 建立领域模型、领域契约、受限网络与本地存储。
- [x] 实现双模式阅读视口与单章阅读界面（fixture 驱动，插图经内存图片仓库加载）。
- [ ] 接入生产数据源，实现搜索、详情和卷章节目录。
- [ ] 完善阅读排版与设置。
- [ ] 实现本地书架、阅读历史和进度恢复界面（存储层已就绪）。
- [ ] 实现有容量限制的缓存与离线续读。
- [ ] 实现本地 TXT / 无 DRM EPUB 导入（存储、文件接收和实际解析已接入，书架与阅读闭环待 LOCAL-005 完成）。
- [ ] 完成 Android ARM64 真机验证与发布准备。
- [x] 完成 iOS Simulator Debug 构建、安装与启动 smoke。
- [ ] 完成 iOS 专项功能、iPhone 设备验证与发布准备。

首版聚焦在线轻小说阅读与本地导入，暂不包含账号同步、TTS、PDF / 漫画阅读器或桌面端。任务依赖和验收标准以[任务计划](docs/TASK_PLAN.md)为准。

## 目录结构

```text
shiori-reader/
├── lib/
│   ├── app/                   # 应用组装、导航、主题与启动配置
│   ├── domain/                # 纯 Dart 领域模型、契约与错误
│   ├── data/                  # 受限网络、本地存储与媒体实现
│   ├── features/              # 功能界面（阅读器等）
│   ├── dev/                   # 离线开发入口（fixture 场景）
│   ├── l10n/                  # 中英 ARB 与 gen-l10n 生成代码
│   └── shared/                # 控制器与通用组件
├── android/                   # Android 原生工程
├── ios/                       # iOS 原生工程
├── assets/branding/           # Logo 原图、生成提示词与说明
├── test/                      # 领域 / 数据 / 组件测试
│   └── fixtures/lightnovel/   # 调查记录、结构摘要和合成输入
├── tool/                      # 环境脚本、数据库代码生成与图标工具
├── tools/source_probe/        # 独立 Dart 数据源调查包
├── .github/workflows/         # CI 与 tag 发布工作流
├── docs/                      # 任务计划、验收记录与调查文档
└── .vscode/                   # VS Code 启动配置
```

## 项目文档

| 文档 | 内容 |
| --- | --- |
| [任务计划](docs/TASK_PLAN.md) | 产品范围、架构设计、任务依赖与验收标准 |
| [开发环境](docs/development.md) | 固定工具链、FVM、Windows / macOS 启动说明与历史基线 |
| [iOS 验证](docs/validation/ios-001.md) | Simulator 已通过项、完整 iOS 待验收项与工具链提示 |
| [领域模型](docs/domain.md) | 领域值模型与内容身份摘要规范 |
| [领域契约](docs/contracts.md) | Source / Repository / 错误契约与验收 |
| [本地存储](docs/database.md) | 双库 schema、迁移基线与验收记录 |
| [持续集成](docs/ci.md) | CI 触发方式、依赖锁定与 tag 发布工作流 |
| 验收记录 | [应用](docs/app.md) · [网络](docs/network.md) · [媒体](docs/media.md) · [阅读器](docs/reader.md) · [离线入口](docs/dev-entry.md) · [Fixture](docs/fixtures.md) |
| [数据源调查](docs/source/lightnovel.md) | LightNovel.fun 访问证据、协议观察与可行性审查 |
| [调查工具](tools/source_probe/README.md) | 离线检查、显式联网验证与报告 |
| [测试样本](test/fixtures/lightnovel/README.md) | 样本来源、删减范围与合成数据说明 |
| [Logo 维护](assets/branding/README.md) | 原图位置及 Android / iOS 图标更新方式 |

## 反馈与贡献

欢迎通过 [Issues](https://github.com/Memory1031/shiori-reader/issues) 提交问题或建议。报告问题时，请附上复现步骤、预期与实际行为、设备信息及 Flutter 版本；提交日志前请移除凭据和个人信息。

较大的功能改动建议先讨论范围，并对照任务计划。提交 PR 时说明具体变化及验证结果，将未完成的验证明确列出。

## 许可证

仓库目前尚未添加 `LICENSE` 文件，项目许可证待确定。
