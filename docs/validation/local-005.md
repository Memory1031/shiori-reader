# LOCAL-005 本地阅读闭环验收

日期：2026-09-08。范围仅 LOCAL-005，不自动启动后续任务。功能实现完成；下方区分离线自动化、模拟器与延期真机矩阵。

## 交付内容

- 生产 `LocalReadingRepository / LocalImageRepository` 在在线缓存和书源之前识别 local 身份，详情、目录、正文、图片全部读取托管副本；没有新依赖、schema 升级或 native 改动。
- 导入与上架在一个用户库事务提交；失败回滚，重复导入去重并重新上架，保留已有进度。成功提供“立即阅读”。
- EPUB 目录保留 nav / NCX 嵌套层级及同章多 fragment，当前章高亮；前后章沿 spine。目录位置通过 blockKey 进入原 BookReaderScreen / ReaderController；翻页、滚动共用原语义定位和 ProgressTracker。
- 首页“更多 → 本地文件”可继续阅读、重新上架和确认删除。删除范围包括托管文件、书架、进度，外部原文件不受影响。删除推进 generation，防止迟到的旧进度写入，包括重导入后；清理目录失败会提示启动重试。
- manifest 解析 / 验证在可取消 worker 中完成；媒体逐张读取只验证发布索引和摘要，不反复解码整本书。本地 Reader 不启动在线缓存预取。

接口与所有权见 [本地导入](../local-import.md) 和 [契约](../contracts.md)。

## 离线自动化

完整 `flutter test --no-pub` **374 PASS**，`flutter analyze --no-pub` 无问题。新增 8 项：

| 范围 | 实際断言 |
| --- | --- |
| TXT / EPUB 真实解析、存储、分流 | 导入即上架；移出书架保留文件和进度；重复导入无重复；删除 disposable 后重开用户库，所有 ReadMode 仍可读取全文；任何调用在线 Repository / ImageRepository 都使测试失败 |
| 发布事务 | SQLite 触发器模拟书架写失败，索引、书架、最终文件目录一并回滚 |
| 删除与并发进度 | 删除清文件 / 书架 / 历史；新图片读取失败，已持有租约可用并幂等关闭；旧写会话无法在重导入后恢复历史；不存在本地书不能上架或创建进度会话 |
| 取消删除 | 已取消请求不影响书籍及书架 |
| Reader 目标 | 指定 fragment 覆盖旧进度，缺失目标从章首开始 |
| 两种阅读模式 | 实际 BookReaderScreen / 目录页选择嵌套 fragment、同章重定位、可见目标文字、保存与重新进入、前后章、缺锚点降级、延迟读取时退出无迟到更新 |

原有跨章失败不覆盖进度、模式切换恢复、媒体解码限额、缓存清理竞态等测试仍包含在完整回归中。新增源码：`test/data/local/local_reading_test.dart`、`test/widgets/reader/local_reading_test.dart`。没有请求真实 Source。

## Android 模拟器

生产入口 Debug ARM64 构建 PASS（12.6 秒），现有 Android 16 / API 36.1 模拟器安装、启动成功。自写样例由 `tool/local_reading_fixtures.dart` 生成并放入 Downloads，使用系统文件选择器接收。

TXT 已通过系统选择、确认导入、自动上架与进度记录（首页约 16%）；EPUB 已验证系统选择、真实解析、自动上架、“立即阅读”、正文、完整嵌套目录与同章 fragment；跳到“片段目标星星”后显示其内嵌 PNG。关闭模拟器 Wi-Fi 和移动数据，移除 Downloads 中原 EPUB，托管正文 / 图片仍可读；强停后读取真实 SQLite，进度为 local / block_index=62 / block_fraction=0。冷启动书架恢复标题、封面及约 95% 继续阅读入口；“本地文件”页面同时列出 TXT 与 EPUB，冷启动后从该页继续 EPUB，断网恢复到同一“片段目标星星”及其内嵌图片。验证后已恢复模拟器 Wi-Fi / 移动数据。删除 / 重上架的事务行为由上述离线自动化覆盖，本轮未补完整模拟器操作矩阵。

UIAutomator 曾超时并返回旧的 100% 导入快照；实际屏幕和已清空的 native 回执确认导入已成功，不是应用卡住。后续改用截图与 SQLite 核对，不以旧快照作为失败或成功证据。

## iOS 与剩余边界

Flutter 3.38.4 / Xcode 26.5 下 Simulator Debug 构建 PASS（11.7 秒），iPhone 17 / iOS 26.5 安装及启动 PASS。共享 Dart 路由、文件路径封装、媒体租约与双模式 Reader 已审查。该结果不等于 iOS Files 系统选择或完整阅读 runtime 验收；真实 Files / 分享后阅读 / iOS 生命周期矩阵继续归 IOS-005。

ARM64 签名真机、大文件峰值内存、系统回收 / 断电、连续强杀、云文档提供者和发布构建均未在本轮验证，归既定设备与 TEST-004 最终回归。桌面 widget 测试不等于这些运行证据。

## 复验与本机证据

```sh
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter test --no-pub
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter analyze --no-pub
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm dart run tool/local_reading_fixtures.dart <样例输出目录>
```

构建沿用 [开发工具链](../development.md)，不升级 SDK。`.tooling/evidence/local005-*.log` 保存全量 / 定向测试、分析和两平台构建日志；同前缀 PNG、样例与只含测试数据的 SQLite 是本机证据，不纳入 Git。
