part of 'managed_local_books.dart';

Future<LocalReparseResult> _reparse(
  ManagedLocalBooks store,
  NovelKey key,
  ChooseTxtEncoding choose,
  TxtEncoding? encoding,
  CancellationToken token,
) async {
  checkLocalCancellation(token);
  final old = await store._read(key, token: token);
  if (old == null) throw const FormatException('Missing book');
  final db = store.db;
  final library = LocalLibraryRepository(db);
  ReadingProgress? progress;
  String? stamp;
  String? previousBundle;
  await db.transaction(() async {
    checkLocalCancellation(token);
    final row = await _bookRow(store, key);
    if (row!.read<int>('maintenance') != 0) throw StateError('Book is busy');
    previousBundle = row.readNullable<String>('active_bundle');
    final read = await library.getProgress(key, cancellation: token);
    if (read is Failure<ReadingProgress?>) {
      throw StateError('Unreadable progress');
    }
    progress = (read as Success<ReadingProgress?>).value;
    stamp = await _progressStamp(store, key);
    await db.customStatement(
      'UPDATE local_books SET maintenance=1 WHERE digest=?',
      [key.novelId],
    );
  });
  store._invalidations.add(key);
  _PreparedReparse? prepared;
  var notified = false;
  try {
    prepared = await _prepareReparse(store, old, choose, encoding, token);
    final migration = await _migrate(
      old.content,
      prepared.content,
      progress,
      token,
    );
    checkLocalCancellation(token);
    await _renameReparse(store, key, prepared);
    await db.transaction(() async {
      checkLocalCancellation(token);
      final row = await _bookRow(store, key);
      if (row == null ||
          row.readNullable<String>('active_bundle') != previousBundle ||
          await _progressStamp(store, key) != stamp) {
        throw StateError('Progress changed');
      }
      await _publishReparse(store, key, prepared!, migration);
      checkLocalCancellation(token);
    });
    store._reparseChanged(key);
    notified = true;
    return LocalReparseResult(
      approximate: migration.approximate,
      cleanupPending: !await store._cleanRevisions(
        key.novelId,
        prepared.bundle,
      ),
    );
  } finally {
    try {
      await _discardReparse(store, key, prepared);
      await db.customStatement(
        'UPDATE local_books SET maintenance=0 WHERE digest=?',
        [key.novelId],
      );
    } finally {
      if (!notified) await _refreshUncertainPublication(store, key, prepared);
    }
  }
}

final class _PreparedReparse {
  _PreparedReparse(this.stage, this.content, this.hash)
    : bundle = sha256.convert(utf8.encode(p.basename(stage.path))).toString();
  Directory stage;
  final LocalBookContent content;
  final String hash;
  final String bundle;
  bool published = false;
}

Future<_PreparedReparse> _prepareReparse(
  ManagedLocalBooks store,
  LocalBookRecord old,
  ChooseTxtEncoding choose,
  TxtEncoding? encoding,
  CancellationToken token,
) async {
  final key = old.content.detail.summary.key;
  final stage = await store.paths.localImportStaging.createTemp('import-');
  _ImportSession? session;
  var ready = false;
  try {
    final original = await store._file(key.novelId, 'original');
    final copy = File(p.join(stage.path, 'original'));
    await _writeStream(
      copy,
      original.openRead(),
      ManagedLocalBooks.maxOriginalBytes,
      token,
    );
    if ((await sha256.bind(copy.openRead()).first).toString() != key.novelId) {
      throw const _OriginalCorrupt();
    }
    session = _ImportSession(key, stage, token, await copy.length());
    final parsed = await store._automaticDecoder.decode(
      session,
      format: old.format,
      filename: '${old.content.detail.summary.title}.${old.format.name}',
      cancellation: token,
      chooseEncoding: choose,
      encoding: encoding ?? old.content.txtEncoding,
    );
    await session.finish();
    final written = await _writeParsedArtifacts(
      stage: stage,
      key: key,
      content: parsed,
      session: session,
      format: old.format,
      importedAt: old.importedAt,
      original: copy,
      token: token,
    );
    await copy.delete();
    checkLocalCancellation(token);
    ready = true;
    return _PreparedReparse(
      stage,
      written.content,
      sha256.convert(written.manifest).toString(),
    );
  } finally {
    try {
      await session?.finish();
    } catch (_) {
      /* Primary outcome wins. */
    }
    if (!ready) {
      try {
        await ManagedLocalBooks._deleteChild(
          store.paths.localImportStaging,
          stage.path,
        );
      } catch (_) {
        /* Startup recovers staging. */
      }
    }
  }
}

Future<QueryRow?> _bookRow(ManagedLocalBooks store, NovelKey key) => store.db
    .customSelect(
      'SELECT * FROM local_books WHERE digest=?',
      variables: [Variable(key.novelId)],
    )
    .getSingleOrNull();

Future<String> _progressStamp(ManagedLocalBooks store, NovelKey key) async {
  final row = await store.db
      .customSelect(
        'SELECT generation,sequence FROM progress_sessions WHERE source_id=? AND novel_id=?',
        variables: [Variable(key.sourceId.value), Variable(key.novelId)],
      )
      .getSingleOrNull();
  return row == null
      ? 'none'
      : '${row.read<int>('generation')}:${row.read<int>('sequence')}';
}

Future<void> _renameReparse(
  ManagedLocalBooks store,
  NovelKey key,
  _PreparedReparse prepared,
) async {
  final revisions = Directory(
    p.join(store.paths.localBooks.path, key.novelId, 'revisions'),
  );
  await revisions.create();
  if (await revisions.resolveSymbolicLinks() !=
      p.join(
        await store.paths.localBooks.resolveSymbolicLinks(),
        key.novelId,
        'revisions',
      )) {
    throw const FileSystemException('Linked revisions');
  }
  prepared.stage = await prepared.stage.rename(
    p.join(revisions.path, prepared.bundle),
  );
  prepared.published = true;
}

/// Caller owns the transaction and verifies its baseline inside that transaction.
Future<void> _publishReparse(
  ManagedLocalBooks store,
  NovelKey key,
  _PreparedReparse prepared,
  ReparsedPosition migration,
) async {
  final db = store.db;
  final content = prepared.content;
  final vars = [Variable(key.sourceId.value), Variable(key.novelId)];
  await db.customUpdate(
    'UPDATE local_books SET active_bundle=?,manifest_hash=?,parser_version=?,title=?,maintenance=0 WHERE digest=?',
    variables: [
      Variable(prepared.bundle),
      Variable(prepared.hash),
      Variable(BookDecoder.parserVersion),
      Variable(content.detail.summary.title),
      Variable(key.novelId),
    ],
    updates: {db.localBooks},
  );
  await db.customUpdate(
    'UPDATE bookshelf SET summary_json=? WHERE source_id=? AND novel_id=?',
    variables: [Variable(RecordCodec.summary(content.detail.summary)), ...vars],
    updates: {db.bookshelf},
  );
  if (migration.progress case final value?) {
    await writeProgressRow(db, value, DateTime.now());
  }
  await db.customUpdate(
    'INSERT INTO progress_sessions(source_id,novel_id,generation,sequence) VALUES(?,?,1,-1) ON CONFLICT(source_id,novel_id) DO UPDATE SET generation=generation+1,sequence=-1',
    variables: vars,
    updates: {db.progressSessions},
  );
  await db.customUpdate(
    'DELETE FROM local_chapter_revisions WHERE digest=?',
    variables: [Variable(key.novelId)],
    updates: {db.localChapterRevisions},
  );
  for (final c in content.chapters) {
    await db.customStatement(
      'INSERT INTO local_chapter_revisions(digest,chapter_id,content_revision,catalog_revision) VALUES(?,?,?,?)',
      [
        key.novelId,
        c.key.chapterId,
        c.contentRevision,
        content.catalog.revision,
      ],
    );
  }
  await db.customUpdate(
    'DELETE FROM local_reparse_attempts WHERE digest=?',
    variables: [Variable(key.novelId)],
    updates: {db.localReparseAttempts},
  );
}

Future<void> _discardReparse(
  ManagedLocalBooks store,
  NovelKey key,
  _PreparedReparse? prepared,
) async {
  if (prepared == null) return;
  try {
    if (prepared.published) {
      // A lost COMMIT acknowledgement must never delete the active candidate.
      final row = await _bookRow(store, key);
      if (row == null ||
          row.readNullable<String>('active_bundle') == prepared.bundle) {
        return;
      }
    }
    await ManagedLocalBooks._deleteChild(
      prepared.stage.parent,
      prepared.stage.path,
    );
  } catch (_) {
    /* Startup checks the durable pointer before reclaiming. */
  }
}

/// A lost commit acknowledgement can leave the new pointer durable. Forget
/// old rendition caches even when that pointer cannot currently be queried.
Future<void> _refreshUncertainPublication(
  ManagedLocalBooks store,
  NovelKey key,
  _PreparedReparse? prepared,
) async {
  store._readCache = null;
  store._presentations.remove(key);
  store._svgLinksScanned.remove(key);
  if (prepared?.published != true) return;
  try {
    final row = await _bookRow(store, key);
    if (row?.readNullable<String>('active_bundle') == prepared!.bundle) {
      store._changes.add(key);
    }
  } catch (_) {
    /* Startup recovery remains authoritative. */
  }
}

class _OriginalCorrupt extends FormatException {
  const _OriginalCorrupt() : super('Original checksum');
}

Future<ReparsedPosition> _migrate(
  LocalBookContent old,
  LocalBookContent next,
  ReadingProgress? progress,
  CancellationToken token,
) => runParserWorker(() => migrateLocalPosition(old, next, progress), token);
