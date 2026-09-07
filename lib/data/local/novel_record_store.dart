import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import 'database/cache_database.dart';
import 'local_guard.dart';
import 'record_codec.dart';
import '../cache/cache_policy.dart';
import '../media/persistent_image_repository.dart';

class StoredRecord<T> {
  const StoredRecord({
    required this.value,
    required this.fetchedAt,
    required this.parserVersion,
    this.expiresAt,
  });
  final T value;
  final DateTime fetchedAt;
  final DateTime? expiresAt;
  final int parserVersion;
}

/// Normalized records, ownership metadata and payload LRU; never Source IO.
class NovelRecordStore {
  NovelRecordStore(this.db, {this.coordinator});
  final CacheDatabase db;
  final CacheCoordinator? coordinator;
  final _touched = <String, DateTime>{};
  static String recordId(String table, NovelKey key, String? chapter) =>
      jsonEncode([table, ...key.identityFields, chapter]);
  List<Variable> _key(NovelKey key, String? chapter) => [
    Variable(key.sourceId.value),
    Variable(key.novelId),
    if (chapter != null) Variable(chapter),
  ];
  String _where(String? chapter) =>
      'source_id=? AND novel_id=?${chapter == null ? '' : ' AND chapter_id=?'}';
  Future<Result<StoredRecord<T>?>> _read<T>(
    String table,
    NovelKey key,
    String? chapter,
    Operation operation,
    T Function(String) decode,
    bool Function(T) belongs,
    CancellationToken token,
  ) async {
    final generation = coordinator?.generation;
    final result = await localRead(operation, token, () async {
      final row = await db
          .customSelect(
            'SELECT * FROM $table WHERE ${_where(chapter)}',
            variables: _key(key, chapter),
          )
          .getSingleOrNull();
      if (row == null) return null;
      if (row.read<int>('codec_version') != 1) {
        throw const FormatException('Unsupported cache codec');
      }
      final value = decode(row.read<String>('payload'));
      if (!belongs(value)) {
        throw const FormatException('Cache identity mismatch');
      }
      final owner = coordinator;
      final id = recordId(table, key, chapter);
      if (owner != null &&
          owner.now().difference(_touched[id] ?? DateTime(1970)) >=
              const Duration(minutes: 1)) {
        _touched[id] = owner.now();
        if (_touched.length > 1024) _touched.remove(_touched.keys.first);
        Future<void> touch() async {
          if (coordinator?.generation != generation || token.isCancelled) {
            return;
          }
          await db.customStatement(
            'UPDATE $table SET last_access_at=? WHERE ${_where(chapter)}',
            [
              owner.now().millisecondsSinceEpoch,
              key.sourceId.value,
              key.novelId,
              ?chapter,
            ],
          );
          final refs = switch (value) {
            ChapterContent(:final blocks) => blocks.whereType<ImageBlock>().map(
              (b) => b.media,
            ),
            NovelDetail(:final summary) => [
              if (summary.cover != null) summary.cover!,
            ],
            _ => <MediaRef>[],
          };
          for (final ref in refs) {
            await db.customStatement(
              'INSERT OR IGNORE INTO image_owners VALUES(?,?,?)',
              [PersistentImageRepository.keyFor(ref), ...key.identityFields],
            );
          }
        }

        try {
          await owner.exclusive(touch);
        } catch (_) {
          /* LRU bookkeeping cannot hide readable content. */
        }
      }
      final expiry = row.readNullable<int>('expires_at');
      return StoredRecord(
        value: value,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('fetched_at'),
          isUtc: true,
        ),
        parserVersion: row.read<int>('parser_version'),
        expiresAt: expiry == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true),
      );
    });
    return switch (result) {
      Failure(:final failure) when !failure.isCancellation => Failure(
        AppFailure(
          kind: FailureKind.cache,
          operation: operation,
          context: FailureContext.invalidContent,
        ),
      ),
      _ => result,
    };
  }

  Future<Result<void>> _write(
    String table,
    NovelKey key,
    String? chapter,
    String payload,
    DateTime fetchedAt,
    int parserVersion,
    DateTime? expiresAt,
    Operation operation,
    CancellationToken token,
  ) async {
    if (parserVersion < 1) {
      throw ArgumentError.value(parserVersion, 'parserVersion');
    }
    final owner = coordinator;
    final generation = owner?.generation;
    Future<Result<void>> commit() => localWrite(db, operation, token, () async {
      if (owner != null && owner.generation != generation) {
        throw StateError('Cache cleared');
      }
      await db.customStatement(
        '''INSERT INTO $table(source_id,novel_id,${chapter == null ? '' : 'chapter_id,'}payload,codec_version,parser_version,fetched_at,expires_at,last_access_at,byte_size)
        VALUES(?,?,${chapter == null ? '' : '?,'}?,1,?,?,?,?,?) ON CONFLICT(source_id,novel_id${chapter == null ? '' : ',chapter_id'}) DO UPDATE SET payload=excluded.payload,codec_version=excluded.codec_version,parser_version=excluded.parser_version,fetched_at=excluded.fetched_at,expires_at=excluded.expires_at,last_access_at=excluded.last_access_at,byte_size=excluded.byte_size''',
        [
          key.sourceId.value,
          key.novelId,
          ?chapter,
          payload,
          parserVersion,
          fetchedAt.millisecondsSinceEpoch,
          expiresAt?.millisecondsSinceEpoch,
          fetchedAt.millisecondsSinceEpoch,
          utf8.encode(payload).length,
        ],
      );
      final refs = <MediaRef>[];
      if (table == 'chapter_cache') {
        refs.addAll(
          RecordCodec.readChapter(
            payload,
          ).blocks.whereType<ImageBlock>().map((b) => b.media),
        );
      }
      if (table == 'novel_cache') {
        final cover = RecordCodec.readDetail(payload).summary.cover;
        if (cover != null) refs.add(cover);
      }
      for (final ref in refs.toSet()) {
        await db.customStatement(
          'INSERT OR IGNORE INTO image_owners(cache_key,source_id,novel_id) VALUES(?,?,?)',
          [
            PersistentImageRepository.keyFor(ref),
            key.sourceId.value,
            key.novelId,
          ],
        );
      }
      if (owner != null) await _evict(owner);
    });
    final result = owner == null
        ? await commit()
        : await owner.exclusive(commit);
    return switch (result) {
      Failure(:final failure) when !failure.isCancellation => Failure(
        AppFailure(
          kind: FailureKind.cache,
          operation: operation,
          context: FailureContext.cacheWriteFailed,
        ),
      ),
      _ => result,
    };
  }

  Future<void> _evict(CacheCoordinator owner) async {
    const tables = ['novel_cache', 'catalog_cache', 'chapter_cache'];
    final rows = await db
        .customSelect(
          '${tables.map((table) => "SELECT '$table' AS kind,source_id,novel_id,${table == 'chapter_cache' ? 'chapter_id' : 'NULL AS chapter_id'},byte_size,last_access_at FROM $table").join(' UNION ALL ')} ORDER BY last_access_at',
        )
        .get();
    var total = rows.fold<int>(
      0,
      (sum, row) => sum + row.read<int>('byte_size'),
    );
    if (total <= owner.policy.textBytes) return;
    for (final row in rows) {
      if (total <= owner.policy.target(owner.policy.textBytes)) break;
      final table = row.read<String>('kind');
      final key = NovelKey(
        sourceId: SourceId(row.read<String>('source_id')),
        novelId: row.read<String>('novel_id'),
      );
      final chapter = row.readNullable<String>('chapter_id');
      if (owner.isPinned(recordId(table, key, chapter))) continue;
      await db.customStatement('DELETE FROM $table WHERE ${_where(chapter)}', [
        key.sourceId.value,
        key.novelId,
        ?chapter,
      ]);
      total -= row.read<int>('byte_size');
    }
  }

  Future<Result<StoredRecord<NovelDetail>?>> readDetail(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => _read(
    'novel_cache',
    key,
    null,
    Operation.novelDetail,
    RecordCodec.readDetail,
    (value) => value.summary.key == key,
    cancellation,
  );
  Future<Result<StoredRecord<Catalog>?>> readCatalog(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => _read(
    'catalog_cache',
    key,
    null,
    Operation.catalog,
    RecordCodec.readCatalog,
    (value) => value.novelKey == key,
    cancellation,
  );
  Future<Result<StoredRecord<ChapterContent>?>> readChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) => _read(
    'chapter_cache',
    key.novelKey,
    key.chapterId,
    Operation.chapter,
    RecordCodec.readChapter,
    (value) => value.key == key,
    cancellation,
  );
  Future<Result<void>> writeDetail(
    NovelDetail value, {
    required DateTime fetchedAt,
    required int parserVersion,
    DateTime? expiresAt,
    required CancellationToken cancellation,
  }) => _write(
    'novel_cache',
    value.summary.key,
    null,
    RecordCodec.detail(value),
    fetchedAt,
    parserVersion,
    expiresAt,
    Operation.novelDetail,
    cancellation,
  );
  Future<Result<void>> writeCatalog(
    Catalog value, {
    required DateTime fetchedAt,
    required int parserVersion,
    DateTime? expiresAt,
    required CancellationToken cancellation,
  }) => _write(
    'catalog_cache',
    value.novelKey,
    null,
    RecordCodec.catalog(value),
    fetchedAt,
    parserVersion,
    expiresAt,
    Operation.catalog,
    cancellation,
  );
  Future<Result<void>> writeChapter(
    ChapterContent value, {
    required DateTime fetchedAt,
    required int parserVersion,
    DateTime? expiresAt,
    required CancellationToken cancellation,
  }) => _write(
    'chapter_cache',
    value.key.novelKey,
    value.key.chapterId,
    RecordCodec.chapter(value),
    fetchedAt,
    parserVersion,
    expiresAt,
    Operation.chapter,
    cancellation,
  );
}
