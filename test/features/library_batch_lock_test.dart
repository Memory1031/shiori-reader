import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/bookshelf/library_controller.dart';
import '../widgets/bookshelf_test.dart' show RemovalCache;
import '../widgets/local_books/harness.dart' show LocalStore;
import 'import/import_flow_test.dart' show MemorySource;
import 'package:shiori/features/import/import_controller.dart';

void main() {
  test(
    'batch lock defers OS import receipts and does not acknowledge or auto-import them',
    () async {
      final source = MemorySource(), store = LocalStore(count: 0);
      final importer = ImportController(source: source, store: store);
      await importer.start();
      final repository = FixtureLibraryRepository();
      final library = LibraryController(
        repository,
        canStartBatch: () => !importer.busy && !importer.interactionOpen,
        onBatchLockChanged: importer.setMaintenanceBlocked,
      )..onStart();
      final lease = library.acquireBatch(CancellationSource())!;
      expect(importer.maintenanceBlocked, isTrue);
      source.receive();
      await Future<void>.delayed(Duration.zero);
      importer.open();
      await importer.refresh();
      await importer.pick();
      await importer.submit();
      await importer.discard();
      expect(importer.panelOpen, isFalse);
      expect(importer.items, isEmpty);
      expect(source.acked, isEmpty);
      expect(source.pickCalls, 0);
      expect(source.inbox, hasLength(1));
      lease.release();
      await Future<void>.delayed(Duration.zero);
      expect(importer.maintenanceBlocked, isFalse);
      expect(importer.items, hasLength(1));
      expect(importer.busy, isFalse);
      expect(source.acked, isEmpty);
      expect(library.acquireBatch(CancellationSource()), isNull);
      importer.dismiss();
      final next = library.acquireBatch(CancellationSource());
      expect(next, isNotNull);
      next!.release();
      library.onDelete();
      await library.resourcesReleased;
      library.dispose();
      await importer.shutdown();
      importer.dispose();
      await store.close();
      await repository.close();
    },
  );
  test(
    'one batch lease blocks ordinary writes; online cache failure keeps key',
    () async {
      final repo = FixtureLibraryRepository();
      final cache = RemovalCache();
      final c = LibraryController(repo, cache: cache)..onStart();
      final book = const FixtureData().summary(FixtureScenario.shortChapter);
      await c.add(book);
      await Future<void>.delayed(Duration.zero);
      final request = CancellationSource();
      final lease = c.acquireBatch(request)!;
      expect(c.writing, isTrue);
      expect(c.acquireBatch(CancellationSource()), isNull);
      expect(await c.remove(book.key), isFalse);
      expect(await c.add(book), isFalse);
      cache.pending = Completer<Result<void>>();
      final removal = c.removeInBatch(
        book.key,
        lease,
        cancellation: request.token,
      );
      expect(cache.cleared, [book.key]);
      cache.pending!.complete(
        Failure(
          AppFailure(
            kind: FailureKind.cache,
            operation: Operation.libraryWrite,
          ),
        ),
      );
      expect(await removal, isA<Failure>());
      expect(c.contains(book.key), isTrue);
      expect(c.writing, isTrue);
      cache.pending = null;
      expect(
        await c.removeInBatch(book.key, lease, cancellation: request.token),
        isA<Success>(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.contains(book.key), isFalse);
      lease.release();
      lease.release();
      expect(c.writing, isFalse);
      c.onDelete();
      await c.resourcesReleased;
      c.dispose();
      await repo.close();
    },
  );
  test('cancel during cache cleanup cannot dispatch shelf mutation', () async {
    final repo = FixtureLibraryRepository();
    final cache = RemovalCache()..pending = Completer<Result<void>>();
    final c = LibraryController(repo, cache: cache)..onStart();
    final book = const FixtureData().summary(FixtureScenario.shortChapter);
    await c.add(book);
    await Future<void>.delayed(Duration.zero);
    final request = CancellationSource(),
        lease = c.acquireBatch(CancellationSource())!;
    final pending = c.removeInBatch(
      book.key,
      lease,
      cancellation: request.token,
    );
    request.cancel();
    cache.pending!.complete(const Success(null));
    expect(await pending, isA<Failure>());
    expect(c.contains(book.key), isTrue);
    lease.release();
    c.onDelete();
    await c.resourcesReleased;
    c.dispose();
    await repo.close();
  });
}
