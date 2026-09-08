import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import 'database/user_database.dart';
import 'files/app_paths.dart';
import 'local_guard.dart';
import 'library_rows.dart';
import 'parser_worker.dart';
import '../../domain/contracts/local_book_decoder.dart';
import 'record_codec.dart';
import 'epub/epub_parser.dart';

/// Durable imported originals and normalized content. Never uses cache.db.
/// Single owner, serialized operations; initialize/recover before exposure.
class ManagedLocalBooks
    implements
        LocalBookStore,
        LocalBookManagement,
        LocalPagePresentationRepository {
  ManagedLocalBooks._(this.paths, this.db);
  final AppPaths paths;
  final UserDatabase db;
  (NovelKey, String, DateTime, int, LocalBookRecord)? _readCache;
  final _presentations = <NovelKey, (LocalBookContent, Map<String, String>)>{};
  @override
  Future<Result<String?>> loadPagePresentation(
    ChapterKey chapter, {
    required CancellationToken cancellation,
  }) => _run(Operation.chapter, () async {
    checkLocalCancellation(cancellation);
    final record = await _read(chapter.novelKey, token: cancellation);
    if (record == null || record.format != LocalBookFormat.epub) return null;
    return _presentations[chapter.novelKey]?.$2[chapter.chapterId];
  });

  Future<void> _tail = Future.value();
  bool _closed = false;
  static const maxOriginalBytes = 128 * 1024 * 1024;
  static const maxMediaBytes = 32 * 1024 * 1024;
  static const maxBundleBytes = 512 * 1024 * 1024;
  static const maxManifestBytes = 32 * 1024 * 1024;
  static final _digest = RegExp(r'^[a-f0-9]{64}$');

  static Future<Result<ManagedLocalBooks>> open(
    AppPaths paths,
    UserDatabase db,
  ) async {
    final store = ManagedLocalBooks._(paths, db);
    try {
      // Read DB before touching files: an unavailable index must not erase data.
      final rows = await db
          .customSelect('SELECT digest FROM local_books')
          .get();
      final committed = rows.map((r) => r.read<String>('digest')).toSet();
      for (final dir in [paths.localBooks, paths.localImportStaging]) {
        await dir.create(recursive: true);
        final expected = p.join(
          await paths.root.resolveSymbolicLinks(),
          'users',
          p.basename(dir.path),
        );
        if (await dir.resolveSymbolicLinks() != expected) {
          throw const FileSystemException('Linked storage root');
        }
      }
      await for (final entry in paths.localImportStaging.list(
        followLinks: false,
      )) {
        if (p.basename(entry.path).startsWith('import-')) {
          await _deleteChild(paths.localImportStaging, entry.path);
        }
      }
      await for (final entry in paths.localBooks.list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (_digest.hasMatch(name) && !committed.contains(name)) {
          await _deleteChild(paths.localBooks, entry.path);
        }
      }
      return Success(store);
    } catch (e) {
      return Failure(localFailure(Operation.libraryRead, e));
    }
  }

  Future<Result<T>> _run<T>(Operation op, Future<T> Function() action) {
    if (_closed) throw StateError('Local book store is closed');
    final result = _tail.then((_) async {
      try {
        return Success<T>(await action());
      } catch (e) {
        return Failure<T>(
          e is _LimitExceeded ||
                  e is LocalParseException &&
                      e.problem == LocalParseProblem.tooLarge
              ? AppFailure(kind: FailureKind.tooLarge, operation: op)
              : e is FormatException
              ? AppFailure(
                  kind: FailureKind.parse,
                  operation: op,
                  context: FailureContext.invalidContent,
                )
              : localFailure(op, e),
        );
      }
    });
    _tail = result.then((_) {});
    return result;
  }

  @override
  Future<Result<LocalBookRecord>> importBook({
    required Stream<List<int>> bytes,
    required LocalBookFormat format,
    required LocalBookParser parse,
    bool addToShelf = false,
    required CancellationToken cancellation,
  }) => _run(Operation.libraryWrite, () async {
    checkLocalCancellation(cancellation);
    final stage = await paths.localImportStaging.createTemp('import-');
    Directory? published;
    var committed = false;
    _ImportSession? session;
    try {
      final original = File(p.join(stage.path, 'original'));
      await _writeStream(original, bytes, maxOriginalBytes, cancellation);
      final digest = (await sha256.bind(original.openRead()).first).toString();
      checkLocalCancellation(cancellation);
      final key = LocalBookIdentity.book(digest);
      final existing = await _read(key, token: cancellation);
      if (existing != null) {
        if (addToShelf) {
          await db.transaction(() async {
            checkLocalCancellation(cancellation);
            await writeBookshelfRow(
              db,
              BookshelfEntry(
                snapshot: existing.content.detail.summary,
                addedAt: DateTime.now(),
              ),
              DateTime.now(),
            );
            checkLocalCancellation(cancellation);
          });
        }
        return existing;
      }
      session = _ImportSession(
        key,
        stage,
        cancellation,
        await original.length(),
      );
      final content = await parse(session);
      await session.finish();
      checkLocalCancellation(cancellation);
      final importedAt = DateTime.now().toUtc();
      final manifest = await _encodeManifest(
        content,
        key,
        session.media,
        format,
        importedAt,
        cancellation,
      );
      if (manifest.length > maxManifestBytes ||
          session.used + manifest.length > maxBundleBytes) {
        throw const _LimitExceeded();
      }
      await File(
        p.join(stage.path, 'manifest.json'),
      ).writeAsBytes(manifest, flush: true);
      checkLocalCancellation(cancellation);
      final destination = p.join(paths.localBooks.path, digest);
      // The sole owner has already recovered unindexed directories on open.
      published = await stage.rename(destination);
      await db.transaction(() async {
        checkLocalCancellation(cancellation);
        await db.customStatement(
          'INSERT INTO local_books(digest,format,title,imported_at,manifest_hash) VALUES(?,?,?,?,?)',
          [
            digest,
            format.name,
            content.detail.summary.title,
            importedAt.millisecondsSinceEpoch,
            sha256.convert(manifest).toString(),
          ],
        );
        if (addToShelf) {
          await writeBookshelfRow(
            db,
            BookshelfEntry(
              snapshot: content.detail.summary,
              addedAt: importedAt,
            ),
            importedAt,
          );
        }
        checkLocalCancellation(cancellation);
      });
      db.notifyUpdates({TableUpdate.onTable(db.localBooks)});
      committed = true;
      return LocalBookRecord(
        content: content,
        format: format,
        importedAt: importedAt,
      );
    } finally {
      try {
        await session?.finish();
      } catch (_) {
        /* Original failure wins. */
      }
      // Cleanup failure is recovered at next open; never hide a committed result.
      try {
        if (!committed && published != null) {
          await _deleteChild(paths.localBooks, published.path);
        }
        if (await stage.exists()) {
          await _deleteChild(paths.localImportStaging, stage.path);
        }
      } catch (_) {
        /* Retain bounded staging for startup recovery. */
      }
    }
  });

  static void _validate(
    LocalBookContent content,
    NovelKey key,
    Set<String> media,
  ) {
    final chapters = content.catalog.flatChapters.toList();
    if (content.detail.summary.key != key ||
        content.catalog.novelKey != key ||
        chapters.isEmpty ||
        chapters.length != content.chapters.length) {
      throw const FormatException('Local book identity mismatch');
    }
    var navigationCount = 0;
    final byKey = {for (final c in content.chapters) c.key: c};
    void validateNavigation(List<LocalNavigationEntry> entries, int depth) {
      if (depth > 32) throw const FormatException('Navigation too deep');
      for (final entry in entries) {
        final chapter = byKey[entry.chapterKey];
        if (++navigationCount > 10000 ||
            entry.title.trim().isEmpty ||
            chapter == null ||
            (entry.blockKey != null &&
                !chapter.blocks.any((b) => b.blockKey == entry.blockKey))) {
          throw const FormatException('Invalid local navigation');
        }
        validateNavigation(entry.children, depth + 1);
      }
    }

    validateNavigation(content.navigation, 0);
    final refs = <MediaRef>[?content.detail.summary.cover];
    for (var i = 0; i < chapters.length; i++) {
      if (content.chapters[i].key != chapters[i].key) {
        throw const FormatException('Local chapter mismatch');
      }
      refs.addAll(
        content.chapters[i].blocks.whereType<ImageBlock>().map((b) => b.media),
      );
    }
    for (final ref in refs) {
      if (ref.sourceId != LocalBookIdentity.sourceId ||
          !ref.mediaId.startsWith('${key.novelId}/') ||
          !media.contains(ref.mediaId.substring(key.novelId.length + 1))) {
        throw const FormatException('Unmanaged image');
      }
    }
  }

  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => _run(Operation.libraryRead, () async {
    checkLocalCancellation(cancellation);
    final value = await _read(key, token: cancellation);
    checkLocalCancellation(cancellation);
    return value;
  });

  Future<LocalBookRecord?> _read(
    NovelKey key, {
    required CancellationToken token,
  }) async {
    if (key.sourceId != LocalBookIdentity.sourceId ||
        !_digest.hasMatch(key.novelId)) {
      throw const FormatException('Invalid local identity');
    }
    final row = await db
        .customSelect(
          'SELECT * FROM local_books WHERE digest=?',
          variables: [Variable(key.novelId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final file = await _file(key.novelId, 'manifest.json');
    final stat = await file.stat();
    final hash = row.read<String>('manifest_hash');
    final cached = _readCache;
    if (cached != null &&
        cached.$1 == key &&
        cached.$2 == hash &&
        cached.$3 == stat.modified &&
        cached.$4 == stat.size) {
      return cached.$5;
    }

    if (await file.length() > maxManifestBytes) throw const _LimitExceeded();
    final bytes = await file.readAsBytes();
    final record = await _decodeManifest(
      bytes,
      key,
      row.read<String>('manifest_hash'),
      token,
    );
    if (record.format != LocalBookFormat.epub) {
      _readCache = (key, hash, stat.modified, stat.size, record);
      return record;
    }
    var extracted = _presentations[key];
    if (extracted == null) {
      final original = await _file(key.novelId, 'original');
      if (await original.length() > 64 * 1024 * 1024) {
        throw const _LimitExceeded();
      }
      extracted = await _extractPresentations(
        await original.readAsBytes(),
        key,
        token,
      );
      checkLocalCancellation(token);
      _presentations.clear();
      _presentations[key] = extracted;
    }
    final upgraded = LocalBookRecord(
      content: LocalBookContent(
        detail: record.content.detail,
        catalog: extracted.$1.catalog,
        chapters: extracted.$1.chapters,
        navigation: extracted.$1.navigation,
      ),
      format: record.format,
      importedAt: record.importedAt,
    );
    _readCache = (key, hash, stat.modified, stat.size, upgraded);
    return upgraded;
  }

  @override
  Stream<Result<List<LocalBookInfo>>> watchBooks() => localWatch(
    db
        .customSelect(
          'SELECT digest,title,format,imported_at FROM local_books ORDER BY imported_at DESC,digest',
          readsFrom: {db.localBooks},
        )
        .watch()
        .map(
          (rows) => List<LocalBookInfo>.unmodifiable(
            rows.map(
              (r) => LocalBookInfo(
                key: LocalBookIdentity.book(r.read<String>('digest')),
                title: r.read<String>('title'),
                format: LocalBookFormat.values.byName(r.read<String>('format')),
                importedAt: DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('imported_at'),
                  isUtc: true,
                ),
              ),
            ),
          ),
        ),
    Operation.libraryRead,
  );

  @override
  Future<Result<LocalBookDeletion>> deleteBook(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => _run(Operation.libraryWrite, () async {
    if (key.sourceId != LocalBookIdentity.sourceId ||
        !_digest.hasMatch(key.novelId)) {
      throw const FormatException('Invalid local identity');
    }
    checkLocalCancellation(cancellation);
    _presentations.remove(key);
    if (_readCache?.$1 == key) _readCache = null;
    await db.transaction(() async {
      final variables = [Variable(key.sourceId.value), Variable(key.novelId)];
      // Retain a generation tombstone even across a later re-import.
      await db.customUpdate(
        'INSERT INTO progress_sessions(source_id,novel_id,generation,sequence) VALUES(?,?,1,-1) ON CONFLICT(source_id,novel_id) DO UPDATE SET generation=generation+1,sequence=-1',
        variables: variables,
        updates: {db.progressSessions},
      );
      await db.customUpdate(
        'DELETE FROM reading_progress WHERE source_id=? AND novel_id=?',
        variables: variables,
        updates: {db.readingProgress},
      );
      await db.customUpdate(
        'DELETE FROM bookshelf WHERE source_id=? AND novel_id=?',
        variables: variables,
        updates: {db.bookshelf},
      );
      await db.customUpdate(
        'DELETE FROM local_books WHERE digest=?',
        variables: [Variable(key.novelId)],
        updates: {db.localBooks},
      );
      checkLocalCancellation(cancellation);
    });
    // SQL is the visibility boundary. A failed filesystem cleanup is an
    // unindexed orphan recovered on restart; never restore a deleted book.
    try {
      final directory = p.join(paths.localBooks.path, key.novelId);
      if (await FileSystemEntity.type(directory, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await _deleteChild(paths.localBooks, directory);
      }
      return const LocalBookDeletion();
    } catch (_) {
      return const LocalBookDeletion(cleanupPending: true);
    }
  });

  @override
  Future<Result<Uint8List>> readMedia(
    MediaRef ref, {
    required CancellationToken cancellation,
  }) => _run(Operation.media, () async {
    checkLocalCancellation(cancellation);
    final parts = ref.mediaId.split('/');
    if (ref.sourceId != LocalBookIdentity.sourceId ||
        parts.length != 2 ||
        !parts.every(_digest.hasMatch)) {
      throw const FormatException('Invalid local media');
    }
    final published = await db
        .customSelect(
          'SELECT 1 FROM local_books WHERE digest=?',
          variables: [Variable(parts[0])],
        )
        .get();
    if (published.isEmpty) throw const FormatException('Unpublished book');
    final file = await _file(parts[0], parts[1]);
    if (await file.length() > maxMediaBytes) throw const _LimitExceeded();
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != parts[1]) {
      throw const FormatException('Media checksum mismatch');
    }
    checkLocalCancellation(cancellation);
    return bytes.asUnmodifiableView();
  });

  Future<File> _file(String digest, String name) async {
    final file = File(p.join(paths.localBooks.path, digest, name));
    final expected = p.join(
      await paths.localBooks.resolveSymbolicLinks(),
      digest,
      name,
    );
    if (await file.resolveSymbolicLinks() != expected) {
      throw const FileSystemException('Linked local file');
    }
    return file;
  }

  static Future<void> _deleteChild(Directory root, String path) async {
    final absolute = p.normalize(p.absolute(path));
    if (p.dirname(absolute) != p.normalize(root.absolute.path)) {
      throw const FileSystemException('Invalid cleanup path');
    }
    final type = await FileSystemEntity.type(absolute, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(absolute).delete(recursive: true);
    } else if (type == FileSystemEntityType.link) {
      await Link(absolute).delete();
    } else if (type == FileSystemEntityType.file) {
      await File(absolute).delete();
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _tail;
    _presentations.clear();
    _readCache = null;
  }
}

class _LimitExceeded implements Exception {
  const _LimitExceeded();
}

Future<int> _writeStream(
  File file,
  Stream<List<int>> bytes,
  int limit,
  CancellationToken cancellation,
) async {
  final iterator = StreamIterator(bytes);
  final handle = await file.open(mode: FileMode.write);
  var length = 0;
  try {
    while (await Future.any([
      iterator.moveNext(),
      cancellation.whenCancelled.then<bool>(
        (_) => throw const LocalCancelled(),
      ),
    ])) {
      checkLocalCancellation(cancellation);
      final chunk = iterator.current;
      length += chunk.length;
      if (length > limit) throw const _LimitExceeded();
      await handle.writeFrom(chunk);
    }
    checkLocalCancellation(cancellation);
    await handle.flush();
    return length;
  } finally {
    await iterator.cancel();
    await handle.close();
  }
}

class _ImportSession implements LocalImportSession {
  _ImportSession(this.key, this.dir, this.token, this.used);
  @override
  final NovelKey key;
  final Directory dir;
  final CancellationToken token;
  int used;
  bool active = true;
  final media = <String>{};
  final List<Future<MediaRef>> pending = [];
  Future<void> writes = Future.value();
  @override
  Stream<List<int>> openOriginal() {
    if (!active) throw StateError('Import session ended');
    return File(p.join(dir.path, 'original')).openRead();
  }

  @override
  Future<MediaRef> writeMedia(Stream<List<int>> bytes) {
    if (!active) throw StateError('Import session ended');
    final index = pending.length;
    if (index >= 4096) throw const _LimitExceeded();
    final future = writes.then((_) async {
      final file = File(p.join(dir.path, 'media-$index'));
      used += await _writeStream(
        file,
        bytes,
        (ManagedLocalBooks.maxBundleBytes - used).clamp(
          0,
          ManagedLocalBooks.maxMediaBytes,
        ),
        token,
      );
      if (used > ManagedLocalBooks.maxBundleBytes) throw const _LimitExceeded();
      final digest = (await sha256.bind(file.openRead()).first).toString();
      if (media.add(digest)) {
        await file.rename(p.join(dir.path, digest));
      } else {
        await file.delete();
      }
      return MediaRef(
        sourceId: LocalBookIdentity.sourceId,
        mediaId: '${key.novelId}/$digest',
      );
    });
    writes = future.then<void>((_) {}, onError: (Object _) {});
    pending.add(future);
    // Attach an error listener immediately, even for a misbehaving parser.
    unawaited(future.then<void>((_) {}, onError: (Object _) {}));
    return future;
  }

  Future<void> finish() async {
    active = false;
    await Future.wait(pending);
  }
}

// Keep validation, digest generation and potentially large JSON encoding off
// the UI isolate. The worker owns only immutable values, never the live store.
Future<List<int>> _encodeManifest(
  LocalBookContent content,
  NovelKey key,
  Set<String> media,
  LocalBookFormat format,
  DateTime importedAt,
  CancellationToken cancellation,
) => runParserWorker(() {
  ManagedLocalBooks._validate(content, key, media);
  return utf8.encode(
    jsonEncode({
      'version': 1,
      'navigation': content.navigation.map((e) => e.toJson()).toList(),
      'format': format.name,
      'importedAt': importedAt.toIso8601String(),
      'detail': RecordCodec.detail(content.detail),
      'catalog': RecordCodec.catalog(content.catalog),
      'chapters': content.chapters.map(RecordCodec.chapter).toList(),
      'media': media.toList()..sort(),
    }),
  );
}, cancellation);

Future<LocalBookRecord> _decodeManifest(
  List<int> bytes,
  NovelKey key,
  String hash,
  CancellationToken token,
) => runParserWorker(() {
  if (sha256.convert(bytes).toString() != hash) {
    throw const FormatException('Manifest checksum mismatch');
  }
  final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  if (map['version'] != 1) throw const FormatException('Unknown local codec');
  final content = LocalBookContent(
    detail: RecordCodec.readDetail(map['detail'] as String),
    catalog: RecordCodec.readCatalog(map['catalog'] as String),
    navigation: (map['navigation'] as List? ?? const []).map(
      (e) => LocalNavigationEntry.fromJson(e as Map<String, dynamic>),
    ),
    chapters: (map['chapters'] as List).cast<String>().map(
      RecordCodec.readChapter,
    ),
  );
  ManagedLocalBooks._validate(
    content,
    key,
    (map['media'] as List).cast<String>().toSet(),
  );
  return LocalBookRecord(
    content: content,
    format: LocalBookFormat.values.byName(map['format'] as String),
    importedAt: DateTime.parse(map['importedAt'] as String).toUtc(),
  );
}, token);

Future<(LocalBookContent, Map<String, String>)> _extractPresentations(
  List<int> bytes,
  NovelKey key,
  CancellationToken cancellation,
) => runParserWorker(() {
  if (sha256.convert(bytes).toString() != key.novelId) {
    throw const LocalParseException(LocalParseProblem.invalid);
  }
  final parser = EpubParser(
    Uint8List.fromList(bytes),
    key,
    'book.epub',
    includePresentations: true,
  );
  final parsed = parser.parse();
  if (parser.presentations.values.fold<int>(
        0,
        (sum, html) => sum + html.length,
      ) >
      16 * 1024 * 1024) {
    throw const LocalParseException(LocalParseProblem.tooLarge);
  }
  return (parsed.content, parser.presentations);
}, cancellation);
