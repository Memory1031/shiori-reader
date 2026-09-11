# TEST-003 Android Profile 探针

仅显式入口，不被生产 main 引用。使用真实 ProductionApp / ReaderScreen / Viewport / SQLite / 图片持久层，合成内容与平台无关；只有存储根目录通过 ProductionApp 的可选参数注入。

运行前连接已授权的 ARM64 Android 手机，并准备可恢复的生产 APK。沿用 `docs/development.md` 的 JDK / Flutter 镜像设置：

```sh
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter build apk --profile --target-platform android-arm64 --no-pub --target integration_test/performance/probe.dart
python3 integration_test/performance/run_android.py \
  --adb "$HOME/Library/Android/sdk/platform-tools/adb" \
  --serial DEVICE_SERIAL \
  --profile build/app/outputs/flutter-apk/app-profile.apk \
  --restore build/app/outputs/flutter-apk/app-release.apk \
  --output .tooling/evidence/test003
```

脚本覆盖安装 Profile 包；仅创建/删除应用 support 目录下专用 `test003` 目录，不卸载、不 clear-data、不更改手机刷新率或生产书架。finally 恢复指定 APK 并启动。不要把探针 APK 当生产包使用。

阶段：

1. 预置 500 本无封面的合成书架，关闭数据库。此阶段不计入冷启动。
2. 3 次 force-stop 后启动正式组合根，轮询真实 BookshelfView 的 shelfReady 与 500 项，在完成布局的帧末记录就绪时间。主机另记从启动命令到观测到就绪的保守上界（包含 adb 与轮询开销）。不等同系统重启后的存储冷缓存。
3. 真实正文 Scrollable 的 drag 接口，通过 AnimationController 在 10 秒内匀速移动 6000 logical px，共 3 次。记录 FrameTiming 原始时间、p95、懒构建计数、位置前进、真实成功进度写入次数与生命周期额外写入；不足 300 帧、正文未前进或没有进度写入会失败，避免静止页面误测。
4. 2000 块中的第 1500 块深恢复；十万字单段的 75% 横向/纵向位置映射与懒测量。
5. 20 张内容不同的合成 PNG（19 张 1200×1800、一张 1200×6000），10 个独立章节会话，每章逐图等待目标 SourceImage 下的 RawImage 解码。使用持久图片层和正式解码缓存；同一组图片重复阅读，各章 MediaRef 独立，文件按内容去重符合生产行为。每章卸载后请求 VM GC，记录 Dart heap、external、RSS、100ms 周期峰值、网络内存保留与 body 数量。未填满磁盘或访问真实 Source。

`--suite-only` 只复跑阅读部分，`--images-only` 只复跑图片部分，`--scroll-only` 只复跑正文滚动与深恢复。计时器、VM service 请求、合成数据和报告只存在探针中。Trace 为 VM `getVMTimeline` 的 Dart/GC 流；逐帧 UI/raster 数据另存 `report.json` 中的 `timingsUs`（vsync 时间、UI、raster，单位微秒）。Trace 缓冲区有界，不保证保存整个运行的全部历史；GC 与图片生成位于滚动计时窗口之外。

脚本保留 `cold.json`、`report.json`、`timeline.json`、`meminfo.txt`；超时也尽量复制部分报告并恢复应用。测量结果仅适用于当次设备与场景，不代表其他平台表现。
