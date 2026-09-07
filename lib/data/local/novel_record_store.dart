import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import 'database/cache_database.dart';
import 'local_guard.dart';
import 'record_codec.dart';

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

/// Basic normalized records only. No Source IO, TTL policy, eviction or images.
class NovelRecordStore {
  NovelRecordStore(this.db);
  final CacheDatabase db;
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
    final result = await localWrite(db, operation, token, () async {
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
    });
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
