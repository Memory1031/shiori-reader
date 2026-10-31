import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/github_update_repository.dart';
import 'package:shiori/data/updates/update_storage.dart';
import 'package:shiori/data/updates/update_installer.dart';
import 'package:shiori/data/updates/update_manifest.dart';
import 'package:shiori/data/updates/update_http.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/contracts/cancellation.dart';
import 'package:shiori/domain/models/release_identity.dart';

import '../support/update_fixtures.dart';

void main() {
  final fixture = UpdateFixtures();
  late Directory temp;
  late FixtureUpdateHttp http;
  late UpdateStorage storage;
  late GithubUpdateRepository repo;
  CancellationToken token() => CancellationSource().token;
  Matcher issue(UpdateProblem problem) =>
      isA<UpdateIssue>().having((e) => e.problem, 'problem', problem);
  GithubUpdateRepository repository({
    String? platform = 'windows-x64-portable',
    InstalledUpdateApp? installed,
    UpdateInstaller? installer,
  }) => GithubUpdateRepository(
    installed: installed ?? fixture.installed,
    platform: platform,
    key: fixture.key,
    http: http,
    storage: storage,
    installer: installer,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shiori-updates-');
    http = FixtureUpdateHttp(fixture);
    storage = UpdateStorage(
      directory: Directory('${temp.path}/updates'),
      preferencesFile: File('${temp.path}/preferences.json'),
    );
    repo = repository();
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });
  test(
    'verification starts after stream return and closed file, before publication',
    () async {
      final target = (await repo.check(UpdateChannel.beta, token()))!;
      final atEnd = Completer<void>();
      final releaseStream = Completer<void>();
      var streamReturned = false;
      var verifications = 0;
      http.finishDownload = () async {
        atEnd.complete();
        await releaseStream.future;
        streamReturned = true;
      };
      final download = repo.download(
        target,
        token(),
        (received) {
          expect(streamReturned, isFalse);
          expect(verifications, 0);
        },
        onVerifying: () {
          verifications++;
          expect(streamReturned, isTrue);
          final part = storage.file('package.part');
          expect(
            part.readAsBytesSync(),
            fixture.package('windows-x64-portable'),
          );
          expect(storage.file('package.bin').existsSync(), isFalse);
          // Windows rejects renaming a file still held by RandomAccessFile.
          final moved = part.renameSync(storage.file('closed.part').path);
          moved.renameSync(part.path);
        },
      );
      await atEnd.future;
      expect(verifications, 0);
      releaseStream.complete();
      await download;
      expect(verifications, 1);
      expect(await storage.file('package.bin').exists(), isTrue);
      expect(await storage.file('package.part').exists(), isFalse);
    },
  );

  test('cancellation on final bytes never emits verification', () async {
    final target = (await repo.check(UpdateChannel.beta, token()))!;
    final source = CancellationSource();
    var verifications = 0;
    await expectLater(
      repo.download(target, source.token, (received) {
        if (received == target.bytes) source.cancel();
      }, onVerifying: () => verifications++),
      throwsA(issue(UpdateProblem.cancelled)),
    );
    expect(verifications, 0);
    expect(await storage.file('package.part').exists(), isFalse);
    expect(await storage.file('package.bin').exists(), isFalse);
  });

  test('cancel at verification start cleans temporary package', () async {
    final target = (await repo.check(UpdateChannel.beta, token()))!;
    final source = CancellationSource();
    await expectLater(
      repo.download(target, source.token, (_) {}, onVerifying: source.cancel),
      throwsA(issue(UpdateProblem.cancelled)),
    );
    expect(await storage.file('package.part').exists(), isFalse);
    expect(await storage.file('package.bin').exists(), isFalse);
  });
  test(
    'handoff rechecks bytes; only signed APK metadata reaches native code',
    () async {
      final installer = _Installer();
      repo = repository(platform: 'android', installer: installer);
      final target = (await repo.check(UpdateChannel.beta, token()))!;
      await repo.download(target, token(), (_) {});
      expect(
        await repo.install(target, token()),
        UpdateInstallState.installing,
      );
      expect(installer.calls, 1);
      expect(installer.release, target.release);
      expect(installer.asset?.certificateSha256, isNotEmpty);
      await storage
          .file('package.bin')
          .writeAsBytes(List.filled(target.bytes, 0));
      await expectLater(
        repo.install(target, token()),
        throwsA(issue(UpdateProblem.packageInvalid)),
      );
      expect(installer.calls, 1);
    },
  );
  test('actual installed build cleans only obsolete download files', () async {
    final target = (await repo.check(UpdateChannel.beta, token()))!;
    await repo.download(target, token(), (_) {});
    await storage.file('unrelated').writeAsString('keep');
    final upgraded = repository(
      installed: InstalledUpdateApp(
        version: target.release.version,
        build: target.release.build,
        availability: UpdateAvailability.enabled,
        release: target.release,
      ),
    );
    expect(await upgraded.restore(UpdateChannel.beta, token()), isNull);
    expect(await storage.file('package.bin').exists(), isFalse);
    expect(await storage.file('download.json').exists(), isFalse);
    expect(await storage.file('unrelated').readAsString(), 'keep');
    await upgraded.close();
  });
  test(
    'retired download cache is discarded without touching preferences',
    () async {
      final target = (await repo.check(UpdateChannel.beta, token()))!;
      await repo.download(target, token(), (_) {});
      final record =
          jsonDecode(await storage.file('download.json').readAsString())
              as Map<String, dynamic>;
      record['schema'] = 1;
      record.remove('platform');
      await UpdateStorage.writeJson(storage.file('download.json'), record);
      await storage
          .file('package.part')
          .writeAsString('unfinished old download');
      await storage.file('unrelated').writeAsString('keep');
      const preferences = UpdatePreferences(
        channel: UpdateChannel.beta,
        automatic: false,
      );
      await repo.savePreferences(preferences);
      expect(await repo.restore(UpdateChannel.beta, token()), isNull);
      expect(await repo.loadPreferences(), preferences);
      for (final name in ['download.json', 'package.part', 'package.bin']) {
        expect(await storage.file(name).exists(), isFalse);
      }
      expect(await storage.file('unrelated').readAsString(), 'keep');
      expect(
        (await repo.check(UpdateChannel.beta, token()))?.release,
        target.release,
      );
    },
  );
  for (final record in [
    '{"schema":1}',
    '{"schema":999}',
    'broken JSON',
    '{"schema":1,"tag":"v1.4.0","notes":"","manifest":"bad","signature":"bad"}',
  ]) {
    test('unknown or damaged cache is retained: $record', () async {
      await storage.prepare();
      await storage.file('download.json').writeAsString(record);
      await storage.file('package.bin').writeAsString('keep package');
      await storage.file('package.part').writeAsString('keep partial');
      await expectLater(
        repo.restore(UpdateChannel.beta, token()),
        throwsA(issue(UpdateProblem.verification)),
      );
      expect(await storage.file('download.json').readAsString(), record);
      expect(await storage.file('package.bin').readAsString(), 'keep package');
      expect(await storage.file('package.part').readAsString(), 'keep partial');
    });
  }
  for (final damage in ['duplicate schema', 'signature', 'tag']) {
    test(
      'recognizable but damaged legacy cache is retained: $damage',
      () async {
        final target = (await repo.check(UpdateChannel.beta, token()))!;
        await repo.download(target, token(), (_) {});
        final record =
            jsonDecode(await storage.file('download.json').readAsString())
                as Map<String, dynamic>;
        record['schema'] = 1;
        record.remove('platform');
        if (damage == 'signature') {
          record['signature'] = base64Encode(List.filled(384, 0));
        }
        if (damage == 'tag') record['tag'] = 'v9.9.9';
        var text = jsonEncode(record);
        if (damage == 'duplicate schema') {
          text = text.replaceFirst('{', '{"schema":999,');
        }
        await storage.file('download.json').writeAsString(text);
        await expectLater(
          repo.restore(UpdateChannel.beta, token()),
          throwsA(issue(UpdateProblem.verification)),
        );
        expect(await storage.file('download.json').readAsString(), text);
        expect(
          await storage.file('package.bin').readAsBytes(),
          fixture.package('windows-x64-portable'),
        );
      },
    );
  }
  test(
    'nine signed releases retain the highest verified upgrade within budget',
    () async {
      http.releases = [
        for (var i = 2; i <= 10; i++) fixture.releaseFor('beta$i'),
      ];
      for (var i = 2; i <= 10; i++) {
        http.casesByTag['v1.2.1-beta.$i'] = 'beta$i';
      }
      final target = await repo.check(UpdateChannel.beta, token());
      expect(target?.release.tag, 'v1.2.1-beta.9');
      expect(
        http.reads
            .where((uri) => uri.path.endsWith('shiori-update.json'))
            .length,
        8,
      );
      expect(http.reads.length, 9);
      await repo.download(target!, token(), (_) {});
    },
  );
  test(
    'three full pages retain an upgrade verified on the first page',
    () async {
      http.pages = [
        [
          fixture.release,
          ...List.generate(19, (_) => {'draft': true}),
        ],
        List.generate(20, (_) => {'draft': true}),
        List.generate(20, (_) => {'draft': true}),
      ];
      expect(
        (await repo.check(UpdateChannel.beta, token()))?.release.build,
        11,
      );
      expect(http.reads.where((uri) => uri.host == 'api.github.com').length, 3);
    },
  );
  test(
    'an older legacy release cannot hide a verified signed update',
    () async {
      http.releases.add({
        'tag_name': 'v1.2.1-beta.0',
        'draft': false,
        'prerelease': true,
        'assets': [],
      });
      http.releases.add({
        'tag_name': 'v1.2.1-beta.2',
        'draft': false,
        'prerelease': true,
        'assets': [],
      });
      expect(
        (await repo.check(UpdateChannel.beta, token()))?.release.build,
        11,
      );
    },
  );

  test(
    'stable excludes beta; beta verifies identity and complete asset binding',
    () async {
      expect(await repo.check(UpdateChannel.stable, token()), isNull);
      expect(http.reads.length, 1);
      final candidate = await repo.check(UpdateChannel.beta, token());
      expect(candidate!.release.build, 11);
      expect(candidate.notes, contains('<b>'));
      expect(
        candidate.page.toString(),
        'https://github.com/Memory1031/shiori-reader/releases/tag/v1.2.1-beta.1',
      );
      expect(http.etags[1], '"fixture"');
      http.notModified = true;
      expect(await repo.check(UpdateChannel.beta, token()), candidate);
    },
  );

  for (final platform in [
    'windows-x64-portable',
    'windows-x64-setup',
    'android',
    'macos-universal',
  ]) {
    test(
      '$platform downloaded package survives restart and is reverified',
      () async {
        repo = repository(platform: platform);
        final candidate = (await repo.check(UpdateChannel.beta, token()))!;
        var received = 0;
        await repo.download(candidate, token(), (value) => received = value);
        expect(received, candidate.bytes);
        expect(await storage.file('package.part').exists(), isFalse);
        final reopened = repository(platform: platform);
        expect(await reopened.restore(UpdateChannel.beta, token()), candidate);
        expect(await reopened.restore(UpdateChannel.stable, token()), isNull);
        await storage
            .file('package.bin')
            .writeAsBytes(List.filled(candidate.bytes, 0));
        await expectLater(
          reopened.restore(UpdateChannel.beta, token()),
          throwsA(issue(UpdateProblem.verification)),
        );
      },
    );
  }

  test(
    'cancel stops download and removes partial file; restart never marks it ready',
    () async {
      final candidate = (await repo.check(UpdateChannel.beta, token()))!;
      final cancellation = CancellationSource();
      await expectLater(
        repo.download(
          candidate,
          cancellation.token,
          (_) => cancellation.cancel(),
        ),
        throwsA(issue(UpdateProblem.cancelled)),
      );
      expect(await storage.file('package.part').exists(), isFalse);
      expect(await storage.file('package.bin').exists(), isFalse);
      await storage.file('package.part').writeAsString('interrupted download');
      expect(await repository().restore(UpdateChannel.beta, token()), isNull);
      expect(await storage.file('package.part').exists(), isFalse);
    },
  );

  test('download refuses wrong digest and excess bytes', () async {
    final candidate = (await repo.check(UpdateChannel.beta, token()))!;
    http.tamper = true;
    await expectLater(
      repo.download(candidate, token(), (_) {}),
      throwsA(issue(UpdateProblem.verification)),
    );
    expect(await storage.file('package.bin').exists(), isFalse);
    http.tamper = false;
    http.overflow = true;
    await expectLater(
      repo.download(candidate, token(), (_) {}),
      throwsA(issue(UpdateProblem.verification)),
    );
    expect(await storage.file('package.part').exists(), isFalse);
  });

  test('invalid signed manifests and foreign asset URLs are refused', () async {
    http.badCase = 'wrongApp';
    await expectLater(
      repo.check(UpdateChannel.beta, token()),
      throwsA(issue(UpdateProblem.verification)),
    );
    http.badCase = null;
    (http.releases.first['assets'] as List).first['browser_download_url'] =
        'https://evil.example/manifest';
    await expectLater(
      repo.check(UpdateChannel.beta, token()),
      throwsA(issue(UpdateProblem.verification)),
    );
  });

  test(
    'incomplete releases and truncated scans never report up to date',
    () async {
      (http.releases.first['assets'] as List).removeAt(1);
      await expectLater(
        repo.check(UpdateChannel.beta, token()),
        throwsA(issue(UpdateProblem.incomplete)),
      );
      http.releases = List.generate(20, (_) => {'draft': true});
      final initial = http.reads.length;
      await expectLater(
        repo.check(UpdateChannel.beta, token()),
        throwsA(issue(UpdateProblem.incomplete)),
      );
      expect(http.reads.length - initial, 3);
    },
  );

  test('network and rate limit errors are surfaced without retries', () async {
    http.failure = const UpdateIssue(UpdateProblem.network);
    await expectLater(
      repo.check(UpdateChannel.beta, token()),
      throwsA(issue(UpdateProblem.network)),
    );
    expect(http.reads.length, 1);
    http.failure = UpdateIssue(
      UpdateProblem.rateLimited,
      retryAt: DateTime.utc(2030),
    );
    await expectLater(
      repo.check(UpdateChannel.beta, token()),
      throwsA(issue(UpdateProblem.rateLimited)),
    );
    expect(http.reads.length, 2);
  });

  test('development installation makes no requests', () async {
    repo = repository(
      installed: const InstalledUpdateApp(
        version: '1.2.1',
        build: 10,
        availability: UpdateAvailability.development,
      ),
    );
    expect(await repo.check(UpdateChannel.beta, token()), isNull);
    expect(await repo.restore(UpdateChannel.beta, token()), isNull);
    expect(http.reads, isEmpty);
  });

  InstalledUpdateApp iosInstalled(DistributionChannel distribution) =>
      InstalledUpdateApp(
        version: fixture.installed.version,
        build: fixture.installed.build,
        release: fixture.installed.release,
        availability: UpdateAvailability.enabled,
        installation: AppInstallation(
          kind: AppInstallationKind.iosApp,
          distribution: distribution,
        ),
      );
  void addIpa(Map<String, dynamic> release) {
    final tag = release['tag_name'] as String;
    final name = 'shiori-reader-$tag-ios-arm64-unsigned.ipa';
    (release['assets'] as List).add({
      'name': name,
      'size': 4096,
      'state': 'uploaded',
      'browser_download_url': releaseAsset(tag, name).toString(),
    });
  }

  test(
    'direct iOS verifies releases without offering a downloadable package',
    () async {
      repo = repository(
        installed: iosInstalled(DistributionChannel.direct),
        platform: null,
      );
      http.releases = [fixture.releaseFor('beta2'), fixture.release];
      http.casesByTag['v1.2.1-beta.2'] = 'beta2';
      for (final release in http.releases) {
        addIpa(release as Map<String, dynamic>);
      }
      expect(await repo.check(UpdateChannel.stable, token()), isNull);
      final candidate = (await repo.check(UpdateChannel.beta, token()))!;
      expect(candidate.release.build, 12);
      expect(candidate.bytes, 4096);
      expect(candidate.page, releasePage('v1.2.1-beta.2'));
      expect(candidate.notes, contains('Notes'));
      expect(await repo.restore(UpdateChannel.beta, token()), isNull);
      await expectLater(
        repo.download(candidate, token(), (_) {}),
        throwsA(issue(UpdateProblem.verification)),
      );
      await expectLater(
        repo.install(candidate, token()),
        throwsA(issue(UpdateProblem.verification)),
      );
      expect(http.reads.any((uri) => uri.path.endsWith('.ipa')), isFalse);
      expect(storage.file('package.bin').existsSync(), isFalse);
      expect(storage.file('download.json').existsSync(), isFalse);
    },
  );

  test(
    'iOS checks require a complete IPA release and valid signed identity',
    () async {
      repo = repository(
        installed: iosInstalled(DistributionChannel.direct),
        platform: 'ios-arm64',
      );
      await expectLater(
        repo.check(UpdateChannel.beta, token()),
        throwsA(issue(UpdateProblem.incomplete)),
      );
      addIpa(http.releases.first as Map<String, dynamic>);
      final ipa = (http.releases.first['assets'] as List).last as Map;
      final url = ipa['browser_download_url'];
      ipa['browser_download_url'] = 'https://example.com/unsigned.ipa';
      await expectLater(
        repo.check(UpdateChannel.beta, token()),
        throwsA(issue(UpdateProblem.verification)),
      );
      ipa['browser_download_url'] = url;
      http.badCase = 'wrongApp';
      await expectLater(
        repo.check(UpdateChannel.beta, token()),
        throwsA(issue(UpdateProblem.verification)),
      );
    },
  );

  test('TestFlight and unknown iOS builds never query GitHub', () async {
    for (final distribution in [
      DistributionChannel.testFlight,
      DistributionChannel.unknown,
    ]) {
      repo = repository(
        installed: iosInstalled(distribution),
        platform: 'ios-arm64',
      );
      expect(await repo.check(UpdateChannel.beta, token()), isNull);
      expect(await repo.restore(UpdateChannel.beta, token()), isNull);
    }
    expect(http.reads, isEmpty);
  });

  test('settings persist independently; unknown schema is retained', () async {
    final settings = UpdatePreferences(
      channel: UpdateChannel.beta,
      automatic: false,
      lastAttempt: DateTime.utc(2030),
      lastChecked: DateTime.utc(2029),
      retryAt: DateTime.utc(2031),
    );
    await repo.savePreferences(settings);
    expect(await repository().loadPreferences(), settings);
    await storage.preferencesFile.writeAsString(jsonEncode({'schema': 999}));
    await expectLater(
      repo.loadPreferences(),
      throwsA(issue(UpdateProblem.verification)),
    );
    expect(
      jsonDecode(await storage.preferencesFile.readAsString())['schema'],
      999,
    );
  });
}

class _Installer implements UpdateInstaller {
  int calls = 0;
  ReleaseIdentity? release;
  UpdateAsset? asset;
  @override
  Future<UpdateInstallState> status() async => UpdateInstallState.idle;
  @override
  Future<void> openSettings() async {}
  @override
  Future<UpdateInstallState> install(
    File package,
    ReleaseIdentity release,
    UpdateAsset asset,
    Uint8List manifest,
    Uint8List signature,
  ) async {
    calls++;
    this.release = release;
    this.asset = asset;
    return UpdateInstallState.installing;
  }
}
