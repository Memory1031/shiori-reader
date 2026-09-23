import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../domain/reparse_position.dart';
import '../repositories/library_repository.dart';
import 'book_decoder.dart';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import 'database/user_database.dart' show UserDatabase;
import 'files/app_paths.dart';
import 'local_guard.dart';
import 'library_rows.dart';
import 'parser_worker.dart';
import '../../domain/contracts/local_book_decoder.dart';
import 'record_codec.dart';
import 'epub/epub_parser.dart';

part 'local_book_reparse.dart';

/// Durable imported originals and normalized content. Never uses cache.db.
/// Single owner, serialized operations; initialize/recover before exposure.
class ManagedLocalBooks
    implements
        LocalBookStore,
        LocalBookManagement,
        LocalPagePresentationRepository,
        LocalBookLinkStore,
        LocalBookReparse {
  ManagedLocalBooks._(this.paths, this.db);
  final AppPaths paths;
  final UserDatabase db;
  final _invalidations = StreamController<NovelKey>.broadcast(sync: true);
  final _changes = StreamController<NovelKey>.broadcast();
  @override
  Stream<NovelKey> get changes => _changes.stream;
  @override
  Stream<NovelKey> get invalidations => _invalidations.stream;
  @override
  Future<Result<LocalReparseResult>> reparseBook(
    NovelKey key, {
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
    required CancellationToken cancellation,
  }) => _run(
    Operation.libraryWrite,
    () => _reparse(this, key, chooseEncoding, encoding, cancellation),
  );

  (NovelKey, String, DateTime, int, LocalBookRecord)? _readCache;
  final _presentations = <NovelKey, (LocalBookContent, Map<String, String>)>{};
  final _svgLinksScanned = <NovelKey>{};
  @override
  Future<Result<String?>> loadPagePresentation(
    ChapterKey chapter, {
    required CancellationToken cancellation,
  }) => _run(Operation.chapter, () async {
    checkLocalCancellation(cancellation);
    final record = await _read(chapter.novelKey, token: cancellation);
    if (record == null || record.format != LocalBookFormat.epub) return null;
    await _loadPresentations(chapter.novelKey, record, cancellation);
    return _presentations[chapter.novelKey]?.$2[chapter.chapterId];
  });

  @override
  Future<Result<List<LocalContentLink>>> loadContentLinks(
    ChapterKey source, {
    required CancellationToken cancellation,
  }) async {
    final result = await _run<List<LocalContentLink>?>(
      Operation.chapter,
      () async {
        checkLocalCancellation(cancellation);
        final record = await _read(source.novelKey, token: cancellation);
        if (record == null) return null;
        final stored = record.content.links
            .where((link) => link.source == source)
            .toList();
        if (record.format != LocalBookFormat.epub ||
            stored.any((link) => link.region != null)) {
          return stored;
        }

        // A previously imported book can gain its SVG rendition on demand,
        // while its older manifest still has no hotspot side table. Reuse the
        // already bounded presentation parse without changing stored chapters.
        await _loadPresentations(source.novelKey, record, cancellation);
        var derived = _presentations[source.novelKey];
        if (derived != null &&
            derived.$2[source.chapterId]?.contains('shiori-svg-page') == true &&
            !_svgLinksScanned.contains(source.novelKey)) {
          // Older reparse bundles retained the rendition but not its link side
          // table. Recover the matching page from the immutable original too.
          final original = await _file(source.novelKey.novelId, 'original');
          if (await original.length() > 64 * 1024 * 1024) {
            throw const _LimitExceeded();
          }
          final extracted = await _extractPresentations(
            await original.readAsBytes(),
            source.novelKey,
            cancellation,
          );
          // A successful scan is conclusive even when the book has no links.
          _svgLinksScanned.add(source.novelKey);
          final revisions = {
            for (final chapter in [
              ...record.content.chapters,
              ...record.content.auxiliaryChapters,
            ])
              chapter.key: chapter.contentRevision,
          };
          final matchingPages = {
            for (final chapter in [
              ...extracted.$1.chapters,
              ...extracted.$1.auxiliaryChapters,
            ])
              if (revisions[chapter.key] == chapter.contentRevision &&
                  extracted.$2.containsKey(chapter.key.chapterId))
                chapter.key.chapterId: extracted.$2[chapter.key.chapterId]!,
          };
          if (matchingPages.containsKey(source.chapterId)) {
            derived = (extracted.$1, {...derived.$2, ...matchingPages});
            _presentations[source.novelKey] = derived;
          }
        }
        if (derived == null || !derived.$2.containsKey(source.chapterId)) {
          return stored;
        }
        final oldChapters = {
          for (final chapter in [
            ...record.content.chapters,
            ...record.content.auxiliaryChapters,
          ])
            chapter.key: chapter,
        };
        final newChapters = {
          for (final chapter in [
            ...derived.$1.chapters,
            ...derived.$1.auxiliaryChapters,
          ])
            chapter.key: chapter,
        };
        final oldSource = oldChapters[source];
        final newSource = newChapters[source];
        if (oldSource == null ||
            newSource == null ||
            oldSource.contentRevision != newSource.contentRevision) {
          return stored;
        }
        final sourceBlocks = oldSource.blocks.map((b) => b.blockKey).toSet();
        final hotspots = derived.$1.links.where((link) {
          if (link.source != source ||
              link.region == null ||
              !sourceBlocks.contains(link.sourceBlockKey)) {
            return false;
          }
          final target = link.target;
          if (target == null) return true;
          final oldTarget = oldChapters[target];
          return oldTarget != null &&
              (link.targetBlockKey == null ||
                  oldTarget.blocks.any(
                    (block) => block.blockKey == link.targetBlockKey,
                  ));
        });
        return [...stored, ...hotspots];
      },
    );
    if (result case Failure(:final failure)) return Failure(failure);
    final links = (result as Success<List<LocalContentLink>?>).value;
    return links == null
        ? Failure(
            AppFailure(
              kind: FailureKind.notFound,
              operation: Operation.chapter,
            ),
          )
        : Success(links);
  }

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
          .customSelect('SELECT digest,active_bundle FROM local_books')
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
      for (final row in rows) {
        await store._cleanRevisions(
          row.read<String>('digest'),
          row.readNullable<String>('active_bundle'),
        );
      }
      await db.customStatement('UPDATE local_books SET maintenance=0');
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
          'INSERT INTO local_books(digest,format,title,imported_at,manifest_hash,parser_version) VALUES(?,?,?,?,?,?)',
          [
            digest,
            format.name,
            content.detail.summary.title,
            importedAt.millisecondsSinceEpoch,
            sha256.convert(manifest).toString(),
            BookDecoder.parserVersion,
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
    final allChapters = [...content.chapters, ...content.auxiliaryChapters];
    final byKey = {for (final c in allChapters) c.key: c};
    if (byKey.length != allChapters.length ||
        content.auxiliaryChapters.length > 64 ||
        content.links.length > 10000 ||
        allChapters.any((c) => c.key.novelKey != key)) {
      throw const FormatException('Invalid auxiliary chapters');
    }
    final mainKeys = content.chapters.map((c) => c.key).toSet();
    final order = content.readingOrder;
    if (order != null &&
        (order.toSet().length != order.length ||
            order.any((k) => !mainKeys.contains(k)))) {
      throw const FormatException('Invalid reading order');
    }
    final blocksByChapter = {
      for (final c in allChapters)
        c.key: c.blocks.map((b) => b.blockKey).toSet(),
    };
    for (final link in content.links) {
      if (!(blocksByChapter[link.source]?.contains(link.sourceBlockKey) ??
              false) ||
          link.target != null &&
              (!byKey.containsKey(link.target) ||
                  link.targetBlockKey != null &&
                      !(blocksByChapter[link.target]?.contains(
                            link.targetBlockKey,
                          ) ??
                          false))) {
        throw const FormatException('Invalid local link');
      }
    }
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
      refs.addAll(content.chapters[i].blocks.expand((b) => b.mediaRefs));
    }
    for (final c in content.auxiliaryChapters) {
      refs.addAll(c.blocks.expand((b) => b.mediaRefs));
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
    final bundle = row.readNullable<String>('active_bundle');
    final file = await _file(key.novelId, 'manifest.json', bundle: bundle);
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
    _readCache = (key, hash, stat.modified, stat.size, record);
    return record;
  }

  Future<void> _loadPresentations(
    NovelKey key,
    LocalBookRecord record,
    CancellationToken token,
  ) async {
    if (_presentations.containsKey(key)) return;
    final row = await db
        .customSelect(
          'SELECT active_bundle,manifest_hash FROM local_books WHERE digest=?',
          variables: [Variable(key.novelId)],
        )
        .getSingle();
    final bundle = row.readNullable<String>('active_bundle');
    if (!_presentations.containsKey(key)) {
      Map<String, String> html;
      var derivedContent = record.content;
      if (bundle != null) {
        final f = await _file(
          key.novelId,
          'presentations.json',
          bundle: bundle,
        );
        if (await f.length() > 32 * 1024 * 1024) throw const _LimitExceeded();
        final manifestFile = await _file(
          key.novelId,
          'manifest.json',
          bundle: bundle,
        );
        if (await manifestFile.length() > maxManifestBytes) {
          throw const _LimitExceeded();
        }
        final manifestBytes = await manifestFile.readAsBytes();
        if (sha256.convert(manifestBytes).toString() !=
            row.read<String>('manifest_hash')) {
          throw const FormatException('Manifest checksum');
        }
        final manifest =
            jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
        final bytes = await f.readAsBytes();
        if (sha256.convert(bytes).toString() != manifest['presentationHash']) {
          throw const FormatException('Presentation checksum');
        }
        html = (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)
            .cast<String, String>();
      } else {
        final original = await _file(key.novelId, 'original');
        if (await original.length() > 64 * 1024 * 1024) {
          throw const _LimitExceeded();
        }
        final extracted = await _extractPresentations(
          await original.readAsBytes(),
          key,
          token,
        );
        derivedContent = extracted.$1;
        // Legacy presentation may be derived, but never replace persisted
        // semantics or show a rendition for a different content revision.
        final revisions = {
          for (final c in [
            ...record.content.chapters,
            ...record.content.auxiliaryChapters,
          ])
            c.key: c.contentRevision,
        };
        html = {
          for (final c in [
            ...extracted.$1.chapters,
            ...extracted.$1.auxiliaryChapters,
          ])
            if (revisions[c.key] == c.contentRevision &&
                extracted.$2.containsKey(c.key.chapterId))
              c.key.chapterId: extracted.$2[c.key.chapterId]!,
        };
      }
      checkLocalCancellation(token);
      _presentations.clear();
      _svgLinksScanned.clear();
      _presentations[key] = (derivedContent, html);
      // The original was fully scanned above. Reparse bundles only persist
      // rendered HTML; even a current-version manifest may lack SVG links.
      if (bundle == null) {
        _svgLinksScanned.add(key);
      }
    }
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
    _svgLinksScanned.remove(key);
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
        'DELETE FROM local_chapter_revisions WHERE digest=?',
        variables: [Variable(key.novelId)],
        updates: {db.localChapterRevisions},
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
          'SELECT active_bundle FROM local_books WHERE digest=?',
          variables: [Variable(parts[0])],
        )
        .get();
    if (published.isEmpty) throw const FormatException('Unpublished book');
    final file = await _file(
      parts[0],
      parts[1],
      bundle: published.single.readNullable<String>('active_bundle'),
    );
    if (await file.length() > maxMediaBytes) throw const _LimitExceeded();
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != parts[1]) {
      throw const FormatException('Media checksum mismatch');
    }
    checkLocalCancellation(cancellation);
    return bytes.asUnmodifiableView();
  });

  Future<File> _file(String digest, String name, {String? bundle}) async {
    if (bundle != null && !_digest.hasMatch(bundle)) {
      throw const FormatException('Invalid bundle');
    }
    final relative = bundle == null ? name : p.join('revisions', bundle, name);
    final file = File(p.join(paths.localBooks.path, digest, relative));
    final expected = p.join(
      await paths.localBooks.resolveSymbolicLinks(),
      digest,
      relative,
    );
    if (await file.resolveSymbolicLinks() != expected) {
      throw const FileSystemException('Linked local file');
    }
    return file;
  }

  Future<bool> _cleanRevisions(String digest, String? active) async {
    try {
      if (!_digest.hasMatch(digest) ||
          active != null && !_digest.hasMatch(active)) {
        return false;
      }
      if (active != null) {
        final manifest = await _file(digest, 'manifest.json', bundle: active);
        final row = await db
            .customSelect(
              'SELECT manifest_hash FROM local_books WHERE digest=?',
              variables: [Variable(digest)],
            )
            .getSingle();
        if (await manifest.length() > maxManifestBytes ||
            sha256.convert(await manifest.readAsBytes()).toString() !=
                row.read<String>('manifest_hash')) {
          return false;
        }
      }
      final root = Directory(p.join(paths.localBooks.path, digest));
      if (await root.resolveSymbolicLinks() !=
          p.join(await paths.localBooks.resolveSymbolicLinks(), digest)) {
        return false;
      }
      final revisions = Directory(p.join(root.path, 'revisions'));
      if (await revisions.exists()) {
        if (await revisions.resolveSymbolicLinks() !=
            p.join(await root.resolveSymbolicLinks(), 'revisions')) {
          return false;
        }
        await for (final entry in revisions.list(followLinks: false)) {
          if (_digest.hasMatch(p.basename(entry.path)) &&
              p.basename(entry.path) != active) {
            await _deleteChild(revisions, entry.path);
          }
        }
      }
      if (active != null) {
        await for (final entry in root.list(followLinks: false)) {
          final name = p.basename(entry.path);
          if (name == 'manifest.json' || _digest.hasMatch(name)) {
            await _deleteChild(root, entry.path);
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
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
    await _invalidations.close();
    await _changes.close();
    _presentations.clear();
    _svgLinksScanned.clear();
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
  CancellationToken cancellation, [
  String? presentationHash,
]) => runParserWorker(() {
  ManagedLocalBooks._validate(content, key, media);
  return utf8.encode(
    jsonEncode({
      'version': 1,
      'presentationHash': presentationHash,
      'txtEncoding': content.txtEncoding?.name,
      'navigation': content.navigation.map((e) => e.toJson()).toList(),
      'auxiliaryChapters': content.auxiliaryChapters
          .map(RecordCodec.chapter)
          .toList(),
      'links': content.links.map((e) => e.toJson()).toList(),
      'readingOrder': content.readingOrder?.map((k) => k.toJson()).toList(),
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
    auxiliaryChapters: (map['auxiliaryChapters'] as List? ?? const [])
        .cast<String>()
        .map(RecordCodec.readChapter),
    links: (map['links'] as List? ?? const []).map(
      (e) => LocalContentLink.fromJson(e as Map<String, dynamic>),
    ),
    readingOrder: (map['readingOrder'] as List?)?.map(
      (e) => ChapterKey.fromJson(e as Map<String, dynamic>),
    ),
    txtEncoding: map['txtEncoding'] == null
        ? null
        : TxtEncoding.values.byName(map['txtEncoding'] as String),
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
