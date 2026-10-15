part of 'managed_local_books.dart';

typedef _BookStamp = ({
  String hash,
  DateTime modified,
  int size,
  String? bundle,
  LocalBookFormat format,
});

// Live Reader uses and search sessions own these pins; the ordinary cache is
// still limited to one book. Never retain a library-wide decoded cache.
final class _SearchSnapshot {
  _SearchSnapshot(this.read, this.id);
  final (NovelKey, String, DateTime, int, _StoredBook) read;
  final LocalSearchSnapshotId id;
  _BookStamp get stamp => read.$5.stamp;
}

extension _LocalSearchOwnership on ManagedLocalBooks {
  String _searchIdentity() => base64UrlEncode(
    List<int>.generate(24, (_) => _searchRandom.nextInt(256)),
  );

  void _pinReaderSnapshot((NovelKey, String, DateTime, int, _StoredBook) read) {
    if (_bookUses[read.$1]?.isNotEmpty == true) {
      _searchSnapshots.putIfAbsent(
        read.$1,
        () => _SearchSnapshot(read, LocalSearchSnapshotId(_searchIdentity())),
      );
    }
  }

  void _releaseSearchSnapshot(NovelKey key) {
    if (_bookUses[key]?.isNotEmpty != true &&
        !_searchSessions.containsValue(key)) {
      _searchSnapshots.remove(key);
    }
  }

  Future<void> _retireSearchSnapshot(NovelKey key) async {
    _searchSnapshots.remove(key);
    final sessions = _searchSessions.entries
        .where((entry) => entry.value == key)
        .map((entry) => entry.key)
        .toList();
    await Future.wait(sessions.map((s) => s.invalidate()));
  }

  Future<Result<bool>> _checkSearchSnapshot(
    NovelKey key,
    LocalSearchSnapshotId id,
    _BookStamp stamp,
    CancellationToken token,
  ) => _run(Operation.search, () async {
    checkLocalCancellation(token);
    if (_closing != null || _searchSnapshots[key]?.id != id) {
      return false;
    }
    final row = await _bookRow(this, key);
    if (row == null ||
        row.read<int>('maintenance') != 0 ||
        row.readNullable<String>('active_bundle') != stamp.bundle ||
        row.read<String>('manifest_hash') != stamp.hash ||
        row.read<String>('format') != stamp.format.name) {
      return false;
    }
    final file = await _file(
      key.novelId,
      'manifest.json',
      bundle: stamp.bundle,
    );
    final stat = await file.stat();
    checkLocalCancellation(token);
    return _searchSnapshots[key]?.id == id &&
        stat.modified == stamp.modified &&
        stat.size == stamp.size;
  });
}
