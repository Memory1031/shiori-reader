import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/contracts/cancellation.dart';
import '../../domain/models/release_identity.dart';
import 'update_http.dart';
import 'update_manifest.dart';
import 'update_storage.dart';
import 'update_installer.dart';

final class _VerifiedUpdate {
  _VerifiedUpdate(this.candidate, this.asset, this.manifest, this.signature);
  final UpdateCandidate candidate;
  final UpdateAsset asset;
  final Uint8List manifest;
  final Uint8List signature;
}

final class GithubUpdateRepository implements AppUpdateRepository {
  GithubUpdateRepository({
    required this.installed,
    required this.platform,
    required this.key,
    required this.http,
    required this.storage,
    this.installer,
  });
  @override
  final InstalledUpdateApp installed;
  final String platform;
  final UpdatePublicKey? key;
  final UpdateHttp http;
  final UpdateStorage storage;
  final UpdateInstaller? installer;
  @override
  bool get supportsInstallation => installer != null;
  @override
  Future<UpdateInstallState> installationStatus() async =>
      await installer?.status() ?? UpdateInstallState.idle;
  @override
  Future<void> openInstallSettings() async => installer?.openSettings();

  @override
  Future<UpdateInstallState> install(
    UpdateCandidate candidate,
    CancellationToken token,
  ) => _guard(() async {
    final value = _selected;
    if (installer == null ||
        value == null ||
        value.candidate != candidate ||
        installed.availability != UpdateAvailability.enabled) {
      throw const UpdateIssue(UpdateProblem.verification);
    }
    // Recheck the signed metadata and bytes at handoff, even after a long pause.
    final verified = _verify(
      candidate.release.tag,
      candidate.notes,
      value.manifest,
      value.signature,
    );
    final package = storage.file('package.bin');
    try {
      await _verifyPackage(package, verified, token);
    } on UpdateIssue catch (error) {
      if (error.problem == UpdateProblem.verification) {
        throw const UpdateIssue(UpdateProblem.packageInvalid);
      }
      rethrow;
    }
    checkUpdateCancellation(token);
    return installer!.install(
      package,
      verified.candidate.release,
      verified.asset,
      verified.manifest,
      verified.signature,
    );
  });
  _VerifiedUpdate? _selected;
  bool _closed = false;

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_closed) throw const UpdateIssue(UpdateProblem.cancelled);
    try {
      return await action();
    } on UpdateIssue {
      rethrow;
    } on FileSystemException {
      throw const UpdateIssue(UpdateProblem.storage);
    } on FormatException {
      throw const UpdateIssue(UpdateProblem.verification);
    } on TypeError {
      throw const UpdateIssue(UpdateProblem.verification);
    } on ArgumentError {
      throw const UpdateIssue(UpdateProblem.verification);
    } on StateError {
      throw const UpdateIssue(UpdateProblem.verification);
    }
  }

  @override
  Future<UpdatePreferences> loadPreferences() => _guard(
    () => storage.loadPreferences(
      installed.release?.channel ?? UpdateChannel.stable,
    ),
  );
  @override
  Future<void> savePreferences(UpdatePreferences preferences) =>
      _guard(() => storage.savePreferences(preferences));

  _VerifiedUpdate _verify(
    String tag,
    String notes,
    Uint8List raw,
    Uint8List sig,
  ) {
    final manifest = UpdateManifest.verifyAndRead(
      raw,
      sig,
      key!,
      expectedTag: tag,
    );
    final asset = manifest.assets.singleWhere(
      (asset) => asset.platform == platform,
    );
    return _VerifiedUpdate(
      UpdateCandidate(
        release: manifest.identity,
        bytes: asset.size,
        notes: notes.length > 10000 ? notes.substring(0, 10000) : notes,
        page: releasePage(tag),
      ),
      asset,
      raw,
      sig,
    );
  }

  bool _eligible(_VerifiedUpdate value, UpdateChannel channel) =>
      value.candidate.release.canReplace(installed.release!, channel);

  @override
  Future<UpdateCandidate?> check(
    UpdateChannel channel,
    CancellationToken token,
  ) => _guard(() async {
    if (installed.availability != UpdateAvailability.enabled) return null;
    await storage.prepare();
    Map<String, dynamic> cache;
    try {
      cache =
          await UpdateStorage.readJson(storage.file('http-cache.json'))
              as Map<String, dynamic>? ??
          {};
    } on FormatException {
      cache = {};
    } on TypeError {
      cache = {};
    }
    final replacements = <String, dynamic>{};
    final verified = <_VerifiedUpdate>[];
    var inspected = 0;
    var complete = false;
    var incompleteRelease = false;
    scan:
    for (var page = 1; page <= 3; page++) {
      checkUpdateCancellation(token);
      final uri = Uri.https(
        'api.github.com',
        '/repos/$updateRepositoryPath/releases',
        {'per_page': '20', 'page': '$page'},
      );
      final old = cache['$page'];
      final etag = old is Map && old['etag'] is String && old['body'] is List
          ? old['etag'] as String
          : null;
      final response = await http.read(
        uri,
        token,
        limit: 2 * 1024 * 1024,
        etag: etag,
      );
      final list =
          (response.notModified
                  ? old['body']
                  : jsonDecode(utf8.decode(response.bytes)))
              as List<dynamic>;
      if (list.length > 20) throw const UpdateIssue(UpdateProblem.incomplete);
      replacements['$page'] = {
        'etag': response.headers['etag'] ?? etag,
        'body': list,
      };
      for (final rawRelease in list) {
        checkUpdateCancellation(token);
        final release = rawRelease as Map<String, dynamic>;
        if (release['draft'] == true) continue;
        final tag = release['tag_name'] as String;
        ReleaseIdentity label;
        try {
          label = ReleaseIdentity(
            tag: tag,
            version: tag.substring(1).split('-').first,
            build: 2100000000,
            commit: '0' * 40,
          );
        } on FormatException {
          continue;
        } on RangeError {
          continue;
        }
        if (!label.canReplace(installed.release!, channel) ||
            tag == installed.release!.tag) {
          continue;
        }
        if ((release['prerelease'] == true) !=
            (label.channel == UpdateChannel.beta)) {
          continue;
        }
        final assets = <String, Map<String, dynamic>>{};
        for (final rawAsset in release['assets'] as List<dynamic>) {
          final asset = rawAsset as Map<String, dynamic>;
          final name = asset['name'] as String;
          if (assets.containsKey(name)) {
            throw const UpdateIssue(UpdateProblem.verification);
          }
          assets[name] = asset;
        }
        // Legacy releases cannot disprove a signed upgrade, but also cannot
        // establish that this channel is up to date.
        if (!assets.containsKey('update-manifest.json') ||
            !assets.containsKey('update-manifest.sig')) {
          incompleteRelease = true;
          continue;
        }
        if (++inspected > 8) break scan;
        void assetReady(String name, int limit, {int? exact}) {
          final asset = assets[name];
          if (asset == null || asset['state'] != 'uploaded') {
            throw const UpdateIssue(UpdateProblem.incomplete);
          }
          final size = asset['size'] as int;
          if (size < 1 ||
              size > limit ||
              (exact != null && size != exact) ||
              asset['browser_download_url'] !=
                  releaseAsset(tag, name).toString()) {
            throw const UpdateIssue(UpdateProblem.verification);
          }
        }

        assetReady('update-manifest.json', maxUpdateManifestBytes);
        assetReady('update-manifest.sig', 384, exact: 384);
        final raw = await http.read(
          releaseAsset(tag, 'update-manifest.json'),
          token,
          limit: maxUpdateManifestBytes,
        );
        final sig = await http.read(
          releaseAsset(tag, 'update-manifest.sig'),
          token,
          limit: 384,
        );
        final candidate = _verify(
          tag,
          (release['body'] as String?) ?? '',
          raw.bytes,
          sig.bytes,
        );
        assetReady(
          candidate.asset.name,
          candidate.asset.size,
          exact: candidate.asset.size,
        );
        if (_eligible(candidate, channel)) verified.add(candidate);
      }
      if (list.length < 20) {
        complete = true;
        break;
      }
    }
    checkUpdateCancellation(token);
    await UpdateStorage.writeJson(
      storage.file('http-cache.json'),
      replacements,
    );
    verified.sort(
      (a, b) => b.candidate.release.build.compareTo(a.candidate.release.build),
    );
    for (var i = 1; i < verified.length; i++) {
      if (verified[i].candidate.release.build ==
              verified[i - 1].candidate.release.build &&
          verified[i].candidate.release != verified[i - 1].candidate.release) {
        throw const UpdateIssue(UpdateProblem.verification);
      }
    }
    checkUpdateCancellation(token);
    if (verified.isEmpty) {
      if (!complete || incompleteRelease) {
        throw const UpdateIssue(UpdateProblem.incomplete);
      }
      return null;
    }
    _selected = verified.first;
    return _selected!.candidate;
  });

  Future<void> _verifyPackage(
    File file,
    _VerifiedUpdate candidate,
    CancellationToken token,
  ) async {
    checkUpdateCancellation(token);
    if (!await file.exists() || await file.length() != candidate.asset.size) {
      throw const UpdateIssue(UpdateProblem.verification);
    }
    final digest = await sha256
        .bind(
          file.openRead().map((bytes) {
            checkUpdateCancellation(token);
            return bytes;
          }),
        )
        .first;
    checkUpdateCancellation(token);
    if (digest.toString() != candidate.asset.sha256) {
      throw const UpdateIssue(UpdateProblem.verification);
    }
  }

  @override
  Future<UpdateCandidate?> restore(
    UpdateChannel channel,
    CancellationToken token,
  ) => _guard(() async {
    if (installed.availability != UpdateAvailability.enabled) return null;
    await storage.prepare();
    final part = storage.file('package.part');
    if (await part.exists()) await part.delete();
    final json = await UpdateStorage.readJson(storage.file('download.json'));
    if (json == null || !await storage.file('package.bin').exists()) {
      return null;
    }
    final record = json as Map<String, dynamic>;
    if (record['schema'] != 1) {
      throw const UpdateIssue(UpdateProblem.verification);
    }
    final value = _verify(
      record['tag'] as String,
      record['notes'] as String,
      base64Decode(record['manifest'] as String),
      base64Decode(record['signature'] as String),
    );
    if (value.candidate.release.build <= installed.build) {
      await storage.file('package.bin').delete();
      await storage.file('download.json').delete();
      return null;
    }
    if (!_eligible(value, channel)) return null;
    await _verifyPackage(storage.file('package.bin'), value, token);
    _selected = value;
    return value.candidate;
  });

  @override
  Future<void> download(
    UpdateCandidate candidate,
    CancellationToken token,
    void Function(int received) onProgress,
  ) => _guard(() async {
    final value = _selected;
    if (value == null || value.candidate != candidate) {
      throw const UpdateIssue(UpdateProblem.verification);
    }
    await storage.prepare();
    final completed = storage.file('package.bin');
    if (await completed.exists()) await completed.delete();
    await UpdateStorage.writeJson(storage.file('download.json'), {
      'schema': 1,
      'tag': candidate.release.tag,
      'notes': candidate.notes,
      'manifest': base64Encode(value.manifest),
      'signature': base64Encode(value.signature),
    });
    final part = storage.file('package.part');
    RandomAccessFile? output;
    var received = 0;
    try {
      output = await part.open(mode: FileMode.write);
      await http.download(
        releaseAsset(candidate.release.tag, value.asset.name),
        token,
        limit: value.asset.size,
        chunk: (bytes) async {
          checkUpdateCancellation(token);
          received += bytes.length;
          if (received > value.asset.size) {
            throw const UpdateIssue(UpdateProblem.verification);
          }
          await output!.writeFrom(bytes);
          onProgress(received);
        },
      );
      await output.flush();
      await output.close();
      output = null;
      await _verifyPackage(part, value, token);
      await part.rename(completed.path);
    } finally {
      await output?.close();
      if (await part.exists()) await part.delete();
    }
  });

  @override
  Future<void> close() async {
    _closed = true;
    http.close();
  }
}
