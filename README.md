<div align="center">
  <img src="assets/branding/shiori-chibi-logo-v1.png" alt="Shiori Logo" width="112" />
  <h1>Shiori</h1>
  <p>把喜欢的故事，留在手边。</p>
  <p>面向 Android 与 iOS 的开源轻小说阅读器 · Flutter · TXT / EPUB · 在线书源 · 中文 / English</p>
  <p>
    <a href="#功能亮点">功能</a> ·
    <a href="#安装">安装</a> ·
    <a href="#快速开始">使用</a> ·
    <a href="docs/development.md">开发文档</a>
  </p>
</div>

---

Shiori 以书架和阅读为中心，支持在线搜索与阅读，也可以导入本地 TXT 和 EPUB。收藏、阅读进度与排版偏好由应用保存，让你随时接着读下去。

> 平台支持范围不代表所有系统版本均已完成实测。

## 功能亮点

- **随时续读** — 网格 / 列表书架，保存阅读位置，点击书籍继续阅读。
- **在线阅读** — 接入 [LightNovel.fun](https://www.lightnovel.fun/) 书源：搜索书籍、查看详情与分卷目录，支持图文正文及已缓存内容离线阅读。
- **本地书库** — 导入 TXT、无 DRM 的流式 EPUB 2/3，支持系统打开 / 分享、重复文件识别和卷内目录跳转。
- **重新解析** — 从应用内原件更新旧书解析结果，尽量保留阅读位置，近似恢复会提示。
- **书内链接** — EPUB 可通过阅读菜单打开脚注与辅助文档，再返回原页。
- **舒适翻页** — 点按或拖动左右翻页，连续切换章节，调整排版后恢复阅读位置。
- **个性排版** — 调整字号、行距、段距、页边距与纸张主题，支持插图和部分 EPUB 特殊页面。
- **外观与语言** — 浅色、深色、跟随系统，多种强调色，中文与英文界面。
- **缓存管理** — 图片缓存、有限预取，以及按书或统一清理缓存。

## 安装

| 平台 | 安装方式 |
| --- | --- |
| Android 7.0+（API 24） | 在 [Releases](https://github.com/Memory1031/shiori-reader/releases) 查看可用的签名 APK。若尚无附件，可按开发说明本地构建。 |
| iOS 15.0+ | 当前通过 macOS / Xcode 使用自己的开发者签名安装，配置见[开发说明](docs/development.md)。 |

Android 覆盖安装需要签名一致；从 Debug 包切换到正式签名包前，请先保全数据。版本、签名与分发方式见[发布说明](docs/release/README.md)。

## 快速开始

1. **添加书籍**：点击首页搜索查找在线书籍，或通过「更多 → 导入」选择 TXT / EPUB；从其他应用打开或分享文件后，在 Shiori 内确认导入。
2. **开始阅读**：点击书架上的书籍继续阅读；网格模式长按、列表模式左滑，可查看详情或移除。
3. **调整阅读体验**：点击正文中部唤起工具栏，通过目录跳转、调整进度或修改排版；点按两侧或左右拖动翻页。

导入文件会保存为应用内副本。移除本地书籍会删除该副本、解析资源和阅读进度，外部原文件不受影响；移除在线书籍会清理对应缓存并保留阅读进度。

### 升级旧书

旧导入记录不会随应用升级自动重建。若 EPUB 特殊排版异常，或需要应用新的兼容规则，请进入「更多 → 本地文件 → 书籍菜单 → 重新解析」，完成后重新打开；无需删除重导。

### 支持范围

目前不支持 DRM、PDF、完整固定版式 EPUB、云同步或整本在线下载。EPUB 以普通流式图文为主，并非完整浏览器级排版实现，具体范围见[本地导入](docs/local-import.md)。

在线功能目前接入 [LightNovel.fun](https://www.lightnovel.fun/)，其服务可用性可能变化。应用不附带小说内容，也不提供发现或推荐流。

## 本地开发

使用固定的 **Flutter 3.38.4 / Dart 3.10.3**。Android 构建需要 JDK 17、SDK 36 和 NDK 28.2.13676358；iOS 构建需要 macOS / Xcode。

以下命令适用于已安装 FVM 的 macOS / Linux 环境：

```sh
fvm install 3.38.4
export PUB_HOSTED_URL=https://pub.flutter-io.cn
fvm flutter pub get --enforce-lockfile
fvm flutter devices
fvm flutter run --target lib/main.dart
```

Windows 环境配置、工具包依赖、离线测试及构建命令见[开发说明](docs/development.md)。版本约束以 [.fvmrc](.fvmrc) 和 [pubspec.yaml](pubspec.yaml) 为准。

## 项目文档

| 文档 | 内容 |
| --- | --- |
| [文档导航](docs/README.md) | 架构、模块与维护文档入口 |
| [阅读器](docs/reader.md) / [本地导入](docs/local-import.md) | 阅读行为、格式兼容与使用限制 |
| [开发说明](docs/development.md) | 环境准备、运行、测试与排障 |
| [持续集成](docs/ci.md) / [发布说明](docs/release/README.md) | 质量检查、签名和版本发布 |

## 问题反馈

可通过 [Issues](https://github.com/Memory1031/shiori-reader/issues) 反馈问题。请注明应用版本、设备与系统版本、复现步骤、预期和实际表现，必要时附截图。

EPUB 兼容性问题请尽量提供最小可复现样本或结构说明；不要上传签名密钥、密码、个人数据或无权分享的完整书籍。

## 隐私与许可

书架、进度、偏好和导入文件由应用在本地保存；在线查询与图片请求会发送到相应第三方服务。系统备份或换机迁移可能包含用户数据，详见[隐私与分发说明](docs/release/dependencies.md#许可与隐私边界)。

Shiori 是非官方第三方客户端，与 LightNovel.fun 及其运营方无关联，也未获得其官方认可。Shiori 不附带小说内容，也不提供绕过认证、访问控制、付费机制或 DRM 的功能。在线内容由相应第三方服务提供，相关内容与商标权利归各自权利人所有；第三方 API 或页面变化可能使在线功能暂时不可用。

本项目源码与自有品牌素材以 [MIT License](LICENSE) 授权。该许可不授予第三方小说内容、第三方商标、LightNovel.fun 的名称 / 服务 / 内容及其他第三方资产的任何权利；依赖许可清单见[发布文档](docs/release/dependencies.md)。
