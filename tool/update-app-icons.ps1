# Run from Windows PowerShell or PowerShell on Windows.
# Resize the original artwork into the native launcher icon resources.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets/branding/shiori-chibi-logo-v1.png'
$sourceImage = [Drawing.Image]::FromFile($sourcePath)

function Write-AppIcon([string]$Path, [int]$Size) {
    # RGB output keeps iOS app icons opaque, including the App Store image.
    $bitmap = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $attributes = [Drawing.Imaging.ImageAttributes]::new()
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(255, 248, 233))
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $rectangle = [Drawing.Rectangle]::new(0, 0, $Size, $Size)
        $graphics.DrawImage($sourceImage, $rectangle, 0, 0, $sourceImage.Width, $sourceImage.Height, [Drawing.GraphicsUnit]::Pixel, $attributes)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $attributes.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw 'The app icon source must be square.'
    }
    $densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
    foreach ($density in $densities.GetEnumerator()) {
        $path = Join-Path $projectRoot "android/app/src/main/res/mipmap-$($density.Key)/ic_launcher.png"
        Write-AppIcon $path $density.Value
    }
    $catalogPath = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    $catalog = Get-Content -LiteralPath (Join-Path $catalogPath 'Contents.json') -Raw | ConvertFrom-Json
    foreach ($entry in ($catalog.images | Sort-Object filename -Unique)) {
        $points = [double]::Parse($entry.size.Split('x')[0], [Globalization.CultureInfo]::InvariantCulture)
        $scale = [int]$entry.scale.TrimEnd('x')
        Write-AppIcon (Join-Path $catalogPath $entry.filename) ([int]($points * $scale))
    }
    Write-Output 'Updated Android and iOS app icons from assets/branding/shiori-chibi-logo-v1.png.'
} finally {
    $sourceImage.Dispose()
}
