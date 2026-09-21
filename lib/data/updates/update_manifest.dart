import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

import '../../domain/models/release_identity.dart';

const updateApplicationId = 'dev.shiori.reader';
const updateSignatureAlgorithm = 'rsa3072-pkcs1-sha256';
const maxUpdateManifestBytes = 4 * 1024 * 1024;

/// Trust is supplied by the installed app, never by a downloaded manifest.
final class UpdatePublicKey {
  UpdatePublicKey.fromJson(Map<String, dynamic> json)
    : modulusHex = json['modulus'] as String,
      keyId = json['keyId'] as String {
    if (json['algorithm'] != updateSignatureAlgorithm ||
        json['exponent'] != 65537 ||
        !RegExp(r'^[89a-f][0-9a-f]{767}$').hasMatch(modulusHex) ||
        BigInt.parse(modulusHex, radix: 16).isEven ||
        keyId != hashes.sha256.convert(_hexBytes(modulusHex)).toString()) {
      throw const FormatException('Invalid update public key');
    }
  }

  final String modulusHex;
  final String keyId;

  bool verify(Uint8List bytes, Uint8List signature) {
    if (bytes.isEmpty ||
        bytes.length > maxUpdateManifestBytes ||
        signature.length != 384) {
      return false;
    }
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(
        false,
        PublicKeyParameter<RSAPublicKey>(
          RSAPublicKey(BigInt.parse(modulusHex, radix: 16), BigInt.from(65537)),
        ),
      );
    try {
      return signer.verifySignature(bytes, RSASignature(signature));
    } on ArgumentError {
      return false;
    }
  }
}

Uint8List _hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

ReleaseIdentity _identity(Map<String, dynamic> json) {
  final result = ReleaseIdentity(
    tag: json['tag'] as String,
    version: json['version'] as String,
    build: json['build'] as int,
    commit: json['commit'] as String,
  );
  if (json['applicationId'] != updateApplicationId ||
      json['channel'] != result.channel.name) {
    throw const FormatException('Release identity mismatch');
  }
  return result;
}

/// Read assets/release/build-info.json; local/iOS builds are marked development.
final class BundledRelease {
  BundledRelease._(this.identity, this.publicKey);
  final ReleaseIdentity identity;
  final UpdatePublicKey publicKey;

  static BundledRelease? fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unknown build identity');
    }
    if (json['development'] == true) return null;
    return BundledRelease._(
      _identity(json['identity'] as Map<String, dynamic>),
      UpdatePublicKey.fromJson(json['publicKey'] as Map<String, dynamic>),
    );
  }

  void verifyInstalledVersion(String version, int build) {
    if (identity.version != version || identity.build != build) {
      throw const FormatException(
        'Installed version differs from bundled identity',
      );
    }
  }
}

final class UpdateFile {
  const UpdateFile(this.path, this.size, this.sha256);
  final String path;
  final int size;
  final String sha256;
}

final class UpdateAsset {
  UpdateAsset._(
    this.platform,
    this.name,
    this.size,
    this.sha256,
    this.minimumSystem,
    this.certificateSha256,
    this.updaterProtocol,
    List<UpdateFile> files,
  ) : files = List.unmodifiable(files);
  final String platform;
  final String name;
  final int size;
  final String sha256;
  final String minimumSystem;
  final String? certificateSha256;
  final int? updaterProtocol;
  final List<UpdateFile> files;
}

final class UpdateManifest {
  UpdateManifest._(this.identity, List<UpdateAsset> assets)
    : assets = List.unmodifiable(assets);
  final ReleaseIdentity identity;
  final List<UpdateAsset> assets;

  static UpdateManifest verifyAndRead(
    Uint8List bytes,
    Uint8List signature,
    UpdatePublicKey trustedKey, {
    required String expectedTag,
  }) {
    if (!trustedKey.verify(bytes, signature)) {
      throw const FormatException('Invalid update manifest signature');
    }
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final identity = _identity(json);
    if (json['schemaVersion'] != 1 ||
        json['keyId'] != trustedKey.keyId ||
        json['algorithm'] != updateSignatureAlgorithm ||
        identity.tag != expectedTag) {
      throw const FormatException('Unsupported update manifest');
    }
    final assets = <UpdateAsset>[];
    final platforms = <String>{};
    for (final item in json['assets'] as List<dynamic>) {
      final asset = item as Map<String, dynamic>;
      final platform = asset['platform'] as String;
      if (!['android', 'windows-x64'].contains(platform) ||
          !platforms.add(platform)) {
        throw const FormatException('Invalid update platform');
      }
      final suffix = platform == 'android' ? 'android.apk' : 'windows-x64.zip';
      final name = asset['name'] as String;
      final minimum = asset['minimumSystem'] as String;
      if (name != 'shiori-reader-${identity.tag}-$suffix' || minimum.isEmpty) {
        throw const FormatException('Invalid update asset');
      }
      final size = _size(asset['size'], allowZero: false);
      final digest = _digest(asset['sha256']);
      final files = <UpdateFile>[];
      String? certificate;
      int? protocol;
      if (platform == 'android') {
        certificate = _digest(asset['certificateSha256']);
      } else {
        protocol = asset['updaterProtocol'] as int;
        final entries = asset['files'] as List<dynamic>;
        if (protocol != 1 || entries.isEmpty || entries.length > 10000) {
          throw const FormatException(
            'Unsupported updater protocol or file count',
          );
        }
        final names = <String>{};
        var total = 0;
        for (final raw in entries) {
          final file = raw as Map<String, dynamic>;
          final path = file['path'] as String;
          if (!isSafeUpdatePath(path) || !names.add(path.toLowerCase())) {
            throw const FormatException('Invalid update file path');
          }
          final length = _size(file['size'], allowZero: true);
          total += length;
          if (total > 2 * 1024 * 1024 * 1024) {
            throw const FormatException('Update too large');
          }
          files.add(UpdateFile(path, length, _digest(file['sha256'])));
        }
        for (final file in files) {
          final parts = file.path.toLowerCase().split('/');
          for (var i = 1; i < parts.length; i++) {
            if (names.contains(parts.take(i).join('/'))) {
              throw const FormatException('File and directory collision');
            }
          }
        }
        if (!names.contains('shiori.exe') || !names.contains('data/app.so')) {
          throw const FormatException('Missing Windows runtime');
        }
      }
      assets.add(
        UpdateAsset._(
          platform,
          name,
          size,
          digest,
          minimum,
          certificate,
          protocol,
          files,
        ),
      );
    }
    if (platforms.length != 2) {
      throw const FormatException('Incomplete platform assets');
    }
    return UpdateManifest._(identity, assets);
  }
}

int _size(dynamic value, {required bool allowZero}) {
  if (value is! int ||
      value < (allowZero ? 0 : 1) ||
      value > 2 * 1024 * 1024 * 1024) {
    throw const FormatException('Invalid update size');
  }
  return value;
}

String _digest(dynamic value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid SHA-256');
  }
  return value;
}

bool isSafeUpdatePath(String path) {
  if (path.isEmpty ||
      path.length > 1024 ||
      RegExp(r'[\\:\x00-\x1f<>"|?*]').hasMatch(path)) {
    return false;
  }
  return path
      .split('/')
      .every(
        (part) =>
            part.isNotEmpty &&
            part != '.' &&
            part != '..' &&
            !part.endsWith('.') &&
            !part.endsWith(' ') &&
            !RegExp(
              r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
              caseSensitive: false,
            ).hasMatch(part),
      );
}
