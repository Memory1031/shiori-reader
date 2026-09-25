# Desktop 与版本演进路线图

本文记录 Shiori 在 Android、iOS 与 Windows 基础能力已经可用之后的后续产品与工程方向。已完成的 Windows bring-up、CI、ZIP 发布和专项验收不再在这里重复维护；需要追溯时查看 Git 历史和对应 Release。

## 当前基线

- Android、iOS、Windows 为当前应用目标平台；Windows 以 x64 便携 ZIP 分发。
- 本地阅读支持 TXT 与无 DRM 的流式 EPUB，在线阅读继续通过 Source 抽象接入。
- Windows 已支持文件选择 / 拖入、键盘与滚轮翻页、宽屏单 / 双页、本地书库、阅读进度、设置与缓存恢复。
- 特殊 EPUB HTML 页面统一由 `flutter_inappwebview` 承载；Windows 子包固定到已验证的 fork commit，普通正文仍走原生 Flutter 阅读器。
- 发布流程支持正式标签 `vX.Y.Z` 和 Beta 标签 `vX.Y.Z-beta.N`。Beta 直接标记 develop 提交并发布为 GitHub Pre-release；正式版进入 master 并作为稳定 Release。
- Android 与 Windows 从同一 GitHub Release 获取 APK / ZIP 产物；iOS 继续通过签名构建和 TestFlight 分发。

## 路线图

| 方向 | 目标 | 优先级 |
| --- | --- | --- |
| Desktop UI 重设计 | 将当前“功能可用”的宽屏适配升级为完整桌面应用外壳、书库与阅读工作区 | P0 |
| 阅读工作区 | 目录、工具栏、进度、设置和辅助面板按桌面交互重新组织，不再沿用移动端底部弹层思路 | P0 |
| 字体系统 | 支持系统字体与用户导入字体，切换后保持语义阅读位置并重新分页 | P1 |
| 更新基础设施 | 建立统一 Release 版本模型、Stable / Beta 通道和 GitHub Release 元数据读取 | P0 |
| Android 自动更新 | 应用内检查、下载和校验 APK，交给系统安装器确认覆盖升级 | P1 |
| Windows 自动更新 | 在便携 ZIP 分发模式下增加独立 updater，完成下载、校验、替换、回滚和重启 | P1 |
| macOS | 复用 Desktop UI、导入和阅读能力，补 runner、sandbox、签名、公证与发布 | P2 |
| 桌面分发完善 | 文件关联、安装器 / MSIX、Windows ARM64、多窗口等按实际需求继续评估 | P2 |

1.3.0 的主要产品目标是 Desktop UI 与整体视觉 / 交互重设计。自动更新可以与 UI 重设计并行设计，但不为了赶 1.3.0 牺牲升级安全或回滚能力；完整 Windows 自更新可在 1.3.x 继续落地。

## Desktop UI 重设计

现有桌面适配解决的是“能用”：限宽正文、双页、键盘 / 鼠标操作和宽屏书架已经具备。下一阶段要解决的是“像桌面应用”，并保持移动端继续使用适合触摸和窄屏的交互。

### 应用外壳与导航

- 为宽窗口设计稳定的桌面导航结构，优先考虑侧栏、顶部工具栏和内容工作区，而不是放大移动端页面。
- 搜索、书架、本地书籍、设置等一级入口在桌面端保持可发现，并减少多层返回。
- 统一窗口最小宽度、主要 breakpoint、内容最大宽度和侧栏展开 / 收起行为。
- 桌面特有行为放在 capability / viewport 边界，不在业务 Widget 中散落 `Platform.isWindows`。

### 书架与管理

- 优化网格 / 列表的信息密度、封面尺寸、悬停、选中与快捷操作。
- 宽屏下支持更合理的搜索、筛选和本地书籍管理入口。
- 长书名、无封面、空书架、加载失败和维护状态都需要有明确的桌面布局。
- 后续若增加批量操作，应先定义选择模型和键鼠交互，不复用移动端长按语义硬套桌面。

### 阅读工作区

- 保留当前单 / 双页、整页插图、特殊 EPUB 页面和 resize 后语义位置恢复能力。
- 将目录、阅读进度、排版设置、本章注释等重组为适合桌面的侧栏 / 面板 / 工具栏。
- 侧栏展开、窗口 resize、字体切换和单双页切换都不能丢失阅读位置。
- 明确键盘快捷键、焦点顺序、鼠标悬停、滚轮、Esc 和右键菜单行为。
- 特殊 EPUB WebView 页保持与普通 Reader 一致的主题、导航和关闭语义，不让 WebView 生命周期泄漏到阅读器其他模块。

### 视觉与组件

- 建立桌面与移动端共用的颜色、圆角、间距、Typography 等基础 token；布局和交互根据平台能力分化。
- 统一按钮、卡片、空状态、加载状态、错误状态和弹层视觉，减少页面级临时样式。
- UI 重设计完成后更新 README 截图，至少展示书架、移动端阅读和 Windows 双页阅读。

## 字体系统

字体是 Desktop UI 重设计后的独立能力，但需要从一开始预留到阅读设置和分页模型中。

- 正文字体与界面字体分开；普通正文遵循用户阅读字体偏好。
- Windows 首先支持发现可用系统字体，并允许用户导入 TTF / OTF；未来 macOS 复用相同偏好语义。
- 用户导入字体复制到应用管理目录，不依赖原文件持续存在。
- 保存稳定的字体身份，不把本机绝对路径写入领域模型或同步到日志。
- 处理字体损坏、缺字、字体被删除和回退到系统默认的情况。
- 字体切换触发重新分页，但恢复到原语义阅读位置。
- 特殊 EPUB 页面默认优先保留出版方内嵌字体；用户正文偏好不应无条件覆盖原版式页面。
- 字体预览至少覆盖中文、英文、日文和常用标点，并与最终正文使用相同测量参数。

## GitHub Release 自动更新

自动更新建立在当前 GitHub Release 流程上，不引入独立更新服务器。GitHub 只负责 Release 元数据和产物托管，版本选择、校验和安装由客户端负责。

### 版本与更新通道

当前平台包内部仍使用纯基础版本和递增构建号，例如：

```text
pubspec: 1.3.0+21
tag:     v1.3.0-beta.1
```

Beta 身份来自 Release tag，不把 `-beta.N` 强行写入 Android / iOS / Windows 的基础版本字段。更新逻辑因此不能只比较 `versionName`。

统一版本模型至少需要区分：

- Release tag：`v1.3.0-beta.2` / `v1.3.0`
- 基础版本：`1.3.0`
- 内部构建号：Android `versionCode` / iOS `CFBundleVersion` / Windows 发布元数据中的 build
- 是否 prerelease
- 平台、架构、asset 名称与 SHA-256

版本顺序定义为：

```text
1.3.0-beta.1 < 1.3.0-beta.2 < 1.3.0 < 1.3.1-beta.1 < 1.3.1
```

更新通道：

- **Stable**：只选择非 prerelease 的最高可用版本。
- **Beta**：允许 Beta 和 Stable，始终选择高于当前安装版本的最高可用版本；正式 `1.3.0` 应高于所有 `1.3.0-beta.N`。
- 开发 / Debug 构建不自动假装属于某个公开 Release。

为了让客户端在离线状态下也知道自己来自哪个 Release，正式 / Beta 构建需要在构建阶段注入当前 tag 或等价的 release identity；不要仅从基础版本号反推。

### 共享 UpdateService

更新检查放在独立的数据 / 应用服务边界：

```text
GitHub Releases
      ↓
GitHubUpdateSource
      ↓
ReleaseVersion / AppUpdate
      ↓
UpdateService
      ↓
Android installer / Windows updater
```

要求：

- Domain 不依赖 GitHub API、HTTP client 或平台安装接口。
- GitHub adapter 负责解析 Releases、选择平台 asset、读取 release notes 与校验信息。
- UpdateService 负责通道选择、版本比较、下载状态、取消和错误分类。
- UI 共用“检查更新 / 发现版本 / 下载进度 / 稍后 / 更新”等状态，安装阶段再进入平台实现。
- 检查更新失败不得阻塞启动、阅读或本地书库。

## Android 自动更新

目标流程：

```text
检查 GitHub Release
        ↓
选择 android.apk
        ↓
下载到应用临时目录
        ↓
校验版本与 SHA-256
        ↓
调用 Android 系统安装器
        ↓
用户确认覆盖安装
```

约束：

- 不以静默安装为目标；普通分发包由系统安装 UI 完成最终确认。
- 继续依赖 Android 包签名保证覆盖安装只能由相同应用签名完成。
- 下载前后校验 package id、版本 / build 和资产摘要，失败时删除临时文件。
- Android 8+ 需要在系统允许当前来源安装应用后才能拉起安装流程；未授权时给出明确引导。
- 下载、取消、安装失败和用户拒绝都不能破坏现有安装。
- Stable / Beta 更新通道使用同一安装实现，只改变 Release 选择规则。

## Windows 自动更新

当前 Windows 是便携 ZIP，不能依赖应用进程原地覆盖自己的可执行文件。完整自更新需要独立 updater。

目标流程：

```text
shiori.exe
   ↓
检查 / 下载新版 ZIP
   ↓
验证 release metadata 与 ZIP
   ↓
将 updater 复制到临时目录并启动
   ↓
Shiori 正常退出
   ↓
updater 等待原进程结束
   ↓
解压到 staging
   ↓
验证新 bundle
   ↓
替换程序目录
   ↓
失败则回滚
   ↓
重新启动 shiori.exe
```

约束：

- updater 从临时副本运行，避免自身正在执行时阻止整个安装目录替换。
- 书架、进度、设置和缓存继续存放在应用数据目录，更新器不得迁移或修改用户数据库。
- 下载与解压必须在安装目录之外的 staging 中完成，全部校验通过后才进入替换阶段。
- 替换前保留可回滚的旧程序目录；启动新版本失败或文件替换失败时恢复旧版本。
- 仅在安装目录可写时提供一键更新；不可写时降级为打开 / 下载 GitHub Release 并提示手动更新。
- 更新过程中防止并发启动两个 updater，并记录不包含用户内容或本机敏感路径的诊断信息。
- updater 与主程序都必须能够被下一版本更新；不要把 updater 设计成永久不可替换的外部安装组件。

### 更新资产信任

当前 Release 已生成平台 SHA-256 和 release-info 文件，可直接作为下载完整性检查的基础。

真正启用 Windows 自动替换前，还应明确更新元数据的信任边界：

- 至少校验 GitHub Release tag、目标 commit、asset 名称、平台 / 架构、版本和 SHA-256 一致。
- 如果需要防止 Release 资产和校验文件被同时篡改，增加独立签名的 update manifest；客户端内置公钥，签名私钥只在发布侧使用。
- 不把 GitHub token 或更新签名私钥放入客户端。

## iOS 更新边界

iOS 不通过 GitHub 下载 IPA 后自行覆盖安装。

- Beta 继续使用 TestFlight。
- 正式分发若进入 App Store，则由系统 / App Store 负责更新。
- 共享 UpdateService 可以在未来用于展示版本信息，但不能绕过 iOS 平台安装机制。
- iOS 的版本与构建号继续和 Android / Windows 共用发布准备流程。

## macOS 后续

macOS 不是 1.3.0 的前置条件。Windows Desktop UI 稳定后再补齐：

- Flutter macOS runner。
- 复用 `DesktopImportSource`、书架、阅读工作区、字体偏好和键鼠交互。
- sandbox entitlement、文件访问边界、签名与 notarization。
- 独立 macOS CI 和 Release 产物。
- 自动更新在签名 / 公证分发稳定后再设计，不直接复用 Windows ZIP 替换流程。

## 其他 Desktop 方向

以下能力不作为 1.3.0 前置条件：

- `.epub` / `.txt` 文件关联和 “Open with Shiori”。
- Windows 安装器或 MSIX，以及 Store 分发。
- Windows ARM64。
- 多窗口 / 多阅读会话。
- 更完整的桌面右键菜单、拖拽排序和批量管理。
- macOS 正式分发和自动更新。

这些能力应在 Desktop 主界面、阅读工作区和更新模型稳定后按真实使用需求逐项加入。

## 架构约束

- Domain 保持纯 Dart，不引入 Windows、macOS、GitHub、文件下载或安装器依赖。
- Parser、Reader、Repository、SQLite、缓存和 Source 逻辑继续平台无关。
- Desktop 文件导入继续通过 `DesktopImportSource`，不因为 UI 重设计改变导入领域语义。
- Android / iOS 原生导入桥保持现有边界；桌面优先复用 Flutter / Dart 能力。
- UI 以 capability、viewport 和输入方式分层，避免共享 Widget 充满平台名称判断。
- Windows WebView fork 只维护解决已知生命周期问题所需的最小差异；升级上游前继续跑现有关闭 / 重启专项验收。
- 自动更新只替换应用程序文件，不直接修改用户数据库、阅读进度、书籍原件或缓存索引。
- Release 元数据、版本比较和更新通道规则必须有纯逻辑测试；平台安装 / 替换另做集成验收。
- Beta 与 Stable 共用同一代码线和资产生成流程，差异集中在 tag、Release 标记和更新选择规则。

## 推荐顺序

```text
Desktop UI / 设计系统
        ↓
书架与应用外壳
        ↓
阅读工作区
        ↓
字体系统
        ↓
Release identity + UpdateService
        ↓
Android 应用内更新
        ↓
Windows updater + 回滚
        ↓
macOS
        ↓
安装器 / 文件关联 / ARM64 / 多窗口
```

1.3.0 完成标准以 UI 与桌面阅读体验形成稳定产品形态为主；后续能力应继续复用现有领域、阅读、存储与发布基础，而不是为 Desktop 建立第二套业务逻辑。
