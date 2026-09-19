param([string]$Tag = $env:GITHUB_REF_NAME, [string]$Commit = $env:GITHUB_SHA)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -version '[17,18)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Visual Studio 2022 C++ installation not found' }
$crt = Get-ChildItem -LiteralPath (Join-Path $vs 'VC/Redist/MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
    Select-Object -First 1
if (!$crt) { throw 'Visual C++ x64 redistributable DLL directory not found' }
python tool/release_windows.py --tag $Tag --commit $Commit --crt-dir $crt
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
