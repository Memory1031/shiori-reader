import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/update_manifest.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/updates/macos.json').readAsStringSync())
          as Map<String, dynamic>;
  final key = UpdatePublicKey.fromJson(
    fixture['publicKey'] as Map<String, dynamic>,
  );
  Uint8List bytes(String name, String field) =>
      base64Decode(fixture['cases'][name][field] as String);
  test(
    'macOS signed feed is separate from the existing two-platform protocol',
    () {
      final manifest = UpdateManifest.verifyAndRead(
        bytes('valid', 'manifest'),
        bytes('valid', 'signature'),
        key,
        expectedTag: 'v1.3.2',
        macOS: true,
      );
      expect(manifest.assets.single.platform, 'macos-universal');
      expect(
        () => UpdateManifest.verifyAndRead(
          bytes('valid', 'manifest'),
          bytes('valid', 'signature'),
          key,
          expectedTag: 'v1.3.2',
        ),
        throwsFormatException,
      );
      for (final invalid in ['wrongProtocol', 'wrongPlatform']) {
        expect(
          () => UpdateManifest.verifyAndRead(
            bytes(invalid, 'manifest'),
            bytes(invalid, 'signature'),
            key,
            expectedTag: 'v1.3.2',
            macOS: true,
          ),
          throwsFormatException,
        );
      }
      final tampered = bytes('valid', 'manifest')..[0] ^= 1;
      expect(
        () => UpdateManifest.verifyAndRead(
          tampered,
          bytes('valid', 'signature'),
          key,
          expectedTag: 'v1.3.2',
          macOS: true,
        ),
        throwsFormatException,
      );
    },
  );
}
