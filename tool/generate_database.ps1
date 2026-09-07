param([string]$Dart = 'dart')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$generatorRoot = Join-Path $PSScriptRoot 'db_codegen'
$schemaRoot = Join-Path $repoRoot 'lib/data/local/database'
foreach ($name in @('user_database.dart', 'cache_database.dart', 'users.drift', 'cache.drift')) {
    Copy-Item -LiteralPath (Join-Path $schemaRoot $name) -Destination (Join-Path $generatorRoot "lib/$name")
}
Push-Location $generatorRoot
try {
    & $Dart --suppress-analytics run build_runner build
    if ($LASTEXITCODE -ne 0) { throw 'Database generation failed' }
    foreach ($kind in @('user', 'cache')) {
        Copy-Item -LiteralPath "lib/${kind}_database.g.dart" -Destination $schemaRoot
        & $Dart --suppress-analytics run drift_dev schema dump "lib/${kind}_database.dart" "../../lib/data/local/database/schemas/$kind"
        if ($LASTEXITCODE -ne 0) { throw 'Schema export failed' }
    }
} finally { Pop-Location }
