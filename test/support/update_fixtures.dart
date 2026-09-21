import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shiori/data/updates/update_http.dart';
import 'package:shiori/data/updates/update_manifest.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/contracts/cancellation.dart';
import 'package:shiori/domain/models/release_identity.dart';

final class UpdateFixtures {
  final Map<String, dynamic> vectors =
      jsonDecode(File('test/fixtures/updates/vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  UpdatePublicKey get key =>
      UpdatePublicKey.fromJson(vectors['publicKey'] as Map<String, dynamic>);
  Uint8List bytes(String field, {String name = 'valid'}) =>
      base64Decode(vectors['cases'][name][field] as String);
  Uint8List package(String platform) =>
      base64Decode(vectors['packages'][platform] as String);
  Map<String, dynamic> get manifest =>
      jsonDecode(utf8.decode(bytes('manifest'))) as Map<String, dynamic>;
  InstalledUpdateApp get installed => InstalledUpdateApp(
    version: '1.2.1',
    build: 10,
    availability: UpdateAvailability.enabled,
    release: ReleaseIdentity(
      tag: 'v1.2.1',
      version: '1.2.1',
      build: 10,
      commit: 'a' * 40,
    ),
  );
  Map<String, dynamic> get release {
    const tag = 'v1.2.1-beta.1';
    Map<String, dynamic> asset(String name, int size) => {
      'name': name,
      'size': size,
      'state': 'uploaded',
      'browser_download_url': releaseAsset(tag, name).toString(),
    };
    return {
      'tag_name': tag,
      'draft': false,
      'prerelease': true,
      'body': 'Notes <b>stay plain text</b>',
      'assets': [
        asset('update-manifest.json', bytes('manifest').length),
        asset('update-manifest.sig', 384),
        for (final entry in manifest['assets'] as List<dynamic>)
          asset(entry['name'] as String, entry['size'] as int),
      ],
    };
  }
}

class FixtureUpdateHttp implements UpdateHttp {
  FixtureUpdateHttp(this.fixtures) {
    releases = [fixtures.release];
  }
  final UpdateFixtures fixtures;
  late List<dynamic> releases;
  final reads = <Uri>[];
  final etags = <String?>[];
  bool notModified = false;
  bool tamper = false;
  bool overflow = false;
  bool closed = false;
  String? badCase;
  UpdateIssue? failure;
  @override
  Future<UpdateReply> read(
    Uri uri,
    CancellationToken token, {
    required int limit,
    String? etag,
  }) async {
    checkUpdateCancellation(token);
    reads.add(uri);
    etags.add(etag);
    if (failure case final error?) throw error;
    if (uri.host == 'api.github.com') {
      return UpdateReply(
        notModified
            ? Uint8List(0)
            : Uint8List.fromList(utf8.encode(jsonEncode(releases))),
        {'etag': '"fixture"'},
        notModified: notModified,
      );
    }
    return UpdateReply(
      fixtures.bytes(
        uri.path.endsWith('.sig') ? 'signature' : 'manifest',
        name: badCase ?? 'valid',
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
  }) async {
    final bytes = fixtures.package(
      uri.path.endsWith('.apk') ? 'android' : 'windows-x64',
    );
    if (tamper) bytes[0] ^= 1;
    await chunk(bytes.sublist(0, 12));
    checkUpdateCancellation(token);
    await chunk(bytes.sublist(12));
    if (overflow) await chunk([0]);
    checkUpdateCancellation(token);
  }

  @override
  void close() {
    closed = true;
  }
}
