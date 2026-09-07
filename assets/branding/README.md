# Shiori Logo

应用 Logo 原图：`shiori-chibi-logo-v1.png`，已注册为 Flutter asset。

Android 的 `@mipmap/ic_launcher` 和 iOS 的 `AppIcon` 使用从该原图缩放生成的 PNG。
更换原图后，在 Windows 的 PowerShell 中运行：

```powershell
./tool/update-app-icons.ps1
```

脚本更新 Android 的 5 档密度及 iOS 图标目录声明的全部尺寸；iOS 输出不含透明通道。
重新构建并安装应用后，桌面图标生效，热重载不会更新原生图标。

Android 启动屏专用高清副本为 `android/app/src/main/res/drawable-nodpi/shiori_launch_logo.png`，直接复制本目录原图，不从 mipmap 桌面缩略图派生。更新 Logo 时也须同步该副本；Flutter 加载页直接读取本目录原图。

- iOS 原生启动 Logo 使用 `ios/Runner/Assets.xcassets/ShioriLaunchLogo.imageset/shiori-logo.png`，为品牌原图的完整复制；更新品牌原图时同步此文件。布局由 `LaunchScreen.storyboard` 的 128pt aspect-fit 约束负责，不使用 AppIcon 裁切图。深浅背景 / 字标颜色分别在 ShioriLaunchPaper / ShioriLaunchInk colorset 中维护。
