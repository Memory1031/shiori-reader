import 'dart:convert';
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
  if (ciJobs.length != 1 || !ciJobs.containsKey('quality')) {
    throw StateError('Regular CI must contain only the quality job');
  }
  final flutterVersion =
      (jsonDecode(File('.fvmrc').readAsStringSync()) as Map)['flutter'];
  if (ci['env']['FLUTTER_VERSION'].toString() != flutterVersion) {
    throw StateError('CI must use the pinned Flutter SDK');
  }
  for (final step in ciJobs['quality']['steps'] as YamlList) {
    final command = (step as YamlMap)['run']?.toString() ?? '';
    if (RegExp(
          r'flutter\s+build\s|package_windows\.ps1|gh\s+release\b',
        ).hasMatch(command) ||
        (step['uses']?.toString() ?? '').startsWith(
          'actions/upload-artifact@',
        )) {
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
  if (releaseJobs.length != 3 ||
      !releaseJobs.containsKey('android-release') ||
      !releaseJobs.containsKey('windows-release') ||
      !releaseJobs.containsKey('publish') ||
      releaseJobs['android-release']['needs'] != null ||
      releaseJobs['windows-release']['needs'] != null ||
      (releaseJobs['publish']['needs'] as YamlList).toSet().difference({
        'android-release',
        'windows-release',
      }).isNotEmpty ||
      (releaseJobs['publish']['needs'] as YamlList).length != 2) {
    throw StateError(
      'Release needs parallel builders and one dependent publisher',
    );
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
  if (signing < 0 || build <= signing || verify <= build) {
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

  final windowsRelease = releaseJobs['windows-release'] as YamlMap;
  final zipSteps = windowsRelease['steps'] as YamlList;
  int zipIndex(String command) => zipSteps.indexWhere(
    (step) => (step['run']?.toString() ?? '').contains(command),
  );
  final zipVersion = zipIndex('release_android.py version');
  final zipDependencies = zipIndex('flutter pub get --enforce-lockfile');
  final zipLock = zipIndex('git diff --exit-code -- pubspec.lock');
  final zipBuild = zipIndex(
    'flutter build windows --release --no-pub --target lib/main.dart',
  );
  final zipPackage = zipIndex('./tool/package_windows.ps1');
  final zipUpload = zipSteps.indexWhere(
    (step) =>
        (step['uses']?.toString() ?? '').startsWith('actions/upload-artifact@'),
  );
  if (release['env']['FLUTTER_VERSION'].toString() != flutterVersion ||
      windowsRelease['runs-on'] != 'windows-2022' ||
      windowsRelease['defaults']['run']['shell'] != 'pwsh' ||
      windowsRelease['env']['GIT_CONFIG_COUNT'] != '1' ||
      windowsRelease['env']['GIT_CONFIG_KEY_0'] != 'core.longpaths' ||
      windowsRelease['env']['GIT_CONFIG_VALUE_0'] != 'true' ||
      zipVersion < 0 ||
      zipDependencies <= zipVersion ||
      zipLock <= zipDependencies ||
      zipBuild <= zipLock ||
      zipPackage <= zipBuild ||
      zipUpload <= zipPackage) {
    throw StateError(
      'Windows release must check version, lock, build and package before upload',
    );
  }
  final publisher = releaseJobs['publish'] as YamlMap;
  final publisherSteps = publisher['steps'] as YamlList;
  final downloads = publisherSteps
      .where(
        (step) => (step['uses']?.toString() ?? '').startsWith(
          'actions/download-artifact@',
        ),
      )
      .toList();
  if (downloads.length != 2 ||
      downloads.map((step) => step['with']['name']).toSet().difference({
        r'android-release-${{ github.ref_name }}',
        r'windows-release-${{ github.ref_name }}',
      }).isNotEmpty ||
      downloads.any(
        (step) =>
            step['with']['path'] != 'build/release-assets/' ||
            step['with']['run-id'] != null,
      ) ||
      publisher['permissions']['contents'] != 'write' ||
      release['permissions']['contents'] != 'read') {
    throw StateError(
      'Only publisher may write releases using both current-run artifacts',
    );
  }
  int publisherIndex(String command) => publisherSteps.indexWhere(
    (step) => (step['run']?.toString() ?? '').contains(command),
  );
  final sums = publisherIndex('sha256sum --check SHA256SUMS.txt');
  if (sums <= publisherSteps.indexOf(downloads.last) ||
      publisherIndex('sha256sum --check SHA256SUMS-windows-x64.txt') != sums ||
      publisherIndex('gh release create') <= sums) {
    throw StateError('Both artifact checksums must pass before publishing');
  }
  for (final builder in ['android-release', 'windows-release']) {
    if (releaseJobs[builder]['permissions']?['contents'] == 'write') {
      throw StateError('Build jobs must not have release write permissions');
    }
  }

  final ios =
      loadYaml(File('.github/workflows/ios-release.yml').readAsStringSync())
          as YamlMap;
  final iosEvents = ios['on'] as YamlMap;
  final iosJobs = ios['jobs'] as YamlMap;
  // iOS 发布同样只由 tag 触发上传；手动入口仅允许构建冒烟。
  if ((iosEvents['push'] as YamlMap)['tags'] == null) {
    throw StateError('iOS release must be tag-triggered');
  }
  // 公开仓库的 Actions 产物任何登录用户都可下载；
  // 含未加密私钥的证书引导任务不得回归。
  if (iosJobs.containsKey('bootstrap-signing')) {
    throw StateError(
      'iOS certificate bootstrap must not exist: its artifact would expose '
      'the unencrypted private key to any logged-in user of a public repo',
    );
  }
  if (iosJobs.length != 1 || !iosJobs.containsKey('ios-release')) {
    throw StateError('iOS release must contain only the release job');
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

  // ---- Security regressions shared across all workflows ----
  final workflows = {
    'ci.yml': ci,
    'release.yml': release,
    'ios-release.yml': ios,
  };
  final shaPinned = RegExp(
    r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-fA-F]{40}$',
  );
  for (final entry in workflows.entries) {
    // pull_request_target runs workflow code from the target branch with
    // base-repo context; fork PRs must only use the plain pull_request CI.
    if ((entry.value['on'] as YamlMap).containsKey('pull_request_target')) {
      throw StateError('${entry.key} must not use pull_request_target');
    }
    for (final job in (entry.value['jobs'] as YamlMap).values) {
      final jobMap = job as YamlMap;
      if (jobMap['uses'] != null) continue;
      for (final step in jobMap['steps'] as YamlList) {
        final stepMap = step as YamlMap;
        final uses = stepMap['uses']?.toString() ?? '';
        if (uses.isEmpty || uses.startsWith('./')) continue;
        // Mutable refs (@v4, @main) let a moved tag change the code CI runs.
        if (!shaPinned.hasMatch(uses)) {
          throw StateError(
            'External action must be pinned to a full 40-hex commit SHA '
            '(${entry.key}): $uses',
          );
        }
        if (uses.startsWith('actions/checkout@') &&
            (stepMap['with'] as YamlMap?)?['persist-credentials'] != false) {
          throw StateError(
            'actions/checkout must disable persist-credentials '
            '(${entry.key}): $uses',
          );
        }
      }
    }
  }

  // Fork PRs execute regular CI; it must never touch release credentials.
  final ciText = File('.github/workflows/ci.yml').readAsStringSync();
  for (final secret in [
    'ASC_KEY_ID',
    'ASC_ISSUER_ID',
    'ASC_KEY_P8',
    'IOS_DIST_CERT_P12',
    'IOS_DIST_CERT_PASSWORD',
    'ANDROID_KEYSTORE_BASE64',
    'ANDROID_STORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD',
  ]) {
    if (ciText.contains(secret)) {
      throw StateError('Regular CI must not reference signing secret: $secret');
    }
  }
  if ((ci['permissions'] as YamlMap)['contents'] != 'read') {
    throw StateError('Regular CI must stay read-only (contents: read)');
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
    '(Android + Windows + iOS), tag-gated uploads, SHA-pinned actions, no persisted '
    'checkout credentials and working directories verified.',
  );
}
