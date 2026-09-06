# Dot-source from PowerShell before local Android commands:
# . ./tool/android-env.ps1
$shioriRoot = Split-Path -Parent $PSScriptRoot
$shioriJdk = Join-Path $shioriRoot '.tooling/jdk/jdk-17.0.20.1+1'
$shioriAndroidSdk = Join-Path $shioriRoot '.tooling/android-sdk'

if (-not (Test-Path (Join-Path $shioriJdk 'bin/java.exe'))) {
    throw 'Install the pinned local JDK first; see docs/development.md.'
}
if (-not (Test-Path (Join-Path $shioriAndroidSdk 'cmdline-tools/latest/bin/sdkmanager.bat'))) {
    throw 'Install the local Android SDK first; see docs/development.md.'
}

# No registry, setx, or global Flutter configuration changes.
$env:JAVA_HOME = $shioriJdk
$env:ANDROID_HOME = $shioriAndroidSdk
$env:ANDROID_SDK_ROOT = $shioriAndroidSdk
$env:GRADLE_USER_HOME = Join-Path $shioriRoot '.tooling/gradle'
$env:Path = "$shioriJdk/bin;$shioriAndroidSdk/platform-tools;$env:Path"

# Flutter may prefer Android Studio's bundled JBR over JAVA_HOME. Keep the
# Gradle build JVM pinned in this project's ignored cache, preserving other keys.
New-Item -ItemType Directory -Path $env:GRADLE_USER_HOME -Force | Out-Null
$shioriGradleProperties = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$shioriExistingProperties = if (Test-Path $shioriGradleProperties) {
    @(Get-Content -LiteralPath $shioriGradleProperties |
        Where-Object { $_ -notmatch '^\s*org\.gradle\.java\.home\s*=' })
} else {
    @()
}
$shioriJavaProperty = 'org.gradle.java.home=' + $shioriJdk.Replace('\', '/')
# Write without BOM on both Windows PowerShell 5.1 and PowerShell 7.
$shioriPropertiesText = (@($shioriExistingProperties) + $shioriJavaProperty) -join [Environment]::NewLine
[IO.File]::WriteAllText(
    $shioriGradleProperties,
    $shioriPropertiesText + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)
