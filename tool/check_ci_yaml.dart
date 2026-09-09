import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  final ci =
      loadYaml(File('.github/workflows/ci.yml').readAsStringSync()) as YamlMap;
  final ciEvents = ci['on'] as YamlMap;
  final ciJobs = ci['jobs'] as YamlMap;
  if (!ciEvents.containsKey('push') ||
      !ciEvents.containsKey('pull_request') ||
      !ciEvents.containsKey('workflow_dispatch')) {
    throw StateError('Missing expected events');
  }
  if (ciJobs.keys.length != 1 || !ciJobs.containsKey('quality')) {
    throw StateError('Regular CI must contain only quality checks');
  }
  for (final step in ciJobs['quality']['steps'] as YamlList) {
    final command = (step as YamlMap)['run']?.toString() ?? '';
    if (RegExp(r'flutter\s+build\s').hasMatch(command)) {
      throw StateError('Packaging is reserved for the tag release workflow');
    }
    if (RegExp(
      r'\b(flutter|dart)\s+(?:--suppress-analytics\s+)?test\b|\bpython3?\s+-m\s+unittest\b',
    ).hasMatch(command)) {
      throw StateError(
        'Run unit/widget tests locally before committing, not in daily CI',
      );
    }
  }

  final release =
      loadYaml(File('.github/workflows/release.yml').readAsStringSync())
          as YamlMap;
  final releaseEvents = release['on'] as YamlMap;
  final releaseJobs = release['jobs'] as YamlMap;
  // 发布工作流只允许 tag 触发：普通推送 / PR / 手动入口不得产出发布包。
  if (releaseEvents.keys.length != 1 ||
      (releaseEvents['push'] as YamlMap)['tags'] == null) {
    throw StateError('Release workflow must be tag-triggered only');
  }
  if (releaseJobs.length != 1 ||
      !releaseJobs.containsKey('android-release') ||
      releaseJobs['android-release']['needs'] != null) {
    throw StateError('Tag release must enter Android packaging directly');
  }
  final releaseChecks = ciJobs['quality']['steps'] as YamlList;
  final releaseCommands = releaseChecks
      .map((step) => (step as YamlMap)['run']?.toString() ?? '')
      .join('\n');
  for (final required in [
    'dart tool/check_ci_yaml.dart',
    'bash tool/generate_database.sh',
    'git diff --exit-code -- lib/l10n/generated',
    'dart format --output=none --set-exit-if-changed lib test',
  ]) {
    if (!releaseCommands.contains(required)) {
      throw StateError('Missing release check: $required');
    }
  }
  if (!releaseChecks.any(
    (step) => (step as YamlMap)['working-directory'] == 'tool/db_codegen',
  )) {
    throw StateError('Release analysis needs database generator dependencies');
  }
  final publishSteps = releaseJobs['android-release']['steps'] as YamlList;
  if (publishSteps.any(
    (step) => RegExp(
      r'flutter\s+(test|analyze)\b',
    ).hasMatch(step['run']?.toString() ?? ''),
  )) {
    throw StateError('Full quality checks belong in develop CI only');
  }
  int commandIndex(String command) => publishSteps.indexWhere(
    (step) => ((step as YamlMap)['run']?.toString() ?? '').contains(command),
  );
  final signing = commandIndex('release_android.py signing');
  if (commandIndex('release_android.py tools') < 0 ||
      commandIndex('release_android.py tools') >= signing) {
    throw StateError('Pinned APK tools must be checked before signing/build');
  }
  if (commandIndex('release_android.py version') < 0 ||
      commandIndex('release_android.py version') >= signing) {
    throw StateError('Tag version check must precede signing');
  }
  final build = commandIndex('flutter build apk --release');
  final verify = commandIndex('release_android.py verify');
  final publish = commandIndex('gh release create');
  if (signing < 0 || build <= signing || verify <= build || publish <= verify) {
    throw StateError(
      'Release must prepare signing, build, verify, then publish',
    );
  }
  final secrets = publishSteps[signing]['env'] as YamlMap;
  for (final name in [
    'ANDROID_KEYSTORE_BASE64',
    'ANDROID_STORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD',
  ]) {
    if (secrets[name] != '\${{ secrets.$name }}') {
      throw StateError('Missing signing secret binding: $name');
    }
  }
  if (!publishSteps.any(
    (step) =>
        step['if'] == 'always()' &&
        (step['run']?.toString() ?? '').contains(
          'rm -f android/key.properties',
        ),
  )) {
    throw StateError('Signing files need unconditional cleanup');
  }

  final ios =
      loadYaml(File('.github/workflows/ios-release.yml').readAsStringSync())
          as YamlMap;
  final iosEvents = ios['on'] as YamlMap;
  final iosJobs = ios['jobs'] as YamlMap;
  // iOS 发布同样只由 tag 触发上传；手动入口仅允许构建冒烟与证书引导。
  if ((iosEvents['push'] as YamlMap)['tags'] == null) {
    throw StateError('iOS release must be tag-triggered');
  }
  if (iosJobs['bootstrap-signing']['if'] !=
      "github.event_name == 'workflow_dispatch' && github.event.inputs.mode == 'bootstrap-cert'") {
    throw StateError('iOS certificate bootstrap must stay manual and opt-in');
  }
  if (iosJobs['ios-release']['if'] !=
      "github.event_name != 'workflow_dispatch' || github.event.inputs.mode == 'build'") {
    throw StateError('iOS release job must not run for the bootstrap mode');
  }
  final iosSteps = iosJobs['ios-release']['steps'] as YamlList;
  int iosIndex(String needle) => iosSteps.indexWhere(
    (step) => ((step as YamlMap)['run']?.toString() ?? '').contains(needle),
  );
  final iosArchive = iosIndex('xcodebuild -workspace');
  final iosExport = iosIndex('xcodebuild -exportArchive');
  final iosUpload = iosIndex('xcrun altool --upload-app');
  if (iosArchive < 0 || iosExport <= iosArchive || iosUpload <= iosExport) {
    throw StateError('iOS release must archive, export, then upload');
  }
  const tagGate = "startsWith(github.ref, 'refs/tags/')";
  final iosVersionStep = iosSteps.firstWhere(
    (step) =>
        (step as YamlMap)['run']?.toString().contains(
          'release_android.py version',
        ) ==
        true,
    orElse: () => null,
  );
  if (iosVersionStep == null ||
      (iosVersionStep as YamlMap)['if'] != tagGate ||
      iosSteps[iosUpload]['if'] != tagGate) {
    throw StateError(
      'iOS version check and TestFlight upload must be tag-gated',
    );
  }
  if (!iosSteps.any(
    (step) => ((step as YamlMap)['uses']?.toString() ?? '').startsWith(
      'apple-actions/import-codesign-certs',
    ),
  )) {
    throw StateError('iOS release must import the distribution certificate');
  }
  if (iosSteps.any(
    (step) => RegExp(
      r'flutter\s+(test|analyze)\b',
    ).hasMatch((step as YamlMap)['run']?.toString() ?? ''),
  )) {
    throw StateError('iOS release must not duplicate develop quality checks');
  }

  for (final job in [
    ...ciJobs.values,
    ...releaseJobs.values,
    ...iosJobs.values,
  ]) {
    if ((job as YamlMap)['uses'] != null) continue;
    for (final step in job['steps'] as YamlList) {
      final dir = (step as YamlMap)['working-directory'];
      if (dir != null && !Directory(dir as String).existsSync()) {
        throw StateError('Missing working directory: $dir');
      }
    }
  }
  stdout.writeln(
    'Workflow YAML parsed; quality-only CI, tag-only releases '
    '(Android + iOS), tag-gated uploads and working directories verified.',
  );
}
