# PARSE-007：有界 EPUB 诊断

日期：2026-09-09。承接 GAP-006。

## 合同与生命周期

诊断保持在 data 层：`ParsedEpub.diagnostics` 返回不可变 `EpubDiagnostics`，只有固定 `EpubDiagnosticCode` 列表和 truncated 标志。每次解析最多 100 条，超出只设置截断标志；不累计无界计数，不附带文件名、路径、URL、正文、书籍 ID 或原始异常。顺序表示发生顺序，重复原因可能来自不同候选，不等于受影响图片总数。

`BookDecoder(epubDiagnostics: slot)` 可选接收调用方拥有的 `EpubDiagnosticSlot`，worker 成功返回且媒体写入、取消检查完成后替换最近一次报告。slot 不保留书籍身份；需要与单次操作对应时调用方使用独立 slot。`clear()` 显式释放；失败、取消和 TXT 不更新“最近一次成功 EPUB”报告，不能把旧报告当作本次结果。默认解码器不持有 slot，没有隐藏全局服务、自动日志或新 UI。

不修改 LocalBookContent / LocalBookDecoder 的领域合同，不写入 manifest，也不改变正文摘要或 blockKey。派生特殊页重建没有自动发布到 slot。已有导入不会因增加诊断而重解析。

## 原因分类

- missingImage / unsupportedImage：包内图片缺失或字节格式不支持。
- noUsableImage：图片候选都不可用，原生保留占位。
- missingNavigation / unusableNavigation：声明的可选目录缺失或不可用。
- syntheticNavigation：降级生成 spine 目录。
- missingNavigationTarget / missingFragment：条目目标不存在，或锚点不存在并退到章首。
- spineFallback：使用外来 spine 类型的 XHTML 回退。

以上均是成功解析中的容忍/降级信息。归档错误、路径越界、实体声明仍抛原有 invalid；预算错误为 tooLarge；DRM、固定版式仍按既有明确类型拒绝。没有为收集报告增加宽泛 catch，也没有把失败伪装为带 warning 的成功。远程候选、base 不支持以及特殊页资源预算不在本轮逐条诊断范围，已有支持矩阵仍是能力边界。

## 验证

新增六项测试覆盖缺图/缺锚点、坏目录回退、不支持图片、缺目标、大量警告截断、快照不可变以及真实 parser worker 到 BookDecoder slot 的传递；包含越界依旧失败且不发布新报告的断言。仅固定枚举可进入报告，类型上没有自由文本入口。

未运行模拟器、真机、真实书源请求或官方 EPUB 套件。未增加诊断持久化或用户可见面板。

最终相关离线回归 `flutter test test/data/local test/data/sources test/widgets/reader --reporter expanded` **268 项通过**；`flutter analyze` 无问题；`git diff --check` 通过。
