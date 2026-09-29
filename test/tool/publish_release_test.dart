import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/publish_release.dart';

class _CapturedStdout implements Stdout {
  final text = StringBuffer();

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final projectTemplate = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();
  final configTemplate = File(
    'ios/ShareExtension/ShareExtension.xcconfig',
  ).readAsStringSync();
  const configPath = 'ios/ShareExtension/ShareExtension.xcconfig';
  const configReference =
      'baseConfigurationReference = E70200000000000000000001 /* ShareExtension.xcconfig */;';
  late Directory temporary;
  late String repo;
  late String remote;
  String git(List<String> args, {String? cwd}) {
    final result = Process.runSync('git', args, workingDirectory: cwd ?? repo);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return (result.stdout as String).trim();
  }

  void commit(String name) {
    File('$repo/$name').writeAsStringSync(name);
    git(['add', '.']);
    git(['commit', '-m', 'test: $name']);
  }

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('shiori-release-');
    repo = '${temporary.path}/work';
    remote = '${temporary.path}/remote.git';
    Directory(repo).createSync();
    git(['init', '--bare', remote]);
    git(['init', '-b', 'develop']);
    git(['config', 'user.name', 'Release Test']);
    git(['config', 'user.email', 'release@example.invalid']);
    git(['config', 'commit.gpgsign', 'false']);
    git(['config', 'tag.gpgsign', 'false']);
    File('$repo/pubspec.yaml').writeAsStringSync('version: 1.0.0+2\n');
    final project = File('$repo/ios/Runner.xcodeproj/project.pbxproj');
    project.parent.createSync(recursive: true);
    project.writeAsStringSync(projectTemplate);
    final config = File('$repo/$configPath');
    config.parent.createSync(recursive: true);
    config.writeAsStringSync(configTemplate);
    commit('initial');
    git(['remote', 'add', 'origin', remote]);
    git(['push', '-u', 'origin', 'develop']);
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  for (final entry in {
    'beta': '1.2.3',
    'stable': '1.2.3',
    'patch': '1.2.4',
    'minor': '1.3.0',
    'major': '2.0.0',
  }.entries) {
    test('prepare ${entry.key} only updates pubspec without publishing', () {
      File('$repo/pubspec.yaml').writeAsStringSync('version: 1.2.3+9\n');
      commit('version-base');
      final before = git(['show-ref']);
      expect(prepareRelease(repo, entry.key), entry.value);
      expect(git(['status', '--porcelain']), isEmpty);
      prepareRelease(repo, entry.key, apply: true);
      expect(
        File('$repo/pubspec.yaml').readAsStringSync(),
        'version: ${entry.value}+10\n',
      );
      final project = File(
        '$repo/ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(project, projectTemplate);
      expect(File('$repo/$configPath').readAsStringSync(), configTemplate);
      expect(git(['diff', '--name-only']), 'pubspec.yaml');
      expect(git(['show-ref']), before);
      expect(
        () => prepareRelease(repo, entry.key, apply: true),
        throwsStateError,
      );
    });
  }

  test('beta sequence uses local and remote tags independently of build', () {
    String preview() {
      final output = _CapturedStdout();
      IOOverrides.runZoned(
        () => prepareRelease(repo, 'beta'),
        stdout: () => output,
      );
      return output.text.toString();
    }

    expect(preview(), contains('Release tag: v1.0.0-beta.1'));
    git(['tag', 'v1.0.0-beta.2']);
    git(['tag', '-a', 'v1.0.0-beta.10', '-m', 'remote beta']);
    git(['push', 'origin', 'v1.0.0-beta.10']);
    git(['tag', '-d', 'v1.0.0-beta.10']);
    git(['tag', 'v1.0.0-beta.99-extra']);
    expect(preview(), contains('Release tag: v1.0.0-beta.11'));
    git(['tag', 'v1.0.0-beta.12']);
    expect(preview(), contains('Release tag: v1.0.0-beta.13'));
    expect(git(['status', '--porcelain']), isEmpty);

    prepareRelease(repo, 'patch', apply: true);
    commit('next-version');
    final next = preview();
    expect(next, contains('Release tag: v1.0.1-beta.1'));
    expect(next, contains('Internal build: 3 -> 4'));
  });

  test('beta tags develop and preserves a diverged master', () {
    git(['switch', '-c', 'master']);
    commit('master-only');
    git(['push', 'origin', 'master']);
    final master = git(['rev-parse', 'master']);
    git(['switch', 'develop']);
    commit('beta-change');
    git(['push', 'origin', 'develop']);
    final source = git(['rev-parse', 'develop']);
    final before = git(['show-ref']);
    publishRelease(repo, 'v1.0.0-beta.1');
    expect(git(['show-ref']), before);
    publishRelease(repo, 'v1.0.0-beta.1', publish: true);
    expect(git(['cat-file', '-t', 'v1.0.0-beta.1']), 'tag');
    expect(git(['rev-parse', 'v1.0.0-beta.1^{}'], cwd: remote), source);
    expect(git(['rev-parse', 'master']), master);
    expect(git(['rev-parse', 'master'], cwd: remote), master);
    expect(git(['branch', '--show-current']), 'develop');
    expect(
      () => publishRelease(repo, 'v1.0.0-beta.1', publish: true),
      throwsStateError,
    );
  });

  test('beta rejects invalid tags, dirty tree and unpushed develop', () {
    for (final tag in ['v1.0.1-beta.1', 'v1.0.0-beta.0', 'v1.0.0-beta.01']) {
      expect(() => publishRelease(repo, tag), throwsStateError);
    }
    File('$repo/dirty').writeAsStringSync('unfinished');
    expect(() => publishRelease(repo, 'v1.0.0-beta.1'), throwsStateError);
    commit('unpushed-beta');
    expect(() => publishRelease(repo, 'v1.0.0-beta.1'), throwsStateError);
  });

  test(
    'prepare rejects invalid increment and malformed extension before writing',
    () {
      expect(
        () => prepareRelease(repo, 'other', apply: true),
        throwsStateError,
      );
      File(
        '$repo/ios/Runner.xcodeproj/project.pbxproj',
      ).writeAsStringSync('invalid');
      commit('invalid-project');
      expect(
        () => prepareRelease(repo, 'patch', apply: true),
        throwsStateError,
      );
      expect(git(['status', '--porcelain']), isEmpty);
    },
  );

  for (final (id, configuration) in [
    ('36049AA6F05B2752A0E63A78', 'Debug'),
    ('85C1EC4F835BA79CAF20E01B', 'Release'),
    ('006068B0FCA81F3AA7B4D9E7', 'Profile'),
  ]) {
    for (final setting in [
      'CURRENT_PROJECT_VERSION = 18;',
      'MARKETING_VERSION = 1.3.0;',
      'FLUTTER_BUILD_NUMBER = 18;',
      '"MARKETING_VERSION[sdk=iphoneos*]" = 1.3.0;',
    ]) {
      test('rejects $configuration version override $setting', () {
        final project = File('$repo/ios/Runner.xcodeproj/project.pbxproj');
        final start = projectTemplate.indexOf('$id /* $configuration */ = {');
        final end = projectTemplate.indexOf('\n\t\t};', start);
        project.writeAsStringSync(
          projectTemplate.replaceRange(
            start,
            end,
            projectTemplate
                .substring(start, end)
                .replaceFirst(
                  'buildSettings = {',
                  'buildSettings = {\n\t\t\t\t$setting',
                ),
          ),
        );
        commit('override');
        git(['push', 'origin', 'develop']);
        final before = git(['show-ref']);
        expect(
          () => prepareRelease(repo, 'patch', apply: true),
          throwsStateError,
        );
        expect(
          () => publishRelease(repo, 'v1.0.0-beta.1', publish: true),
          throwsStateError,
        );
        expect(git(['status', '--porcelain']), isEmpty);
        expect(git(['show-ref']), before);
      });
    }
  }

  for (final invalidConfig in [
    '#include? "../Flutter/Generated.xcconfig"\n'
        r'MARKETING_VERSION = $(FLUTTER_BUILD_NAME)'
        '\n'
        r'CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER)',
    configTemplate.replaceFirst(r'$(FLUTTER_BUILD_NUMBER)', '18'),
    configTemplate.replaceFirst(r'$(FLUTTER_BUILD_NAME)', '1.3.0'),
    '${configTemplate}FLUTTER_BUILD_NUMBER = 18\n',
    '$configTemplate#include "Other.xcconfig"\n',
  ]) {
    test('rejects xcconfig that can bypass the pubspec version source', () {
      File('$repo/$configPath').writeAsStringSync(invalidConfig);
      commit('invalid-config');
      git(['push', 'origin', 'develop']);
      expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
    });
  }

  for (final replacement in [
    '',
    'baseConfigurationReference = 9740EEB31CF90195004384FC /* Generated.xcconfig */;',
  ]) {
    test('rejects a disconnected extension configuration', () {
      File('$repo/ios/Runner.xcodeproj/project.pbxproj').writeAsStringSync(
        projectTemplate.replaceFirst(configReference, replacement),
      );
      commit('disconnected-config');
      git(['push', 'origin', 'develop']);
      expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
    });
  }

  test('rejects an incomplete extension target configuration list', () {
    File('$repo/ios/Runner.xcodeproj/project.pbxproj').writeAsStringSync(
      projectTemplate.replaceFirst(
        '\t\t\t\t006068B0FCA81F3AA7B4D9E7 /* Profile */,\n',
        '',
      ),
    );
    commit('missing-profile');
    git(['push', 'origin', 'develop']);
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
  });

  test('preview leaves branch and tag refs unchanged', () {
    final before = git(['show-ref']);
    publishRelease(repo, 'v1.0.0');
    expect(git(['show-ref']), before);
    expect(
      git(['ls-remote', 'origin', 'refs/heads/master', 'refs/tags/v1.0.0']),
      isEmpty,
    );
  });

  test('remote tag rejection leaves both remote refs unpublished', () {
    final hook = File('$remote/hooks/update');
    hook.writeAsStringSync(
      '#!/bin/sh\n'
      r'case "$1" in refs/tags/*) exit 1;; esac'
      '\nexit 0\n',
    );
    if (!Platform.isWindows) {
      final result = Process.runSync('chmod', ['+x', hook.path]);
      expect(result.exitCode, 0);
    }
    expect(
      () => publishRelease(repo, 'v1.0.0', publish: true),
      throwsStateError,
    );
    expect(
      git(['ls-remote', 'origin', 'refs/heads/master', 'refs/tags/v1.0.0']),
      isEmpty,
    );
    // Retain local release evidence for review/retry; never delete on failure.
    expect(git(['tag', '--list']), 'v1.0.0');
    expect(git(['branch', '--show-current']), 'master');
  });

  test('first release creates master and annotated tag atomically', () {
    final source = git(['rev-parse', 'develop']);
    publishRelease(repo, 'v1.0.0', publish: true);
    expect(git(['rev-parse', 'master']), source);
    expect(git(['rev-parse', 'v1.0.0^{}']), source);
    expect(git(['cat-file', '-t', 'v1.0.0']), 'tag');
    expect(git(['branch', '--show-current']), 'develop');
    expect(git(['rev-parse', 'master'], cwd: remote), source);
    expect(git(['rev-parse', 'v1.0.0^{}'], cwd: remote), source);
    expect(
      () => publishRelease(repo, 'v1.0.0', publish: true),
      throwsStateError,
    );
  });

  test('existing master produces a merge commit and tag at that commit', () {
    git(['switch', '-c', 'master']);
    commit('master-only');
    git(['push', 'origin', 'master']);
    final previous = git(['rev-parse', 'master']);
    git(['switch', 'develop']);
    commit('next');
    git(['push', 'origin', 'develop']);
    final source = git(['rev-parse', 'develop']);
    publishRelease(repo, 'v1.0.0', publish: true);
    expect(git(['rev-parse', 'master^1']), previous);
    expect(git(['rev-parse', 'master^2']), source);
    expect(git(['rev-parse', 'v1.0.0^{}']), git(['rev-parse', 'master']));
  });

  test('linear release retains the tested develop SHA', () {
    git(['branch', 'master']);
    git(['push', 'origin', 'master']);
    commit('linear-next');
    git(['push', 'origin', 'develop']);
    final source = git(['rev-parse', 'develop']);
    publishRelease(repo, 'v1.0.0', publish: true);
    expect(git(['rev-parse', 'master']), source);
    expect(git(['rev-parse', 'v1.0.0^{}']), source);
  });

  test('rejects dirty tree, wrong version and unpushed develop', () {
    expect(() => publishRelease(repo, 'v1.0.1'), throwsStateError);
    File('$repo/dirty').writeAsStringSync('unfinished');
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
    commit('unpushed');
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
  });

  test('rejects diverged local master', () {
    git(['branch', 'master']);
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
  });

  test('rejects master-only xcconfig changes before tagging', () {
    git(['switch', '-c', 'master']);
    File(
      '$repo/$configPath',
    ).writeAsStringSync('$configTemplate\nFLUTTER_BUILD_NUMBER = 18\n');
    commit('master-version-override');
    git(['push', 'origin', 'master']);
    final previous = git(['rev-parse', 'master']);
    git(['switch', 'develop']);
    commit('next');
    git(['push', 'origin', 'develop']);
    expect(
      () => publishRelease(repo, 'v1.0.0', publish: true),
      throwsStateError,
    );
    expect(git(['rev-parse', 'master'], cwd: remote), previous);
    expect(git(['tag', '--list']), isEmpty);
  });

  test('merge conflict leaves remote untouched and creates no tag', () {
    git(['switch', '-c', 'master']);
    File('$repo/initial').writeAsStringSync('master edit');
    git(['commit', '-am', 'test: master edit']);
    git(['push', 'origin', 'master']);
    final previous = git(['rev-parse', 'master']);
    git(['switch', 'develop']);
    File('$repo/initial').writeAsStringSync('develop edit');
    git(['commit', '-am', 'test: develop edit']);
    git(['push', 'origin', 'develop']);
    expect(
      () => publishRelease(repo, 'v1.0.0', publish: true),
      throwsStateError,
    );
    expect(git(['rev-parse', 'master'], cwd: remote), previous);
    expect(git(['tag', '--list']), isEmpty);
    expect(git(['branch', '--show-current']), 'master');
  });
}
