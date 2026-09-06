# Shiori Logo

应用 Logo 原图：`shiori-chibi-logo-v1.png`，已注册为 Flutter asset。

Android 的 `@mipmap/ic_launcher` 和 iOS 的 `AppIcon` 使用从该原图缩放生成的 PNG。
更换原图后，在 Windows 的 PowerShell 中运行：

```powershell
./tool/update-app-icons.ps1
```

脚本更新 Android 的 5 档密度及 iOS 图标目录声明的全部尺寸；iOS 输出不含透明通道。
重新构建并安装应用后，桌面图标生效，热重载不会更新原生图标。
