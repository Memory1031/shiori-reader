# TEST-001 Android 生产链路 Smoke

这是独立 APK 入口，默认 `TEST001_LIVE=false` 时只显示禁用状态，不触发网络。默认 `flutter test` 仍只执行 test/ 中的离线测试。

运行前必须取得本次真实源访问授权。构建命令：`flutter build apk --debug --no-pub --target integration_test/live/source_smoke.dart --dart-define=TEST001_LIVE=true`。安装并启动后自动执行一次，最多12次串行HTTP，至少间隔1秒，不自动重试；失败打印当前阶段与封闭原因码后停止。不要因失败直接重复安装/启动以重试。

固定测试身份：搜索“玩乐关系”→书31607→卷44117/章309555→首图。使用生产 SourceServices / Repository / Source / ImageRepository；SQLite 仅内存，正文和图片不写磁盘。仅运行锁写入 App 临时目录，防止意外进程重启重复请求；本次锁为 test001-live-20260907.started。未来重新验收应明确新的授权与运行标识，不自动删除旧锁绕过预算。

报告只输出阶段、计数、尺寸和封闭失败码，无原文、签名或请求Header。结束后先保存报告，再安装普通 lib/main_dev.dart 开发包；不要将此 live APK 作为日常或发布包。

2026-09-07 结果见 docs/validation/test001-android.json；10/12次请求，所有阶段PASS。未来源站变动或生产代码变更需要新的有界验收，不沿用历史结果作为当下可用性承诺。
# READER-007 后续探针

`reader_smoke.dart` 为独立 Android 入口，默认不开网络；显式 `READER007_LIVE=true` 才运行。2026-09-07 两次授权已分别执行10/12与10/10次，首轮数据/解码成功但探针释放租约过早，第二轮保留租约后正式阅读器图文挂载通过。当前代码为第二轮修正版，使用独立v2一次性标记；不得删除标记、重跑或把未使用额度当后续授权。

只读既定样本，串行至少1秒间隔，无重试，失败即停。内容与图片只在内存数据库/媒体租约中保留；仅首图用于页面挂载，其他图在探针层本地占位，挂载阶段禁止网络。生产代码没有该限制。验收见 `docs/reading-flow.md` 与 `docs/validation/reading-flow.json`。
