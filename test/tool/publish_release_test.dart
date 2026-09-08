import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/publish_release.dart';

void main() {
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
    project.writeAsStringSync(
      'buildSettings = {\n'
      'INFOPLIST_FILE = ShareExtension/Info.plist;\n'
      'MARKETING_VERSION = 1.0.0;\nCURRENT_PROJECT_VERSION = 2;\n};',
    );
    commit('initial');
    git(['remote', 'add', 'origin', remote]);
    git(['push', '-u', 'origin', 'develop']);
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  for (final entry in {
    'patch': '1.2.4',
    'minor': '1.3.0',
    'major': '2.0.0',
  }.entries) {
    test('prepare ${entry.key} synchronizes version without publishing', () {
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
      expect(project, contains('MARKETING_VERSION = ${entry.value};'));
      expect(project, contains('CURRENT_PROJECT_VERSION = 10;'));
      expect(git(['show-ref']), before);
      expect(
        () => prepareRelease(repo, entry.key, apply: true),
        throwsStateError,
      );
    });
  }

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
    git(['branch', 'master']);
    git(['push', 'origin', 'master']);
    final previous = git(['rev-parse', 'master']);
    commit('next');
    git(['push', 'origin', 'develop']);
    final source = git(['rev-parse', 'develop']);
    publishRelease(repo, 'v1.0.0', publish: true);
    expect(git(['rev-parse', 'master^1']), previous);
    expect(git(['rev-parse', 'master^2']), source);
    expect(git(['rev-parse', 'v1.0.0^{}']), git(['rev-parse', 'master']));
  });

  test('rejects dirty tree, wrong version and unpushed develop', () {
    expect(() => publishRelease(repo, 'v1.0.1'), throwsStateError);
    File('$repo/dirty').writeAsStringSync('unfinished');
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
    commit('unpushed');
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
  });

  test('rejects mismatched extension and diverged local master', () {
    final project = File('$repo/ios/Runner.xcodeproj/project.pbxproj');
    project.writeAsStringSync(
      project.readAsStringSync().replaceAll('1.0.0;', '0.1.0;'),
    );
    commit('bad-extension');
    git(['push', 'origin', 'develop']);
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
    project.writeAsStringSync(
      project.readAsStringSync().replaceAll('0.1.0;', '1.0.0;'),
    );
    commit('fixed-extension');
    git(['push', 'origin', 'develop']);
    git(['branch', 'master']);
    expect(() => publishRelease(repo, 'v1.0.0'), throwsStateError);
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
