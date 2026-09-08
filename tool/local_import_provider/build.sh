#!/bin/sh
# ANDROID_HOME / JAVA_HOME must point to the local SDK and JDK 17.
set -eu
: "${ANDROID_HOME:?Set ANDROID_HOME}"
: "${JAVA_HOME:?Set JAVA_HOME to JDK 17}"
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
task_out="$task_root/.tooling/import-provider"
task_tools="$ANDROID_HOME/build-tools/35.0.0"
task_jar="$ANDROID_HOME/platforms/android-36/android.jar"
mkdir -p "$task_out/classes" "$task_out/dex"
"$JAVA_HOME/bin/javac" -source 17 -target 17 -classpath "$task_jar" -d "$task_out/classes" "$task_root"/tool/local_import_provider/*.java
"$task_tools/d8" --lib "$task_jar" --output "$task_out/dex" "$task_out"/classes/dev/shiori/importfixture/*.class
"$task_tools/aapt" package -f -M "$task_root/tool/local_import_provider/AndroidManifest.xml" -I "$task_jar" -F "$task_out/unsigned.apk"
zip -q -j "$task_out/unsigned.apk" "$task_out/dex/classes.dex"
"$task_tools/zipalign" -f 4 "$task_out/unsigned.apk" "$task_out/aligned.apk"
if [ ! -f "$task_out/test.jks" ]; then
  "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$task_out/test.jks" -storepass android -keypass android -alias test -dname "CN=Offline Test" -keyalg RSA -validity 3650 >/dev/null 2>&1
fi
"$task_tools/apksigner" sign --ks "$task_out/test.jks" --ks-pass pass:android --out "$task_out/provider.apk" "$task_out/aligned.apk"
