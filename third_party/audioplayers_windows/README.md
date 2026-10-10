# audioplayers_windows

基于上游 `audioplayers_windows 4.3.1` 的 Windows 原生实现，保留 MIT 许可。
原始发布包 SHA-256：`95f875a96c88c3dbbcb608d4f8288e300b0113d256a81d0b3197fcc18f0dc91a`。
来源：[bluefireteam/audioplayers](https://github.com/bluefireteam/audioplayers/tree/main/packages/audioplayers_windows)。

本地补丁使用注册插件时创建的消息窗口，将成功和错误事件异步派发到
Flutter 平台线程。取消、重新订阅或销毁通道时，旧订阅的排队事件被丢弃；
插件释放时注销事件处理器并销毁消息窗口。音频解码和其他平台实现保持上游行为。

原生回归位于 `windows/test`。先用固定 FVM 工具链构建 Windows，生成客户端包装头文件，
再以 CMake 配置该测试目录，设置 `FLUTTER_WRAPPER_INCLUDE` 为
`windows/flutter/ephemeral/cpp_client_wrapper/include` 的绝对路径；构建后执行 CTest。
