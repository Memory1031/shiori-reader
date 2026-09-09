# TXT 宿主基准

在项目根目录使用固定 Dart SDK；不安装第三方检测器，不访问网络。

```sh
.fvm/flutter_sdk/bin/dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/txt_benchmark/main.dart 1 lines
.fvm/flutter_sdk/bin/dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/txt_benchmark/main.dart 10 lines
.fvm/flutter_sdk/bin/dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/txt_benchmark/main.dart 16 lines
```

将 `lines` 改为 `single` 测长单行。每条命令启动独立进程，输出 JSON；输入为精确 1/10/16MiB ASCII，不以字符数冒充多字节文件大小。补充平面、中文及编码正确性由合成 UT 覆盖。

decodeMs 为严格解码；probeMs 为全候选探测加预览；parseMs **包含再次解码**与建模，不能三者相加当作实际导入耗时。ProcessInfo.maxRss 是该进程生命周期峰值，包含 VM/JIT、输入生成及上述三阶段，不是手机或单阶段分配量。样本内存生成也计入峰值，不测存储写入/UI；结果为单次观测，不是统计意义上的性能提升证明。

本轮先测基线再固定宿主预算：每阶段 <=5s、峰值 <=512MiB。不要作为不同机器的 CI 时间断言。已有 16MiB 输入/100000 行/10000 章限制不变，超限由测试验拒绝，不扩大支持范围。结果见 [benchmark.json](../../docs/validation/txt/benchmark.json)。
