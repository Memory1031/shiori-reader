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
  if (ciJobs['android-build']['if'] != null ||
      ciJobs['android-build']['needs'] != 'analyze-test') {
    throw StateError('Regular APK build must depend on checks');
  }

  final androidJob = ciJobs['android-build'] as YamlMap;
  final androidSteps = androidJob['steps'] as YamlList;
  final smoke = androidSteps.cast<YamlMap>().singleWhere(
    (step) => step['name'] == '构建 release smoke APK',
  );
  if (androidJob['runs-on'] != 'ubuntu-latest' ||
      smoke['if'] !=
          "github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/main')" ||
      ci['permissions']['contents'] != 'read' ||
      File(
        '.github/workflows/ci.yml',
      ).readAsStringSync().contains('secrets.')) {
    throw StateError(
      'Android smoke must be Linux, main/manual and secret-free',
    );
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
  if (releaseJobs['android-release']['needs'] != 'checks') {
    throw StateError('Android release build must depend on checks');
  }

  for (final job in [...ciJobs.values, ...releaseJobs.values]) {
    for (final step in (job as YamlMap)['steps'] as YamlList) {
      final dir = (step as YamlMap)['working-directory'];
      if (dir != null && !Directory(dir as String).existsSync()) {
        throw StateError('Missing working directory: $dir');
      }
    }
  }
  stdout.writeln(
    'Workflow YAML parsed; triggers, regular Debug, main/manual smoke, tag-only release '
    'and working directories verified.',
  );
}
