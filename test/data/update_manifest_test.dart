import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/update_manifest.dart';
import 'package:shiori/domain/models/release_identity.dart';

void main() {
  final vectors =
      jsonDecode(File('test/fixtures/updates/vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final key = UpdatePublicKey.fromJson(
    vectors['publicKey'] as Map<String, dynamic>,
  );
  final cases = vectors['cases'] as Map<String, dynamic>;
  Uint8List bytes(String name, String field) =>
      base64Decode(cases[name][field] as String);

  test('OpenSSL signed manifest verifies in Dart and models are immutable', () {
    final manifest = UpdateManifest.verifyAndRead(
      bytes('valid', 'manifest'),
      bytes('valid', 'signature'),
      key,
      expectedTag: 'v1.2.1-beta.1',
    );
    expect(manifest.identity.build, 11);
    expect(manifest.identity.channel, UpdateChannel.beta);
    expect(manifest.assets.length, 2);
    expect(() => manifest.assets.clear(), throwsUnsupportedError);
    expect(() => manifest.assets.last.files.clear(), throwsUnsupportedError);
  });

  for (var number = 2; number <= 10; number++) {
    test('verifies signed release history beta.$number', () {
      final manifest = UpdateManifest.verifyAndRead(
        bytes('beta$number', 'manifest'),
        bytes('beta$number', 'signature'),
        key,
        expectedTag: 'v1.2.1-beta.$number',
      );
      expect(manifest.identity.build, 10 + number);
    });
  }
  for (final name in cases.keys.where(
    (name) => name != 'valid' && !name.startsWith('beta'),
  )) {
    test('rejects signed but invalid manifest: $name', () {
      expect(
        () => UpdateManifest.verifyAndRead(
          bytes(name, 'manifest'),
          bytes(name, 'signature'),
          key,
          expectedTag: 'v1.2.1-beta.1',
        ),
        throwsFormatException,
      );
    });
  }

  test(
    'rejects tampered payload, signature, replay under another tag and oversized input',
    () {
      final payload = bytes('valid', 'manifest');
      final signature = bytes('valid', 'signature');
      payload[0] ^= 1;
      expect(key.verify(payload, signature), isFalse);
      payload[0] ^= 1;
      signature[0] ^= 1;
      expect(key.verify(payload, signature), isFalse);
      expect(
        key.verify(Uint8List(maxUpdateManifestBytes + 1), signature),
        isFalse,
      );
      expect(key.verify(payload, Uint8List(1)), isFalse);
      expect(
        () => UpdateManifest.verifyAndRead(
          payload,
          bytes('valid', 'signature'),
          key,
          expectedTag: 'v1.2.1-beta.2',
        ),
        throwsFormatException,
      );
    },
  );

  test('release channels use numeric base versions and global builds', () {
    ReleaseIdentity release(String tag, int build) => ReleaseIdentity(
      tag: tag,
      version: tag.substring(1).split('-').first,
      build: build,
      commit: 'a' * 40,
    );
    final current = release('v1.2.1-beta.1', 11);
    expect(
      release('v1.2.1-beta.2', 12).canReplace(current, UpdateChannel.beta),
      isTrue,
    );
    expect(
      release('v1.2.1-beta.2', 12).canReplace(current, UpdateChannel.stable),
      isFalse,
    );
    expect(
      release('v1.2.1', 12).canReplace(current, UpdateChannel.stable),
      isTrue,
    );
    expect(
      release('v1.2.1', 10).canReplace(current, UpdateChannel.stable),
      isFalse,
    );
    expect(
      release('v1.2.1', 11).canReplace(current, UpdateChannel.beta),
      isFalse,
    );
    expect(
      release('v1.1.9', 12).canReplace(current, UpdateChannel.beta),
      isFalse,
    );
    expect(
      release('v1.10.0-beta.1', 12).canReplace(current, UpdateChannel.beta),
      isTrue,
    );
  });

  test('build identity is cross-checked against installed version', () {
    expect(
      BundledRelease.fromJson({'schemaVersion': 1, 'development': true}),
      isNull,
    );
    final manifest =
        jsonDecode(utf8.decode(bytes('valid', 'manifest')))
            as Map<String, dynamic>;
    final bundled = BundledRelease.fromJson({
      'schemaVersion': 1,
      'identity': manifest,
      'publicKey': vectors['publicKey'],
    })!;
    bundled.verifyInstalledVersion('1.2.1', 11);
    expect(
      () => bundled.verifyInstalledVersion('1.2.1', 10),
      throwsFormatException,
    );
  });
}
