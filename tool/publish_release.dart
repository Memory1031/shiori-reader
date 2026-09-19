import 'dart:io';

/// Preview by default. Publishing requires an explicit --publish argument.
void main(List<String> args) {
  const usage =
      'dart tool/publish_release.dart v1.0.0 [--publish]\n'
      'dart tool/publish_release.dart v1.0.0-beta.1 [--publish]\n'
      'dart tool/publish_release.dart prepare beta|patch|minor|major [--apply]';
  if (args.contains('--help')) {
    stdout.writeln(usage);
    return;
  }
  try {
    if (args.isNotEmpty && args.first == 'prepare') {
      if (args.length < 2 ||
          args.length > 3 ||
          (args.length == 3 && args[2] != '--apply')) {
        throw StateError(usage);
      }
      prepareRelease(
        Directory.current.path,
        args[1],
        apply: args.contains('--apply'),
      );
      return;
    }
    if (args.isEmpty ||
        args.length > 2 ||
        (args.length == 2 && args[1] != '--publish')) {
      throw StateError(usage);
    }
    publishRelease(
      Directory.current.path,
      args.first,
      publish: args.contains('--publish'),
    );
  } on Object catch (error) {
    stderr.writeln(error);
    stderr.writeln(
      'Stopped. No reset or automatic conflict resolution was performed. Inspect local branches and tags before retrying.',
    );
    exitCode = 1;
  }
}

void publishRelease(String directory, String tag, {bool publish = false}) {
  String git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: directory);
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed:\n${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  bool exists(String ref) =>
      Process.runSync('git', [
        'show-ref',
        '--verify',
        '--quiet',
        ref,
      ], workingDirectory: directory).exitCode ==
      0;

  final tagVersion = RegExp(
    r'^v(\d+\.\d+\.\d+)(?:-beta\.([1-9]\d*))?$',
  ).firstMatch(tag);
  if (tagVersion == null) {
    throw StateError('Expected vX.Y.Z or vX.Y.Z-beta.N');
  }
  final beta = tagVersion[2] != null;
  directory = git(['rev-parse', '--show-toplevel']);
  if (git(['status', '--porcelain']).isNotEmpty) {
    throw StateError(
      'Commit or otherwise finish all tracked/untracked changes first.',
    );
  }
  if (git(['branch', '--show-current']) != 'develop') {
    throw StateError('Run this script on develop.');
  }
  final source = git(['rev-parse', 'refs/heads/develop']);
  final pubspec = git(['show', '$source:pubspec.yaml']);
  final version = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (version == null ||
      version[1] != tagVersion[1] ||
      int.parse(version[2]!) > 2100000000) {
    throw StateError(
      'Tag must match the committed pubspec version and a valid build number.',
    );
  }
  final project = git(['show', '$source:ios/Runner.xcodeproj/project.pbxproj']);
  final extensions = RegExp(r'buildSettings = \{([^}]+)\};')
      .allMatches(project)
      .where(
        (match) =>
            match[1]!.contains('INFOPLIST_FILE = ShareExtension/Info.plist;'),
      );
  if (extensions.isEmpty ||
      extensions.any(
        (match) =>
            !match[1]!.contains('MARKETING_VERSION = ${version[1]};') ||
            !match[1]!.contains('CURRENT_PROJECT_VERSION = ${version[2]};'),
      )) {
    throw StateError(
      'ShareExtension version/build must match pubspec in every configuration.',
    );
  }
  final remote = git([
    'ls-remote',
    'origin',
    'refs/heads/develop',
    'refs/heads/master',
    'refs/tags/$tag',
    'refs/tags/$tag^{}',
  ]);
  final refs = <String, String>{
    for (final line in remote.split('\n').where((line) => line.isNotEmpty))
      line.split(RegExp(r'\s+'))[1]: line.split(RegExp(r'\s+'))[0],
  };
  if (refs['refs/heads/develop'] != source) {
    throw StateError(
      'Local develop must equal origin/develop. Push completed changes or synchronize first.',
    );
  }
  if (exists('refs/tags/$tag') || refs.containsKey('refs/tags/$tag')) {
    throw StateError('Tag $tag already exists; tags are never overwritten.');
  }
  if (beta) {
    stdout.writeln(
      'develop: $source\nbeta: $tag\ninternal build: ${version[2]}\n'
      'Plan: annotated beta tag on develop; push tag for all platforms.',
    );
    if (!publish) {
      stdout.writeln(
        'Preview only; use --publish to execute. No refs changed.',
      );
      return;
    }
    git([
      'fetch',
      '--no-tags',
      'origin',
      '+refs/heads/develop:refs/remotes/origin/develop',
    ]);
    if (git(['rev-parse', 'refs/remotes/origin/develop']) != source) {
      throw StateError('Remote develop changed during preparation; run again.');
    }
    git(['tag', '-a', tag, source, '-m', 'Beta $tag']);
    git(['push', 'origin', 'refs/tags/$tag:refs/tags/$tag']);
    stdout.writeln(
      'Published $tag at $source. Platform beta workflows will run.',
    );
    return;
  }
  final master = refs['refs/heads/master'];
  if (exists('refs/heads/master') &&
      git(['rev-parse', 'refs/heads/master']) != master) {
    throw StateError(
      'Local master differs from origin/master; reconcile it manually first.',
    );
  }
  stdout.writeln(
    'develop: $source\nmaster: ${master ?? '(first release)'}\nrelease: $tag\ninternal build: ${version[2]}',
  );
  stdout.writeln(
    'Plan: ${master == null ? 'create master from develop' : 'merge develop into master (fast-forward when possible)'}; annotated tag on master; atomic push master + tag.',
  );
  if (!publish) {
    stdout.writeln('Preview only; use --publish to execute. No refs changed.');
    return;
  }
  git([
    'fetch',
    '--no-tags',
    'origin',
    '+refs/heads/develop:refs/remotes/origin/develop',
    if (master != null) '+refs/heads/master:refs/remotes/origin/master',
  ]);
  if (git(['rev-parse', 'refs/remotes/origin/develop']) != source ||
      (master != null &&
          git(['rev-parse', 'refs/remotes/origin/master']) != master)) {
    throw StateError('Remote branches changed during preparation; run again.');
  }
  if (exists('refs/heads/master')) {
    git(['switch', 'master']);
  } else {
    git(['switch', '-c', 'master', master ?? source]);
  }
  if (master != null) {
    git([
      'merge',
      '--ff',
      source,
      '-m',
      'chore: release $tag\n\n- Merge develop into master for release',
    ]);
  }
  // Validate the merged tree, not just the source branch: master-only changes
  // must not silently alter the version used by the release workflow.
  if (git(['show', 'HEAD:pubspec.yaml']) != pubspec ||
      git(['show', 'HEAD:ios/Runner.xcodeproj/project.pbxproj']) != project) {
    throw StateError(
      'Merged version configuration differs from develop. Review master before tagging.',
    );
  }
  git(['tag', '-a', tag, '-m', 'Release $tag']);
  // Explicit expected master prevents publishing over a concurrent update.
  // No force update is allowed: the merge above must retain the old master.
  if (master != null) git(['merge-base', '--is-ancestor', master, 'master']);
  git([
    'push',
    '--atomic',
    '--force-with-lease=refs/heads/master:${master ?? ''}',
    'origin',
    'refs/heads/master:refs/heads/master',
    'refs/tags/$tag:refs/tags/$tag',
  ]);
  stdout.writeln(
    'Published $tag at ${git(['rev-parse', 'HEAD'])}. Platform release workflows will run.',
  );
  git(['switch', 'develop']);
}

/// Prepare a reviewable version change; never commits, tags or pushes.
String prepareRelease(
  String directory,
  String increment, {
  bool apply = false,
}) {
  if (!['beta', 'patch', 'minor', 'major'].contains(increment)) {
    throw StateError('Expected beta, patch, minor or major.');
  }
  String git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: directory);
    if (result.exitCode != 0) throw StateError('git failed: ${result.stderr}');
    return (result.stdout as String).trim();
  }

  directory = git(['rev-parse', '--show-toplevel']);
  if (git(['branch', '--show-current']) != 'develop' ||
      git(['status', '--porcelain']).isNotEmpty) {
    throw StateError('Prepare versions on a clean develop branch.');
  }
  final pubspec = File('$directory/pubspec.yaml');
  final original = pubspec.readAsStringSync();
  final pattern = RegExp(
    r'^version: *(\d+)\.(\d+)\.(\d+)\+([1-9]\d*)',
    multiLine: true,
  );
  final match = pattern.firstMatch(original);
  if (match == null ||
      pattern.allMatches(original).length != 1 ||
      original.substring(match.end).split('\n').first.trim().isNotEmpty) {
    throw StateError(
      'Expected one stable pubspec version with a build number.',
    );
  }
  final parts = [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
  if (increment != 'beta') {
    final index = {'major': 0, 'minor': 1, 'patch': 2}[increment]!;
    parts[index]++;
    for (var i = index + 1; i < 3; i++) {
      parts[i] = 0;
    }
  }
  final next = parts.join('.');
  final build = int.parse(match[4]!) + 1;
  if (build > 2100000000) throw StateError('Build number limit reached.');
  var tag = 'v$next';
  if (increment == 'beta') {
    // Beta sequence is per app version; the platform build number is global.
    final candidates = [
      ...git(['tag', '--list', 'v$next-beta.*']).split('\n'),
      ...git(['ls-remote', '--tags', 'origin', 'refs/tags/v$next-beta.*'])
          .split('\n')
          .where((line) => line.isNotEmpty)
          .map((line) => line.split(RegExp(r'\s+')).last),
    ];
    final pattern = RegExp(
      '^(?:refs/tags/)?v${RegExp.escape(next)}-beta\\.([1-9]\\d*)\$',
    );
    var highest = 0;
    for (final candidate in candidates) {
      final found = pattern.firstMatch(candidate);
      if (found == null) continue;
      final sequence = int.parse(found[1]!);
      if (sequence > highest) highest = sequence;
    }
    tag = 'v$next-beta.${highest + 1}';
  }
  final project = File('$directory/ios/Runner.xcodeproj/project.pbxproj');
  final projectOriginal = project.readAsStringSync();
  var count = 0;
  final updated = projectOriginal.replaceAllMapped(
    RegExp(r'buildSettings = \{([^}]+)\};'),
    (block) {
      if (!block[1]!.contains('INFOPLIST_FILE = ShareExtension/Info.plist;')) {
        return block[0]!;
      }
      count++;
      final marketing = RegExp(r'MARKETING_VERSION = [^;]+;');
      final number = RegExp(r'CURRENT_PROJECT_VERSION = [^;]+;');
      if (marketing.allMatches(block[0]!).length != 1 ||
          number.allMatches(block[0]!).length != 1) {
        throw StateError('Invalid ShareExtension version configuration.');
      }
      return block[0]!
          .replaceAll(marketing, 'MARKETING_VERSION = $next;')
          .replaceAll(number, 'CURRENT_PROJECT_VERSION = $build;');
    },
  );
  if (count == 0) throw StateError('ShareExtension configuration missing.');
  stdout.writeln(
    'Version: ${match[1]}.${match[2]}.${match[3]} -> $next\nInternal build: ${match[4]} -> $build\nRelease tag: $tag',
  );
  if (apply) {
    pubspec.writeAsStringSync(
      original.replaceRange(match.start, match.end, 'version: $next+$build'),
    );
    project.writeAsStringSync(updated);
    stdout.writeln(
      'Prepared $tag. Review, commit and push develop; after CI passes run:\ndart tool/publish_release.dart $tag --publish',
    );
  } else {
    stdout.writeln('Preview only. Add --apply to update version files.');
  }
  return next;
}
