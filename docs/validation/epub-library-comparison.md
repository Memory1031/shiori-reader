# EPUB 第三方解析库对比

2026-09-08，Windows 宿主机，Dart 3.10.3 AOT。结论：**Dart 有可用第三方库，并非必须从零实现；目前没有证据支持立即替换 Shiori 解析器。** `epub_parser` 值得作为容器解析层的参考和对照实现，现有阅读模型、资源处理和安全约束仍需保留。

## 实测范围

用户原清单 35 个路径，本轮可读取 31 个。三本《和你恋爱什么，应该是不可能的》及 `1.epub` 已不在原路径，记为无法复测，不是解析失败。此前 35 个文件的历史核查不能与本轮分母混用。

| 实现 | 版本 | 解析返回成功 | 失败 / 拒绝 |
| --- | --- | ---: | ---: |
| Shiori 当前解析器 | develop 工作树 | 30/31 | 1 |
| epubx | 4.0.0 | 20/31 | 11 |
| epub_parser | 3.0.1 | 30/31 | 1 |

每个文件独立进程、离线读取、无重试。源码未打补丁，生产依赖未更换。逐文件结果见 [JSON 摘要](epub-library-comparison.json)，[复跑工具](../../tool/epub_compare/README.md)保留隔离构建方法。

## 差异与解释

### epubx 的 10 次额外失败与 Windows 路径有关

错误为 `Text\cover.xhtml` / `Text\p-cover.xhtml` 不在 manifest 中。包源码 `navigation_reader.dart` 使用宿主机 `path.normalize` 处理 EPUB 内部路径；Windows 会产生反斜杠，而归档资源键使用正斜杠。源码与错误吻合，属于明确的移植风险。

**未在 Android / iOS 复跑，也未运行修补版本，不能把 20/31 宣称为移动端成功率。** 若采用该库，应先把归档路径处理改为 POSIX / URI 语义，再复测。

### epub_parser 的 WebP 需要额外分类，资源本身没有丢失

30 个成功样本中，113 个图片资源未进入 `Content.Images`，但在 `Content.AllFiles` 中仍存在。源码 MIME 分类没有 `image/webp` 分支，默认归入 OTHER；完整读取会将其保留在 AllFiles。

最终对比包含 AllFiles：两个第三方库各自成功样本的 XHTML 与图片资源均无缺失，字节哈希无差异（HTML 仅规范化 UTF-8 BOM），spine 顺序一致，导航目标文档均存在。**只接 Images 会漏图；这不是解包丢失。** 未验证 fragment 锚点、实际跳转、图片解码或页面展示。

### 三者均未成功的样本，原因不同

《义妹生活》11：Shiori 因加密声明按现有策略拒绝；两个第三方库因百分号编码的 TOC 路径查找失败。不能将两者称为 DRM 检测成功，也不能仅凭声明认定整本正文被加密。

## 接入成本

| 项目 | epubx 4.0.0 | epub_parser 3.0.1 |
| --- | --- | --- |
| 本次 Dart 3.10.3 隔离解析、编译 | 成功 | 成功 |
| archive 依赖 | ^3.1.6 | ^3.1.6 |
| xml 依赖 | ^6.0.1 | ^5.3.1 |
| 与本项目 archive 4.2.0 / xml 6.6.1 | archive 约束冲突 | archive、xml 约束冲突 |
| 已发现适配点 | Windows 目录路径 | WebP 分类 |

`epub_parser` 发布元数据虽然声明 SDK `<3.0.0`，但本次 Pub 实际解析成功，且 AOT 编译、执行成功；**不能仅凭该声明判断 Dart 3 不可用**。上述依赖冲突来自版本约束比较，未在生产 pubspec 中试装，也未验证强制 dependency_overrides；不建议通过强制覆盖掩盖 API 兼容问题。

两者主要提供元数据、manifest、spine、目录、XHTML/CSS 与资源，并非完整浏览器渲染引擎。接入后仍要完成 Shiori 的正文块转换、卷内锚点、分页/进度映射、SVG 图片引用、图片缓存与预取、导入限额和错误分类。返回原始 CSS 不等于完整 CSS 排版支持；本轮也没有验证固定版式、纯 SVG 绘图或 DRM 解密。

Shiori worker 构建阅读内容模型，第三方 worker 读取 EPUB 容器并解码封面，工作量不同。因此不将单次耗时、峰值内存做成性能排名，亦不以“解析成功”替代阅读器验收。

## 建议

1. 当前版本保留现有解析器，本轮没有发现第三方能额外打开的样本；不为替换而回退 archive/xml。
2. 将 epub_parser 当作结构解析对照，参考 OPF/NCX/nav 的处理，但对其 WebP 和路径行为增加我们自己的适配。若后续维护成本明显增大，再独立评估维护 fork / 容器解析层替换。
3. 如果目标是完整 CSS、固定版式等高保真排版，应评估渲染引擎层；Readium、foliate-js 属于另一个层次，不能把换一个 Dart 解包库当作解决方案。本轮未对它们运行测试。

参考：[epubx](https://pub.dev/packages/epubx)、[epub_parser](https://pub.dev/packages/epub_parser)、[Readium Mobile](https://github.com/readium/mobile)、[foliate-js](https://github.com/johnfactotum/foliate-js)。版本和实现行为以本次下载的发布包为准。
