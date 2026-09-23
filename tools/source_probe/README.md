# Source 调查工具

独立纯 Dart 包，只服务可重复的调查证据，不是生产 Source / Parser。依赖本仓库的 `test/fixtures/lightnovel/`，不依赖主 Flutter 包，也不修改 App 依赖。

## 复跑（Windows PowerShell）

使用项目 Flutter 3.38.10 所带 Dart 3.10.9。在仓库根目录执行：

```powershell
Set-Location tools/source_probe
dart pub get --enforce-lockfile
dart --suppress-analytics analyze
dart --suppress-analytics test
# 默认离线；安装依赖后直接运行脚本，避免 dart run 的隐式依赖解析。
dart bin/source_probe.dart
# 可选保存报告；目标文件必须不存在。
dart bin/source_probe.dart --report reports/my-offline.json
```

依赖安装需要网络；调查程序默认不创建 HttpClient，离线检查也不请求源站。`dart test` 全部使用本地 fixture / 内存传输，无 live 测试钩子。

`--suppress-analytics` 只抑制当次 CLI 的分析发送，不改用户全局配置。

只有明确需要重新验证源站时运行一次：

```powershell
dart bin/source_probe.dart --live --max-requests 30 --report reports/my-live.json
```

请选新的报告文件名。已存在的文件在访问网络前即拒绝覆盖。退出码：`0` 全部指定阶段通过，`1` 调查阶段失败（后续阶段 SKIPPED），`2` 参数或本地输出失败。成功和失败均输出 JSON；不输出原始异常、堆栈或响应正文。网络或访问失败后先查看报告，不循环重跑。

## 固定链路和停止条件

查询 **玩乐关系**，匹配 book_id `31607` + 标题 `桌游咖（玩乐关系/玩玩的戀愛關係）` + 作者 `葵关南`，详情再次断言身份及默认卷 `44117` / 章 `309555`；验证卷、所选卷章节的有序目录与归属，读取 `body_snapshot`，获取正文第一张图片并解码。不随意更换小说，不采集其他卷正文，不把 `render_preview` 单独当全文。

- 先执行 5 个离线预检阶段，再执行 search / detail / volumes / chapters / chapter_text / illustration_decode。预检失败时 live 也是零 HTTP。
- 单流串行，后续尝试至少等待 1 秒。每次真正调用传输前消耗一次预算，网络失败和重定向也计数；`--max-requests` 只能是 1–30，没有重试。预算耗尽即停止。
- API 只允许已验证的五个 HTTPS POST 路径；API 重定向直接停止。图片仅允许 `api.lightnovel.fun` 的已知图片路径形状，最多 3 次同站 HTTPS 重定向，每跳重新校验、计入总预算。没有 live 重定向样本，行为由合成测试验证。
- HTTP 非 200、非零业务 code、HTML challenge、身份缺失/变化/重复、locked 或正文缺失均停止。不读取拒绝响应正文，不导入 Cookie / Authorization，不接入 WebView，不尝试解锁或其他端点。
- 连接超时 15 秒，每次请求总超时 30 秒；每个响应最多 16 MiB（同时检查 Content-Length 和流式累计字节）。图像必须 MIME 与识别格式一致、单帧、正尺寸且不超过 2,000 万像素；先查尺寸，再解码。
- 此工具针对 SRC-002 单页目录样本；页数变多时报告 `catalog_shape_changed`，要求重新调查，不自动扩大采集。长期稳定性、签名寿命和生产分页逻辑不在此包中实现。

## 证据与脱敏

离线预检校验 15 个 manifest SHA-256、目标身份、搜索 0 → 1 页映射、无结果页、四卷十章的顺序与归属、自制 HTML 和 2×2 PNG 解码。真实记录是删减投影、人工转录或结构统计；合成 HTML / 图片和内存 HTTP 链路明确不是真实 API 捕获，不据此声称已覆盖线上错误 schema。

报告只写固定身份、阶段状态、尝试数、字节数、文本/标签统计、图片 SHA-256 / MIME / 解码尺寸及常量错误码。正文、原始 HTML、图片字节、完整请求/响应和签名查询值都不写磁盘；图片当前 URL 的查询值在内存中原样传给 GET，报告仅记录是否有 query 及已知字段名 m/t。传输和解码异常不直接序列化。测试用秘密哨兵证明失败正文、原始异常、正文与 query 不进入报告。

失败报告结构示例（**合成摘录**，不是站点失败记录）：

```json
{
  "status": "FAIL",
  "httpAttempts": 2,
  "stages": [
    {"stage": "volumes", "status": "FAIL", "httpAttempts": 0, "failureCode": "budget_exhausted", "rawErrorRetained": false},
    {"stage": "chapters", "status": "SKIPPED"},
    {"stage": "chapter_text", "status": "SKIPPED"},
    {"stage": "illustration_decode", "status": "SKIPPED"}
  ]
}
```

历史运行报告查 Git。纯 Dart 解码不等于 Flutter 平台显示验证；每次在线调查均须取得新的明确授权。

## 依赖范围

锁文件固定本次解析结果：`html 0.15.7`（DOM 结构统计）、`image 4.9.2`（本工具仅启用 PNG/JPEG 解码）、`crypto 3.0.7`（样本/图片哈希）、`test 1.31.1` / `lints 6.1.0`（开发检查）。版本以 pubspec.lock 为准，沿用宿主的 pub.flutter-io.cn 镜像配置。

尺寸边界测试发现 `image 4.9.2` 的 JPEG `startDecode/readInfo` 已分配系数缓冲，不能在它返回后才检查上限。工具现在先检查 JPEG 帧头 / PNG IHDR，再调用库解码；超大 JPEG 合成测试覆盖这一停止点。多帧和未验证的格式/特殊 JPEG 采样布局直接停止，不扩展格式支持。

图像解码是本次唯一媒体调查依赖；留在本包，不选择主 App 的渲染/缓存实现。官方 API 依据：[image decodeImage / decoder 文档](https://pub.dev/documentation/image/4.9.2/image/Decoder-class.html)、[html](https://pub.dev/packages/html/versions/0.15.7)、[Dart test](https://pub.dev/packages/test/versions/1.31.1)。依赖许可证保留在各包分发内；本包没有复制 Aidoku / 源站代码，内容与 fixture 许可边界见项目发布说明。
