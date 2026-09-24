import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_cover_index.dart';

import '../../domain/reparse_position_test.dart' as f;

class _Store implements LocalBookStore, LocalBookInvalidation {
  final events = StreamController<NovelKey>.broadcast(sync: true);
  int reads = 0;
  Completer<void>? gate;
  MediaRef? cover = MediaRef(
    sourceId: LocalBookIdentity.sourceId,
    mediaId: '${f.key.novelId}/a',
  );

  @override
  Stream<NovelKey> get changes => events.stream;

  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    reads++;
    final answer = cover;
    await gate?.future;
    final book = f.book([
      [f.p('Page')],
    ]);
    return Success(
      LocalBookRecord(
        content: LocalBookContent(
          detail: NovelDetail(
            summary: NovelSummary(key: key, title: 'Book', cover: answer),
          ),
          catalog: book.catalog,
          chapters: book.chapters,
        ),
        format: LocalBookFormat.epub,
        importedAt: DateTime.utc(2025),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  test('resolves each cover once across callers and visits', () async {
    final store = _Store();
    final index = LocalCoverIndex(store);
    final results = await Future.wait([
      index.resolve(f.key),
      index.resolve(f.key),
    ]);
    expect(results.toSet(), {store.cover});
    expect(await index.resolve(f.key), store.cover);
    expect(index.contains(f.key), isTrue);
    expect(store.reads, 1);
    await index.close();
  });

  test('a reparse drops the entry and notifies rows', () async {
    final store = _Store();
    final index = LocalCoverIndex(store);
    await index.resolve(f.key);
    final notified = <NovelKey>[];
    index.invalidations.listen(notified.add);
    store.cover = null;
    store.events.add(f.key);
    await Future<void>.delayed(Duration.zero);
    expect(notified, [f.key]);
    expect(index.contains(f.key), isFalse);
    expect(await index.resolve(f.key), isNull);
    expect(store.reads, 2);
    await index.close();
  });

  test('a read overtaken by a reparse is not kept', () async {
    final store = _Store()..gate = Completer<void>();
    final index = LocalCoverIndex(store);
    final stale = index.resolve(f.key);
    store.events.add(f.key);
    store.gate!.complete();
    await stale;
    expect(index.contains(f.key), isFalse);
    await index.close();
  });
}
