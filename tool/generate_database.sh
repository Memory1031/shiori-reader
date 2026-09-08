#!/usr/bin/env bash
# macOS / Linux 入口，与 generate_database.ps1 使用同一隔离生成器。
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
generator_root="$repo_root/tool/db_codegen"
schema_root="$repo_root/lib/data/local/database"
dart_bin="${DART_BIN:-dart}"
mkdir -p "$generator_root/lib"
for name in user_database.dart cache_database.dart users.drift cache.drift; do
  cp "$schema_root/$name" "$generator_root/lib/$name"
done
cd "$generator_root"
"$dart_bin" --suppress-analytics run build_runner build
for kind in user cache; do
  cp "lib/${kind}_database.g.dart" "$schema_root/"
  "$dart_bin" --suppress-analytics run drift_dev schema dump \
    "lib/${kind}_database.dart" "$schema_root/schemas/$kind"
done
