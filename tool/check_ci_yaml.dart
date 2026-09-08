import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  final ci =
      loadYaml(File('.github/workflows/ci.yml').readAsStringSync()) as YamlMap;
  final ciEvents = ci['on'] as YamlMap;
  final ciJobs = ci['jobs'] as YamlMap;
  if (!ciEvents.containsKey('push') ||
      !ciEvents.containsKey('pull_request') ||
      !ciEvents.containsKey('workflow_dispatch') ||
      !ciEvents.containsKey('workflow_call')) {
    throw StateError('Missing expected events');
  }
  if (ciJobs.keys.length != 1 || !ciJobs.containsKey('analyze-test')) {
    throw StateError('Regular CI must contain only quality checks');
  }
  for (final step in ciJobs['analyze-test']['steps'] as YamlList) {
    final command = (step as YamlMap)['run']?.toString() ?? '';
    if (RegExp(r'flutter\s+build\s').hasMatch(command)) {
      throw StateError('Packaging is reserved for the tag release workflow');
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
  if (releaseJobs['android-release']['needs'].toString() !=
          '[ci-status, quality]' ||
      releaseJobs['quality']['uses'] != './.github/workflows/ci.yml' ||
      releaseJobs['quality']['if'] !=
          "needs.ci-status.outputs.reuse != 'true'" ||
      releaseJobs['ci-status']['permissions']['actions'] != 'read') {
    throw StateError(
      'Release must reuse exact-commit CI or call shared quality checks',
    );
  }
  final condition = releaseJobs['android-release']['if'].toString();
  for (final guard in [
    "needs.ci-status.result == 'success'",
    "needs.ci-status.outputs.reuse == 'true'",
    "needs.quality.result == 'success'",
    '!cancelled()',
  ]) {
    if (!condition.contains(guard)) {
      throw StateError('Missing release gate: $guard');
    }
  }
  final releaseChecks = ciJobs['analyze-test']['steps'] as YamlList;
  final releaseCommands = releaseChecks
      .map((step) => (step as YamlMap)['run']?.toString() ?? '')
      .join('\n');
  for (final required in [
    'dart tool/check_ci_yaml.dart',
    'bash tool/generate_database.sh',
    'git diff --exit-code -- lib/l10n/generated',
    'dart format --output=none --set-exit-if-changed lib test',
    'test_release_android.py',
    'node --test tool/test_release_ci_gate.cjs',
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
  int commandIndex(String command) => publishSteps.indexWhere(
    (step) => ((step as YamlMap)['run']?.toString() ?? '').contains(command),
  );
  final signing = commandIndex('release_android.py signing');
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

  for (final job in [...ciJobs.values, ...releaseJobs.values]) {
    if ((job as YamlMap)['uses'] != null) continue;
    for (final step in job['steps'] as YamlList) {
      final dir = (step as YamlMap)['working-directory'];
      if (dir != null && !Directory(dir as String).existsSync()) {
        throw StateError('Missing working directory: $dir');
      }
    }
  }
  stdout.writeln(
    'Workflow YAML parsed; quality-only CI, tag-only release '
    'and working directories verified.',
  );
}
