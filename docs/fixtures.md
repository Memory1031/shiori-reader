# DEV-001：离线 Fixture Source 与可控媒体

2026-09-07。DEV-001 DONE。代码、宿主契约/解码测试和 Android 编译已完成；DEV-002 执行时连接 MuMu 后补齐 20 图设备解码 PASS，iOS runtime 为 DEFERRED_NO_MAC。菜单和快捷入口现见 [DEV-002](dev-entry.md)。

## 入口和所有权

`lib/dev/fixtures.dart` 导出 `FixtureEnvironment`，按构造器选择场景和 seed，装配正式接口的 FixtureNovelSource / SourceMedia、FixtureNovelRepository、FixtureImageRepository、FixtureLibraryRepository、FixtureSettingsStore。调用方通过构造器注入消费者，退出时取消自己的请求和订阅、关闭 media lease，最后 `await environment.close()`。没有全局注册、Get.find、真实站点访问或生产入口改动。

```dart
final environment = FixtureEnvironment(
  scenario: FixtureScenario.revisedContent,
  seed: 20260907,
);
final cancellation = CancellationSource();
final key = fixtureChapterKey(FixtureScenario.revisedContent);
final result = await environment.novels.loadChapter(
  key,
  mode: ReadMode.cacheFirst,
  cancellation: cancellation.token,
);
// 消费正式 Result / LoadResult / ChapterContent。
cancellation.cancel();
await environment.close();
```

同一环境可发现、搜索和读取全部小说；构造参数 scenario 选择该次运行的搜索/媒体故障配置。场景枚举名是稳定开发 ID，`labelZh` / `labelEn` 供后续开发菜单按语言选择。合成标题和正文作为内容数据含中英日文，不是生产 UI 翻译；DEV-002 的菜单操作文案仍遵循 gen-l10n 规范。

## 场景目录

| 场景 ID | 形状或触发方式 |
| --- | --- |
| shortChapter | 8 段短章，正常目录和封面 |
| longChapter | 精确 2,000 段，每段 50 个汉字，共 100,000 字 |
| extremeParagraph | 一个 100,000 字语义 Paragraph，不做渲染切片 |
| twentyImages | 20 张不同尺寸 PNG；按需生成、按需解码 |
| singleImage | 纯单图章，没有为凑正文插入文字段 |
| slowImage | 每个媒体块默认延迟 200ms，可通过 controls 改为零或其他时长 |
| failingImage | 第一次媒体流先交付字节，再以 network/manual 终止；再次 load 成功 |
| unknownImageSize | 正文 ImageBlock 和媒体 MediaInfo 均不预告尺寸，实际 PNG 可解码 |
| longTitle | 重复的中英文长标题，供换行/布局验收 |
| typography | 空段、段内换行、日文、全角缩进、标点、emoji、居中、emphasis 纯文字和 Ruby 括注降级 |
| multiVolume | 三卷、九章，第三卷为番外，ordinal 全目录连续 |
| noVolume | 一个明确 isSynthetic 的无名分组 |
| missingVolumeName | 真实分组形状但 title=null，与无卷不同 |
| emptySearch | 无论查询均为空且 nextCursor=null |
| repeatedCursor | 首次正常分页，回传游标时模拟检测到重放，返回 parse/repeatedPage 并终止 |
| deletedChapter | 第一章从目录删除，直接请求稳定旧 Key 返回 notFound |
| revisedContent | 初始 revision=0；将 controls.revision 改为 1 后刷新，Key 不变、正文 revision 变化 |

数据仅在读取时生成，注册和普通搜索不会创建压力章。sourceId 固定 `dev-fixture`，novelId 为场景名，chapterId 为 `chapter-N`，mediaId 为 `checker-N`；它们不是 URL。默认 seed=20260907，文本按固定字表和整数索引生成，不使用 Random、当前时间或平台 hashCode。生成 PNG 使用自制 RGB 棋盘、PNG CRC/Adler 校验和无压缩 DEFLATE，无额外依赖；固定种子、尺寸产生相同字节。

所有文本和图片均为本项目自制测试数据，可随项目提交，没有复制网站整章、插图或 Cookie。图片不加入主 pubspec assets；Parser fixtures 和阅读 fixtures 保持分开。

## 故障与缓存控制

`environment.source.controls` 支持按 Operation 的 `delays`、`failNext(AppFailure(...))`，以及 `mediaChunkDelay`、`mediaStreamFailures`、`chapterDeleted`、`revision`。`calls` 统计进入 Source 的操作，预取消不计数。Library 和 Settings 也有各自 controls，可模拟本地读写失败。延迟支持 token 取消，媒体还有单独 body 关闭信号，不以 sleep 阻塞 UI。

- 正常搜索每页最多 4 本；Source 绑定正规化查询并验证不透明游标，跨源/跨查询/越界游标返回 invalidCursor。重复游标场景模拟正式 Source 应交付的诊断，不把非法循环页传给业务 Widget。
- NovelRepository 的 detail/catalog/chapter 都有独立内存缓存和按 Key 广播流；订阅无初始事件、无 IO。cacheOnly miss 返回 cache/cacheMiss。`markStale()` 显式标记陈旧；cacheFirst 返回旧快照并安排按 Key 去重刷新；refresh 失败保留旧 fetchedAt 和 refreshFailure。一个调用者取消不影响其他消费者，仓库生命周期拥有刷新任务，close 后不发布晚结果。
- ImageRepository 消费完整受限字节流，返回独立可关闭的 memoryOnly lease。cacheOnly 不触碰 Source；失败字节不进缓存，成功 PNG 可重新获取。已有缓存的刷新失败返回 stale + refreshFailure，并保留陈旧状态；cacheFirst 可安排后台更新，后续 load 观察新值，不通过广播分享 lease。
- SourceMediaBody 单消费者、累计 maxBytes 上限、不可变成功块、一次终止失败；读取完毕、取消和重复 close 均释放资源。消费者收到 body 后仍须 finally close；activeBodies 可用于测试确认归零。
- Library 提供不可变初始/后续快照、幂等书架写入、删除书架保留历史、generation/sequence 拒绝晚进度、clearHistory 失效旧代次。Settings 只保存已验证 ReaderSettings，模拟失败不覆盖原值。

这些是开发用内存替身。LoadOrigin.remote 表示从 Fixture Source 新取值，不代表真实网络；固定 UTC epoch 加内部计数供可重复测试。没有持久化、重启离线保证、生产 TTL/LRU、网络调度或跨进程事务，不代替 CORE-005、DB、NET、MEDIA/CACHE 任务。

## 验证与复验

- 完整 Flutter 测试 65 项通过（既有 50 + 本轮 14 项契约测试 + 1 项 codec 测试），全项目静态分析无问题。
- 契约覆盖场景遍历、稳定 seed、压力规模、分页绑定和终止、删除/revision、故障切换、缓存/广播/去重、取消、媒体限额/失败重试/释放、书架进度及设置。HttpOverrides 拒绝意外 HTTP；同时白名单检查 dev imports，禁止 IO/网络库，避免其他 transport 绕过 HTTP 检查。生产源码无 dev fixture 导入。
- 宿主 Flutter 引擎实际解码 20 张 PNG，校验尺寸、RGBA 字节数及像素；codec、ui.Image 和 lease 均释放。这不是 Reader 性能测量。
- Android codec 探针和默认应用 Debug 编译通过。探针仅位于 test/support，不建立 DEV-002 的场景菜单。探针构建产物另存 `build/app/outputs/flutter-apk/fixture-codec-debug.apk`，默认 app-debug.apk 仍为普通入口。
- 本轮 adb 设备列表为空，未取得 Android 设备 codec PASS，也未重复先前的安装失败。PNG 跨端支持可由固定 Flutter SDK 的 painting.dart instantiateImageCodec 文档核对；iOS 无插件/平台分支/最低 OS 变化，Level A compatibility review PASS，实际 iOS 解码 DEFERRED_NO_MAC。

```powershell
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
flutter test --no-pub test/domain/fixture_contract_test.dart test/widgets/dev/fixture_codec_test.dart --reporter expanded
flutter analyze --no-pub
flutter test --no-pub --reporter expanded

# 连接 Android 后补验；通过标志是该次新启动日志的 FIXTURE_CODEC_PASS count=20。
. ./tool/android-env.ps1
flutter run --no-pub --debug -d <device-id> --target test/support/fixture_android_decode.dart
```

后续补验（2026-09-07，DEV-002）：连接已配置的 MuMu 127.0.0.1:16384，安装本探针后新进程日志输出 `FIXTURE_CODEC_PASS count=20`。已补齐 Android codec 验收，前述无设备记录保留为当时事实。开发菜单与快捷路径已在 [DEV-002](dev-entry.md) 交付。
