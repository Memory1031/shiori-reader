# TEST-004 离线 MVP 真机回归

`mvp_test.dart` 是显式 Profile 入口。组合真实 LightNovelSource、Repository、Drift 双库、持久图片层、ReadingHome 与 Reader；HTTP adapter 只返回自制 JSON / HTML / PNG，绝不委托 socket adapter。生产 main 不引用此入口。

沿用 `docs/development.md` 的本机 JDK / SDK 设置：

```sh
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter build apk --profile --target-platform android-arm64 --no-pub --target integration_test/mvp_test.dart
python3 integration_test/run_mvp_android.py \
  --adb "$HOME/Library/Android/sdk/platform-tools/adb" \
  --serial DEVICE_SERIAL \
  --profile build/app/outputs/flutter-apk/app-profile.apk \
  --restore build/app/outputs/flutter-apk/app-release.apk \
  --output .tooling/evidence/test004
```

仅在已授权设备上运行。脚本使用真实 Android UIAutomator 层级与 input 点击/输入/滚动：首页 → 搜索 → 详情 → 收藏 → 阅读图文 → 滚动 → 确认 SQLite 提交 → force-stop → 离线重启 → 继续阅读 → 返回章首读图。offline 标记让任何 HTTP adapter 调用都失败并计数，冷启动阶段要求计数为 0；不依赖手机实际断网。

正文/封面通过可见 SourceImage 下的 RawImage 识别，不把 Logo 或后方 offstage 路由的图片当正文图片。状态报告记录原始 revision / blockKey / index / fraction，冷重启前后的持久位置要求一致；同布局继续阅读要求相同 blockKey、fraction 误差 <.02。截图供人工复核，报告不以“截图有字”代替持久化断言。

所有数据在应用 support 下专用 `test004` 目录；不使用生产库、系统偏好或用户文档。脚本 finally 复制报告、关闭应用、删除自身目录与 UI dump，再覆盖恢复指定生产 APK 并启动；不卸载、不 clear-data、不修改全局网络设置。若脚本所在主机进程被强杀，finally 无法保证运行，需手动恢复提供的 APK。

四阶段 parser 演练：

```sh
PUB_HOSTED_URL=https://pub.flutter-io.cn fvm flutter test --no-pub test/data/sources/lightnovel/repair_drill_test.dart --reporter expanded
```

共享合成协议位于 `support/mvp_fixture.dart`。测试分别移除 Search/Detail 必填 title、将 Catalog list 改名、将 Chapter body_snapshot 改名，检查 Failure.operation / kind、单次请求、缓存/用户库保留，再恢复黄金协议重放并验证 cacheOnly 零请求。测试没有加入未经实站验证的新字段兼容逻辑。
