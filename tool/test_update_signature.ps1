param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root 'build/update-signature-test'
New-Item -ItemType Directory -Path $output -Force | Out-Null
# Doubled single quotes: Windows PowerShell 5.1 strips double quotes from native arguments.
& $Python -c 'import base64,json,sys; from pathlib import Path; v=json.loads(Path(sys.argv[1]).read_bytes()); d=Path(sys.argv[2]); c=v[''cases''][''valid'']; (d/''manifest.json'').write_bytes(base64.b64decode(c[''manifest''])); (d/''manifest.sig'').write_bytes(base64.b64decode(c[''signature''])); (d/''modulus.bin'').write_bytes(bytes.fromhex(v[''publicKey''][''modulus'']))' (Join-Path $root 'test/fixtures/updates/vectors.json') $output
if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare signature test vectors' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -version '[17,18)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Visual Studio 2022 C++ tools not found' }
$vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
$source = Join-Path $root 'windows/update/manifest_signature.cpp'
$test = Join-Path $PSScriptRoot 'test_update_signature.cpp'
Push-Location $output
try {
  $commands = @('@echo off', ('call "{0}" >nul' -f $vcvars),
    'if errorlevel 1 exit /b %errorlevel%',
    ('cl /nologo /std:c++17 /EHsc /W4 /WX /Fe:verify.exe "{0}" "{1}" bcrypt.lib' -f $source, $test),
    'exit /b %errorlevel%')
  Set-Content -LiteralPath (Join-Path $output 'compile.cmd') -Value $commands -Encoding oem
  & cmd.exe /d /c .\compile.cmd
  if ($LASTEXITCODE -ne 0) { throw 'Signature verifier compilation failed' }
  & (Join-Path $output 'verify.exe') 'manifest.json' 'manifest.sig' 'modulus.bin'
  if ($LASTEXITCODE -ne 0) { throw 'Windows signature interoperability test failed' }
} finally { Pop-Location }
