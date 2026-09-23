param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'build/windows-updater-test'
New-Item -ItemType Directory -Path $output -Force | Out-Null
# Ephemeral key and embedded build for this run only; never a release key.
& $Python (Join-Path $PSScriptRoot 'test_windows_updater.py') --prepare $output
if ($LASTEXITCODE -ne 0) { throw 'Cannot create updater test key' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -version '[17,18)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Visual Studio 2022 C++ tools not found' }
$vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
$update = Join-Path $root 'windows/update'
$sources = ('updater_main.cpp', 'release_manifest.cpp', 'update_transaction.cpp', 'manifest_signature.cpp' |
  ForEach-Object { '"{0}"' -f (Join-Path $update $_) }) -join ' '
$fixture = Join-Path $PSScriptRoot 'update_fixture_app.cpp'
Push-Location $output
try {
  $flags = '/nologo /std:c++17 /EHsc /W4 /WX /MT /utf-8 /DUNICODE /D_UNICODE /DNOMINMAX'
  $commands = @('@echo off', ('call "{0}" >nul' -f $vcvars),
    'if errorlevel 1 exit /b %errorlevel%',
    ('cl {0} /FI"{1}" /Fe:shiori-updater.exe {2} bcrypt.lib user32.lib shell32.lib' -f
      $flags, (Join-Path $output 'updater_test_key.h'), $sources),
    'if errorlevel 1 exit /b %errorlevel%',
    ('cl {0} /DFIXTURE_VERSION=1 /Fe:old-app.exe "{1}"' -f $flags, $fixture),
    'if errorlevel 1 exit /b %errorlevel%',
    ('cl {0} /DFIXTURE_VERSION=2 /Fe:new-app.exe "{1}"' -f $flags, $fixture),
    'exit /b %errorlevel%')
  Set-Content -LiteralPath (Join-Path $output 'compile.cmd') -Value $commands -Encoding oem
  & cmd.exe /d /c .\compile.cmd
  if ($LASTEXITCODE -ne 0) { throw 'Updater compilation failed' }
  & $Python (Join-Path $PSScriptRoot 'test_windows_updater.py') --bin-dir $output
  if ($LASTEXITCODE -ne 0) { throw 'Updater process tests failed' }
} finally { Pop-Location }
