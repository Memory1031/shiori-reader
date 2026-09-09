# EPUB 解析库对比

生产依赖保持不变。工具把 epubx 4.0.0、epub_parser 3.0.1 和实际 Shiori 解析器分别编译为独立 AOT 进程，输出元数据、计数和哈希，不输出正文或图片。实验目录 `.tooling/epub-compare` 不入库；需要 Dart 3.10.3 和 Python 3。

```text
python tool/epub_compare/prepare.py --dart <Dart可执行文件绝对路径>
python tool/epub_compare/run.py --samples <路径清单.json> --bin .tooling/epub-compare --output .tooling/epub-comparison.json
```

路径清单是用户明确提供的 EPUB 绝对路径 JSON 数组。工具不遍历其他目录，缺失原件单独记录。准备阶段访问 Pub 下载依赖；解析阶段离线。保留实验目录的 pubspec.lock 可固定传递依赖，勿把本机路径或电子书提交到仓库。

每个文件、每个实现均启动独立进程，超时 60 秒，不重试。HTML 对比仅移除 UTF-8 BOM 后计算哈希；图片按原始字节计算。图片包括 AllFiles 中未归类进 Images 的资源。导航只检查目标文档是否存在，不验证 fragment、点击跳转或设备呈现。Shiori 的输出为阅读模型，第三方输出为 EPUB 容器模型，不能直接用耗时判定渲染性能优劣。

结果与解释见 [比较报告](../../docs/references/epub.md)。原件读取失败或不合法 ZIP 属于输入/参考提取问题；这不是用于不可信输入的安全沙箱。
