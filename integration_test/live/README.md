# TEST-001 Android 生产链路 Smoke

这是独立 APK 入口，默认 `TEST001_LIVE=false` 时只显示禁用状态，不触发网络。默认 `flutter test` 仍只执行 test/ 中的离线测试。

运行前必须取得本次真实源访问授权。构建命令：`flutter build apk --debug --no-pub --target integration_test/live/source_smoke.dart --dart-define=TEST001_LIVE=true`。安装并启动后自动执行一次，最多12次串行HTTP，至少间隔1秒，不自动重试；失败打印当前阶段与封闭原因码后停止。不要因失败直接重复安装/启动以重试。

固定测试身份：搜索“玩乐关系”→书31607→卷44117/章309555→首图。使用生产 SourceServices / Repository / Source / ImageRepository；SQLite 仅内存，正文和图片不写磁盘。仅运行锁写入 App 临时目录，防止意外进程重启重复请求；本次锁为 test001-live-20260907.started。未来重新验收应明确新的授权与运行标识，不自动删除旧锁绕过预算。

报告只输出阶段、计数、尺寸和封闭失败码，无原文、签名或请求Header。结束后先保存报告，再安装普通 lib/main_dev.dart 开发包；不要将此 live APK 作为日常或发布包。

2026-09-07 结果见 docs/validation/test001-android.json；10/12次请求，所有阶段PASS。未来源站变动或生产代码变更需要新的有界验收，不沿用历史结果作为当下可用性承诺。
