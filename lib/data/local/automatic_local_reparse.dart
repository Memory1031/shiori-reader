part of 'managed_local_books.dart';

/// App-lifetime limits; resumed never replenishes these budgets.
const automaticReparseInitialDelay = Duration(seconds: 10);
const automaticReparsePrepareBudget = Duration(minutes: 3);
const automaticReparseBookBudget = 15;

class _AmbiguousEncoding implements Exception {}

final class _BookUse implements LocalBookUse {
  _BookUse(this.store, this.key, this.id);
  final ManagedLocalBooks store;
  final NovelKey key;
  final int id;
  bool released = false;
  final done = Completer<void>();
  @override
  Future<void> release({bool? progressSaved}) async {
    if (released) return;
    released = true;
    final readers = store._bookUses[key]!;
    readers.remove(this);
    if (readers.isEmpty) store._bookUses.remove(key);
    if (progressSaved == false) {
      final failure = store._unsafeProgress[key] ?? -1;
      if (id > failure) store._unsafeProgress[key] = id;
    } else if (progressSaved == true &&
        id >= (store._unsafeProgress[key] ?? -1)) {
      store._unsafeProgress.remove(key);
    }
    done.complete();
    store._wakeAutomatic();
  }
}

final class _AutoPrepared {
  _AutoPrepared(this.key, this.old, this.baseline, this.prepared);
  final NovelKey key;
  final LocalBookRecord old;
  final Map<String, Object?> baseline;
  final _PreparedReparse prepared;
}

extension _AutomaticReparse on ManagedLocalBooks {
  bool get _mayStartAutomatic =>
      !_closed &&
      !_autoStopped &&
      _autoReady &&
      _autoForeground &&
      _manualOperations == 0 &&
      (_autoStorageRetryAt == null ||
          !_autoNow().isBefore(_autoStorageRetryAt!));

  void _wakeAutomatic() {
    if (!_mayStartAutomatic) return;
    _autoWakeRequested = true;
    if (_autoRun != null) return;
    _autoRun = _automaticLoop().whenComplete(() {
      _autoRun = null;
      if (_autoWakeRequested && _mayStartAutomatic) _wakeAutomatic();
    });
  }

  Future<void> _automaticLoop() async {
    try {
      do {
        _autoWakeRequested = false;
        await _automaticCycle();
      } while (_autoWakeRequested && _mayStartAutomatic);
    } catch (_) {
      // Discovery/database failure must never escape into application startup.
    }
  }

  Future<void> _automaticCycle() async {
    if (_autoPending case final pending?) {
      final source = _autoCancellation = CancellationSource();
      try {
        if (!await _tryAutomaticCommit(pending)) {
          await _writeAutomaticAttempt(pending.key, 'preparedWaiting');
          checkLocalCancellation(source.token);
        }
      } catch (error) {
        if (error is LocalCancelled || source.token.isCancelled) {
          await _cancelAutomaticAttempt(pending.key);
        } else {
          await _automaticFailure(pending.key, error);
        }
        await _finishAutoCandidate(pending);
      } finally {
        _autoCancellation = null;
      }
    }
    if (!_mayStartAutomatic ||
        _autoBooksStarted >= _autoMaxBooks ||
        _autoPrepareTime >= _autoTimeBudget) {
      return;
    }
    final rows = await db
        .customSelect(
          '''
SELECT l.digest FROM local_books l
LEFT JOIN bookshelf b ON b.source_id='local' AND b.novel_id=l.digest
LEFT JOIN reading_progress r ON r.source_id='local' AND r.novel_id=l.digest
LEFT JOIN local_reparse_attempts a ON a.digest=l.digest AND a.target_parser_version=?
WHERE l.parser_version < ? AND l.maintenance=0 AND l.format IN ('epub','txt')
AND (a.digest IS NULL OR ((a.failure_count < 5 OR a.outcome='lowStorage') AND a.next_retry_at IS NOT NULL AND a.next_retry_at <= ?))
ORDER BY (b.novel_id IS NOT NULL) DESC, (r.last_read_at IS NOT NULL) DESC,
r.last_read_at DESC, l.imported_at DESC, l.digest
''',
          variables: [
            Variable(BookDecoder.parserVersion),
            Variable(BookDecoder.parserVersion),
            Variable(_autoNow().millisecondsSinceEpoch),
          ],
        )
        .get();
    for (final row in rows) {
      if (!_mayStartAutomatic ||
          _autoBooksStarted >= _autoMaxBooks ||
          _autoPrepareTime >= _autoTimeBudget) {
        break;
      }
      final key = LocalBookIdentity.book(row.read<String>('digest'));
      if (_autoAttempted.contains(key) || _autoPending?.key == key) continue;
      // Keep at most one waiting bundle, while allowing all idle books through.
      if (_autoPending != null &&
          (_bookUses[key]?.isNotEmpty == true ||
              _unsafeProgress.containsKey(key))) {
        continue;
      }
      _autoAttempted.add(key);
      final source = _autoCancellation = CancellationSource();
      _PreparedReparse? prepared;
      var pendingOwnsStage = false;
      Stopwatch? work;
      Timer? deadline;
      try {
        final baseline = await _bookRow(this, key);
        if (baseline == null ||
            baseline.read<int>('parser_version') >= BookDecoder.parserVersion ||
            baseline.read<int>('maintenance') != 0) {
          continue;
        }
        if (!_mayStartAutomatic) {
          source.cancel();
          checkLocalCancellation(source.token);
        }
        work = _autoWorkClock = _autoClock()..start();
        deadline = Timer(_autoTimeBudget - _autoPrepareTime, source.cancel);
        if (_autoFreeSpace != null) {
          final free = await Future.any<int?>([
            _autoFreeSpace!(paths.localBooks),
            source.token.whenCancelled.then<int?>(
              (_) => throw const LocalCancelled(),
            ),
          ]);
          // Reserve the bounded maximum new bundle plus bounded input copy.
          // This is a conservative refusal threshold, not an EPUB size guess.
          if (free != null &&
              free <
                  ManagedLocalBooks.maxBundleBytes +
                      ManagedLocalBooks.maxOriginalBytes +
                      32 * 1024 * 1024) {
            throw const _LowStorage();
          }
        }
        checkLocalCancellation(source.token);
        // Capacity refusal is not a started book. Persist before actual input
        // work so only interrupted active work gets crash backoff on restart.
        _autoBooksStarted++;
        await _writeAutomaticAttempt(key, 'running');
        final old = await _read(key, token: source.token);
        if (old == null) throw const _OriginalCorrupt();
        prepared = await _prepareReparse(
          this,
          old,
          (preview) async {
            final saved = old.content.txtEncoding;
            if (saved != null && preview.samples.containsKey(saved)) {
              return saved;
            }
            throw _AmbiguousEncoding();
          },
          old.content.txtEncoding,
          source.token,
        );
        work.stop();
        deadline.cancel();
        _autoPrepareTime += work.elapsed;
        _autoWorkClock = null;
        work = null;
        final candidate = _AutoPrepared(
          key,
          old,
          Map.of(baseline.data),
          prepared,
        );
        checkLocalCancellation(source.token);
        if (!await _tryAutomaticCommit(candidate)) {
          // A different deferred bundle cannot be displaced by another reader.
          if (_autoPending == null) {
            await _writeAutomaticAttempt(key, 'preparedWaiting');
            checkLocalCancellation(source.token);
            _autoPending = candidate;
            pendingOwnsStage = true;
          } else {
            await _cancelAutomaticAttempt(key);
          }
        }
      } catch (error) {
        if (work != null) {
          work.stop();
          _autoPrepareTime += work.elapsed;
          work = null;
        }
        if (error is LocalCancelled) {
          await _cancelAutomaticAttempt(key);
        } else {
          await _automaticFailure(key, error);
        }
      } finally {
        deadline?.cancel();
        if (work != null) {
          work.stop();
          _autoPrepareTime += work.elapsed;
        }
        if (!pendingOwnsStage) await _discardReparse(this, key, prepared);
        _autoCancellation = null;
        _autoWorkClock = null;
      }
    }
  }

  Future<bool> _tryAutomaticCommit(_AutoPrepared candidate) async {
    final key = candidate.key;
    if (!_mayStartAutomatic ||
        _bookUses[key]?.isNotEmpty == true ||
        _unsafeProgress.containsKey(key)) {
      return false;
    }
    final token = _autoCancellation?.token ?? CancellationSource().token;
    await _writeAutomaticAttempt(key, 'running');
    final stamp = await _progressStamp(this, key);
    final read = await LocalLibraryRepository(
      db,
    ).getProgress(key, cancellation: token);
    if (read case Failure(:final failure)) {
      if (failure.isCancellation) throw const LocalCancelled();
      throw StateError('Unreadable progress');
    }
    final progress = (read as Success<ReadingProgress?>).value;
    final migrationWatch = _autoWorkClock = Stopwatch()..start();
    late final ReparsedPosition migration;
    try {
      migration = await _migrate(
        candidate.old.content,
        candidate.prepared.content,
        progress,
        token,
      );
    } finally {
      migrationWatch.stop();
      _autoPrepareTime += migrationWatch.elapsed;
      _autoWorkClock = null;
      _autoMeasure?.call('migration', migrationWatch.elapsed);
    }
    await _autoCheckpoint?.call('migration');
    if (!_exactAutomaticPosition(
      candidate.old.content,
      candidate.prepared.content,
      progress,
      migration,
    )) {
      await _writeAutomaticAttempt(
        key,
        LocalAutoReparseIssue.approximatePosition.name,
      );
      await _finishAutoCandidate(candidate);
      return true;
    }
    if (!_mayStartAutomatic ||
        _bookUses[key]?.isNotEmpty == true ||
        _unsafeProgress.containsKey(key)) {
      return false;
    }
    final result = await _run(Operation.libraryWrite, () async {
      if (!_mayStartAutomatic ||
          _bookUses[key]?.isNotEmpty == true ||
          _unsafeProgress.containsKey(key)) {
        return false;
      }
      final gate = Completer<void>();
      _publishing[key] = gate;
      final lockWatch = Stopwatch()..start();
      var committed = false;
      try {
        // No large file read, migration, cleanup or Worker under this permit.
        final row = await _bookRow(this, key);
        if (!_sameBaseline(row, candidate.baseline) ||
            await _progressStamp(this, key) != stamp) {
          return false;
        }
        await _autoCheckpoint?.call('beforeRename');
        await db.customStatement(
          'UPDATE local_books SET maintenance=1 WHERE digest=?',
          [key.novelId],
        );
        await _renameReparse(this, key, candidate.prepared);
        await _autoCheckpoint?.call('afterRename');
        final sqlWatch = Stopwatch()..start();
        await db.transaction(() async {
          final latest = await _bookRow(this, key);
          if (!_sameBaseline(latest, candidate.baseline) ||
              await _progressStamp(this, key) != stamp) {
            throw const _AutoStateChanged();
          }
          final persisted = await LocalLibraryRepository(
            db,
          ).getProgress(key, cancellation: CancellationSource().token);
          if (persisted is! Success<ReadingProgress?> ||
              persisted.value != progress) {
            throw const _AutoStateChanged();
          }
          await _autoCheckpoint?.call('transaction');
          await _publishReparse(this, key, candidate.prepared, migration);
        });
        _autoMeasure?.call('transaction', sqlWatch.elapsed);
        await _autoCheckpoint?.call('afterCommit');
        committed = true;
        _reparseChanged(key);
        return true;
      } on _AutoStateChanged {
        return false;
      } finally {
        // Once publishing begins, lifecycle/budget cancellation never aborts SQL.
        try {
          if (!committed) {
            await db.customStatement(
              'UPDATE local_books SET maintenance=0 WHERE digest=?',
              [key.novelId],
            );
          }
        } finally {
          try {
            if (!committed) {
              await _refreshUncertainPublication(this, key, candidate.prepared);
            }
          } finally {
            _publishing.remove(key);
            gate.complete();
            _autoMeasure?.call('publication', lockWatch.elapsed);
          }
        }
      }
    });
    if (result case Failure(:final failure)) {
      throw StateError('Automatic publication failed: ${failure.kind.name}');
    }
    final committed = (result as Success<bool>).value;
    if (committed) {
      final cleanupWatch = Stopwatch()..start();
      await _autoCheckpoint?.call('cleanup');
      await _cleanRevisions(key.novelId, candidate.prepared.bundle);
      _autoMeasure?.call('cleanup', cleanupWatch.elapsed);
      await _finishAutoCandidate(candidate);
    } else if (candidate.prepared.published) {
      // A failed CAS after rename retires this immutable candidate. Re-prepare
      // next launch; never rename an already published revision a second time.
      await _clearRunningAttempt(key);
      await _finishAutoCandidate(candidate);
      return true;
    }
    return committed;
  }

  Future<void> _finishAutoCandidate(_AutoPrepared candidate) async {
    if (identical(_autoPending, candidate)) _autoPending = null;
    await _discardReparse(this, candidate.key, candidate.prepared);
  }

  Future<void> _writeAutomaticAttempt(
    NovelKey key,
    String outcome, {
    bool failure = false,
    Duration? retry,
  }) async {
    await db.customUpdate(
      '''
INSERT INTO local_reparse_attempts(digest,target_parser_version,outcome,failure_count,next_retry_at,attempted_at)
SELECT digest,?,?,?, ?,? FROM local_books WHERE digest=? AND parser_version < ?
ON CONFLICT(digest) DO UPDATE SET target_parser_version=excluded.target_parser_version,
outcome=excluded.outcome, failure_count=CASE WHEN local_reparse_attempts.target_parser_version=excluded.target_parser_version THEN local_reparse_attempts.failure_count+? ELSE excluded.failure_count END,
next_retry_at=excluded.next_retry_at, attempted_at=excluded.attempted_at
''',
      variables: [
        Variable(BookDecoder.parserVersion),
        Variable(outcome),
        Variable(failure ? 1 : 0),
        Variable(
          retry == null ? null : _autoNow().add(retry).millisecondsSinceEpoch,
        ),
        Variable(_autoNow().millisecondsSinceEpoch),
        Variable(key.novelId),
        Variable(BookDecoder.parserVersion),
        Variable(failure ? 1 : 0),
      ],
      updates: {db.localReparseAttempts},
    );
  }

  Future<void> _clearRunningAttempt(NovelKey key) async {
    // Restore eligibility without erasing earlier failure counts on cancellation.
    await db.customUpdate(
      "UPDATE local_reparse_attempts SET outcome='cancelled',next_retry_at=? WHERE digest=? AND outcome IN ('running','preparedWaiting')",
      variables: [
        Variable(_autoNow().millisecondsSinceEpoch),
        Variable(key.novelId),
      ],
      updates: {db.localReparseAttempts},
    );
  }

  Future<void> _cancelAutomaticAttempt(NovelKey key) async {
    await _clearRunningAttempt(key);
    _autoAttempted.remove(key);
  }

  Future<void> _automaticFailure(NovelKey key, Object error) async {
    final issue = switch (error) {
      _AmbiguousEncoding() => LocalAutoReparseIssue.ambiguousEncoding,
      _OriginalCorrupt() => LocalAutoReparseIssue.originalCorrupt,
      _LowStorage() => LocalAutoReparseIssue.lowStorage,
      LocalParseException(problem: LocalParseProblem.timeout) =>
        LocalAutoReparseIssue.timeout,
      FileSystemException(osError: OSError(errorCode: 28 || 112)) =>
        LocalAutoReparseIssue.lowStorage,
      FileSystemException() => LocalAutoReparseIssue.storageWrite,
      _ => LocalAutoReparseIssue.other,
    };
    final terminal =
        issue == LocalAutoReparseIssue.ambiguousEncoding ||
        issue == LocalAutoReparseIssue.originalCorrupt;
    final count = await db
        .customSelect(
          'SELECT failure_count FROM local_reparse_attempts WHERE digest=? AND target_parser_version=?',
          variables: [
            Variable(key.novelId),
            Variable(BookDecoder.parserVersion),
          ],
        )
        .getSingleOrNull();
    final failures = count?.read<int>('failure_count') ?? 0;
    final retry = terminal ? null : Duration(hours: 1 << failures.clamp(0, 4));
    if (issue == LocalAutoReparseIssue.lowStorage) {
      _autoStorageRetryAt = _autoNow().add(retry!);
      _autoAttempted.remove(key);
    }
    await _writeAutomaticAttempt(
      key,
      issue.name,
      failure: !terminal && issue != LocalAutoReparseIssue.lowStorage,
      retry: retry,
    );
  }

  Future<Result<T>> _foregroundOperation<T>(
    NovelKey? key,
    Future<Result<T>> Function() action,
  ) async {
    if (_closing != null || _closed) {
      throw StateError('Local book store is closed');
    }
    if (_manualOperations++ == 0) _manualIdle = Completer<void>();
    _autoWorkClock?.stop();
    _autoCancellation?.cancel();
    try {
      // Includes Worker exit, pending writes, rollback and an entered Commit.
      await _autoRun;
      if (_autoPending case final pending?
          when key == null || pending.key == key) {
        // Claim before awaiting so shutdown cannot clean the same candidate.
        _autoPending = null;
        await _cancelAutomaticAttempt(pending.key);
        await _finishAutoCandidate(pending);
      }
      return await action();
    } finally {
      if (--_manualOperations == 0) _manualIdle?.complete();
      _wakeAutomatic();
    }
  }

  void _reparseChanged(NovelKey key) {
    _readCache = null;
    _presentations.remove(key);
    _svgLinksScanned.remove(key);
    _changes.add(key);
  }
}

bool _sameBaseline(QueryRow? row, Map<String, Object?> baseline) =>
    row != null &&
    [
      'active_bundle',
      'manifest_hash',
      'parser_version',
      'format',
      'imported_at',
    ].every((field) => row.data[field] == baseline[field]);

bool _exactAutomaticPosition(
  LocalBookContent old,
  LocalBookContent next,
  ReadingProgress? saved,
  ReparsedPosition migrated,
) {
  if (saved == null) return migrated.progress == null && !migrated.approximate;
  final before = old.chapters
      .where((c) => c.key == saved.chapterKey)
      .firstOrNull;
  final result = migrated.progress;
  if (before == null ||
      before.contentRevision != saved.position.contentRevision ||
      saved.position.blockIndex >= before.blocks.length ||
      before.blocks[saved.position.blockIndex].blockKey !=
          saved.position.blockKey ||
      saved.catalogRevision != old.catalog.revision ||
      migrated.approximate ||
      result == null ||
      result.completed != saved.completed ||
      result.bookProgress?.terminal !=
          (saved.bookProgress?.terminal ?? BookTerminalState.reading) ||
      result.lastReadAt != saved.lastReadAt ||
      result.catalogRevision != next.catalog.revision) {
    return false;
  }
  final target = next.chapters
      .where((c) => c.key == result.chapterKey)
      .firstOrNull;
  return target != null &&
      target.contentRevision == result.position.contentRevision &&
      result.position.blockIndex < target.blocks.length &&
      target.blocks[result.position.blockIndex].blockKey ==
          result.position.blockKey &&
      next.catalog.flatChapters.any(
        (c) =>
            c.key == result.chapterKey &&
            c.ordinal == result.chapterOrdinalSnapshot,
      );
}

class _LowStorage implements Exception {
  const _LowStorage();
}

class _AutoStateChanged implements Exception {
  const _AutoStateChanged();
}
