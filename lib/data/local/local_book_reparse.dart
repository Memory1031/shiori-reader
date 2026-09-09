part of 'managed_local_books.dart';

Future<LocalReparseResult> _reparse(
  ManagedLocalBooks store,
  NovelKey key,
  ChooseTxtEncoding choose,
  TxtEncoding? encoding,
  CancellationToken token,
) async {
  checkLocalCancellation(token);
  // _read validates the published manifest before any maintenance starts.
  final old = await store._read(key, token: token);
  if (old == null) throw const FormatException('Missing book');
  final db = store.db;
  final vars = [Variable(key.sourceId.value), Variable(key.novelId)];
  final library = LocalLibraryRepository(db);
  ReadingProgress? progress;
  String? stamp;
  String? previousBundle;
  Future<String> currentStamp() async {
    final row = await db
        .customSelect(
          'SELECT generation,sequence FROM progress_sessions WHERE source_id=? AND novel_id=?',
          variables: vars,
        )
        .getSingleOrNull();
    return row == null
        ? 'none'
        : '${row.read<int>('generation')}:${row.read<int>('sequence')}';
  }

  await db.transaction(() async {
    checkLocalCancellation(token);
    final row = await db
        .customSelect(
          'SELECT active_bundle,maintenance FROM local_books WHERE digest=?',
          variables: [Variable(key.novelId)],
        )
        .getSingle();
    if (row.read<int>('maintenance') != 0) throw StateError('Book is busy');
    previousBundle = row.readNullable<String>('active_bundle');
    final read = await library.getProgress(key, cancellation: token);
    if (read is Failure<ReadingProgress?>) {
      throw StateError('Unreadable progress');
    }
    progress = (read as Success<ReadingProgress?>).value;
    stamp = await currentStamp();
    await db.customStatement(
      'UPDATE local_books SET maintenance=1 WHERE digest=?',
      [key.novelId],
    );
  });
  store._invalidations.add(key);
  Directory? stage;
  Directory? published;
  _ImportSession? session;
  var committed = false;
  try {
    stage = await store.paths.localImportStaging.createTemp('import-');
    final original = await store._file(key.novelId, 'original');
    final copy = File(p.join(stage.path, 'original'));
    await _writeStream(
      copy,
      original.openRead(),
      ManagedLocalBooks.maxOriginalBytes,
      token,
    );
    if ((await sha256.bind(copy.openRead()).first).toString() != key.novelId) {
      throw const FormatException('Original checksum');
    }
    session = _ImportSession(key, stage, token, await copy.length());
    final content = await const BookDecoder().decode(
      session,
      format: old.format,
      filename: '${old.content.detail.summary.title}.${old.format.name}',
      cancellation: token,
      chooseEncoding: choose,
      encoding: encoding ?? old.content.txtEncoding,
    );
    await session.finish();
    List<int>? html;
    if (old.format == LocalBookFormat.epub) {
      final extracted = await _extractPresentations(
        await copy.readAsBytes(),
        key,
        token,
      );
      html = utf8.encode(jsonEncode(extracted.$2));
      if (html.length > 32 * 1024 * 1024) throw const _LimitExceeded();
      await File(
        p.join(stage.path, 'presentations.json'),
      ).writeAsBytes(html, flush: true);
    }
    final manifest = await _encodeManifest(
      content,
      key,
      session.media,
      old.format,
      old.importedAt,
      token,
      html == null ? null : sha256.convert(html).toString(),
    );
    if (manifest.length > ManagedLocalBooks.maxManifestBytes ||
        session.used + manifest.length + (html?.length ?? 0) >
            ManagedLocalBooks.maxBundleBytes) {
      throw const _LimitExceeded();
    }
    await File(
      p.join(stage.path, 'manifest.json'),
    ).writeAsBytes(manifest, flush: true);
    final migration = await _migrate(old.content, content, progress, token);
    await copy.delete(); // Original stays immutable in the book root.
    checkLocalCancellation(token);
    final bundle = sha256
        .convert(utf8.encode(p.basename(stage.path)))
        .toString();
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
    published = await stage.rename(p.join(revisions.path, bundle));
    await db.transaction(() async {
      checkLocalCancellation(token);
      final row = await db
          .customSelect(
            'SELECT active_bundle FROM local_books WHERE digest=?',
            variables: [Variable(key.novelId)],
          )
          .getSingleOrNull();
      if (row == null ||
          row.readNullable<String>('active_bundle') != previousBundle ||
          await currentStamp() != stamp) {
        throw StateError('Progress changed');
      }
      await db.customUpdate(
        'UPDATE local_books SET active_bundle=?,manifest_hash=?,parser_version=2,title=?,maintenance=0 WHERE digest=?',
        variables: [
          Variable(bundle),
          Variable(sha256.convert(manifest).toString()),
          Variable(content.detail.summary.title),
          Variable(key.novelId),
        ],
        updates: {db.localBooks},
      );
      await db.customUpdate(
        'UPDATE bookshelf SET summary_json=? WHERE source_id=? AND novel_id=?',
        variables: [
          Variable(RecordCodec.summary(content.detail.summary)),
          ...vars,
        ],
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
      checkLocalCancellation(token);
    });
    committed = true;
    store._readCache = null;
    store._presentations.remove(key);
    store._changes.add(key);
    return LocalReparseResult(
      approximate: migration.approximate,
      cleanupPending: !await store._cleanRevisions(key.novelId, bundle),
    );
  } finally {
    try {
      await session?.finish();
    } catch (_) {
      /* Primary outcome wins. */
    }
    try {
      if (!committed && published != null) {
        await ManagedLocalBooks._deleteChild(published.parent, published.path);
      }
      if (stage != null && await stage.exists()) {
        await ManagedLocalBooks._deleteChild(
          store.paths.localImportStaging,
          stage.path,
        );
      }
    } catch (_) {
      /* Startup recovers unreferenced staging. */
    }
    if (!committed) {
      await db.customStatement(
        'UPDATE local_books SET maintenance=0 WHERE digest=?',
        [key.novelId],
      );
    }
  }
}

Future<ReparsedPosition> _migrate(
  LocalBookContent old,
  LocalBookContent next,
  ReadingProgress? progress,
  CancellationToken token,
) => runParserWorker(() => migrateLocalPosition(old, next, progress), token);
