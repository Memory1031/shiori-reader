import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/github_update_repository.dart';
import 'package:shiori/data/updates/update_http.dart';
import 'package:shiori/data/updates/update_manifest.dart';
import 'package:shiori/data/updates/update_storage.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/contracts/cancellation.dart';
import 'package:shiori/domain/models/release_identity.dart';

class MacFeed implements UpdateHttp {
  final fixture =
      jsonDecode(File('test/fixtures/updates/macos.json').readAsStringSync())
          as Map<String, dynamic>;
  final requests = <Uri>[];
  Uint8List bytes(String field) =>
      base64Decode(fixture['cases']['valid'][field] as String);
  @override
  Future<UpdateReply> read(
    Uri uri,
    CancellationToken token, {
    required int limit,
    String? etag,
  }) async {
    requests.add(uri);
    if (uri.host != 'api.github.com') {
      return UpdateReply(
        bytes(uri.path.endsWith('.sig') ? 'signature' : 'manifest'),
        {},
      );
    }
    final manifest =
        jsonDecode(utf8.decode(bytes('manifest'))) as Map<String, dynamic>;
    final asset = manifest['assets'][0] as Map<String, dynamic>;
    Map<String, dynamic> entry(String name, int size) => {
      'name': name,
      'size': size,
      'state': 'uploaded',
      'browser_download_url': releaseAsset('v1.3.2', name).toString(),
    };
    return UpdateReply(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode([
            {
              'tag_name': 'v1.3.2',
              'draft': false,
              'prerelease': false,
              'body': 'macOS update',
              'assets': [
                entry(
                  'update-manifest.json',
                  123,
                ), // Other platforms keep their own protocol.
                entry('update-manifest-macos.json', bytes('manifest').length),
                entry('update-manifest-macos.sig', 384),
                entry(asset['name'] as String, asset['size'] as int),
              ],
            },
          ]),
        ),
      ),
      {},
    );
  }

  @override
  Future<void> download(
    Uri uri,
    CancellationToken token, {
    required int limit,
    required Future<void> Function(List<int>) chunk,
  }) => throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  test('GitHub lookup selects only the separate signed macOS feed', () async {
    final temp = await Directory.systemTemp.createTemp('shiori-mac-feed-');
    final http = MacFeed();
    final repository = GithubUpdateRepository(
      installed: InstalledUpdateApp(
        version: '1.3.1',
        build: 19,
        availability: UpdateAvailability.enabled,
        release: ReleaseIdentity(
          tag: 'v1.3.1',
          version: '1.3.1',
          build: 19,
          commit: 'a' * 40,
        ),
      ),
      platform: 'macos-universal',
      key: UpdatePublicKey.fromJson(
        http.fixture['publicKey'] as Map<String, dynamic>,
      ),
      http: http,
      storage: UpdateStorage(
        directory: temp,
        preferencesFile: File('${temp.path}/preferences.json'),
      ),
    );
    try {
      final candidate = await repository.check(
        UpdateChannel.stable,
        CancellationSource().token,
      );
      expect(candidate!.release.build, 20);
      expect(
        http.requests
            .where((u) => u.host != 'api.github.com')
            .map((u) => u.pathSegments.last),
        ['update-manifest-macos.json', 'update-manifest-macos.sig'],
      );
    } finally {
      await repository.close();
      await temp.delete(recursive: true);
    }
  });
}
