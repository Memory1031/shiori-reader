# 文档导航

文档描述当前实现，不保留逐轮开发日记。历史执行过程通过 Git 历史查询；已完成任务不再逐项重复列出。

| 需要了解 | 文档 |
| --- | --- |
| 产品功能与使用 | [项目 README](../README.md) |
| 当前范围及剩余事项 | [任务计划](TASK_PLAN.md) |
| 环境、命令、开发场景 | [开发说明](development.md) |
| 页面、路由、依赖装配、多语言 | [应用结构](app.md) |
| 阅读与翻页规则 | [阅读器](reader.md)、[视口决策](decisions/reader-viewport.md) |
| TXT / EPUB、系统导入与文件管理 | [本地导入](local-import.md) |
| 领域模型与跨层接口 | [领域模型](domain.md)、[契约](contracts.md) |
| 存储与迁移 | [数据库](database.md) |
| 离线、图片与预取 | [缓存](cache.md) |
| 请求预算与在线适配 | [网络](network.md)、[书源维护](source/lightnovel.md) |
| CI 与发布 | [CI](ci.md)、[发布说明](release/README.md)、[依赖许可快照](release/dependencies.md) |
| 已验证内容与边界 | [验收摘要](validation/README.md) |

探针和测试样本的操作说明留在其目录：[Source 调查工具](../tools/source_probe/README.md)、[Source 样本](../test/fixtures/lightnovel/README.md)、[MVP 探针](../integration_test/README-mvp.md)、[性能探针](../integration_test/performance/README.md)、[显式在线验收](../integration_test/live/README.md)。

维护时同步修改对应主题文档；只有未完成且仍在范围内的事项进入任务计划。测试结果要注明平台与证据类型，不能用旧构建、旧截图或单元测试代表当前版本的真机验收。
