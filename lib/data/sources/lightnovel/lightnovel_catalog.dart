import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import 'lightnovel_api.dart';
import 'lightnovel_identity.dart';

final class _CatalogFailure implements Exception {
  _CatalogFailure(this.failure);
  final AppFailure failure;
}

final class LightNovelCatalog {
  LightNovelCatalog(this.api);
  final LightNovelApi api;
  Future<Result<Catalog>> load(NovelKey key, CancellationToken token) async {
    var requests = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    Never fail(FailureContext context) => throw _CatalogFailure(
      AppFailure(
        kind: FailureKind.parse,
        operation: Operation.catalog,
        context: context,
      ),
    );
    void check() {
      if (token.isCancelled) {
        throw _CatalogFailure(AppFailure.cancelled(Operation.catalog));
      }
    }

    Future<List<Map<String, dynamic>>> pages(
      LightNovelEndpoint endpoint,
      Map<String, Object?> payload,
      String idField,
    ) async {
      final rows = <Map<String, dynamic>>[];
      final seen = <String>{};
      int? expectedTotal, expectedCount;
      for (var page = 1; ; page++) {
        check();
        if (++requests > 100) {
          throw _CatalogFailure(
            AppFailure(
              kind: FailureKind.tooLarge,
              operation: Operation.catalog,
            ),
          );
        }
        final response = await api.request(
          endpoint,
          {...payload, 'page': page, 'pageSize': 50},
          cancellation: token,
          deadline: deadline,
        );
        if (response case Failure(:final failure)) {
          throw _CatalogFailure(failure);
        }
        check();
        final data = (response as Success<Map<String, dynamic>>).value;
        final list = data['list'], pagination = data['pagination'];
        if (list is! List || list.length > 50 || pagination is! Map) {
          fail(FailureContext.invalidContent);
        }
        final count = pagination['page_count'], total = pagination['total'];
        if (count is! int ||
            total is! int ||
            count < 1 ||
            total < 0 ||
            pagination['page_size'] != 50) {
          fail(FailureContext.invalidContent);
        }
        if (pagination['page'] != page) fail(FailureContext.repeatedPage);
        if (page > count ||
            (expectedCount != null && expectedCount != count) ||
            (expectedTotal != null && expectedTotal != total)) {
          fail(FailureContext.invalidContent);
        }
        if (total > 5000 || count > 100) {
          throw _CatalogFailure(
            AppFailure(
              kind: FailureKind.tooLarge,
              operation: Operation.catalog,
            ),
          );
        }
        expectedCount = count;
        expectedTotal = total;
        if (list.isEmpty && (page < count || total != 0)) {
          fail(FailureContext.invalidContent);
        }
        for (final row in list) {
          if (row is! Map<String, dynamic>) fail(FailureContext.invalidContent);
          if (!seen.add(lightNovelRemoteId(row[idField]))) {
            fail(FailureContext.repeatedPage);
          }
          rows.add(row);
        }
        if (rows.length > total) fail(FailureContext.invalidContent);
        if (page == count) {
          if (rows.length != total) fail(FailureContext.invalidContent);
          return rows;
        }
      }
    }

    try {
      check();
      if (key.sourceId != lightNovelSourceId) {
        fail(FailureContext.invalidContent);
      }
      lightNovelRemoteId(key.novelId);
      final groups = await pages(LightNovelEndpoint.volumes, {
        'book_id': key.novelId,
      }, 'volume_id');
      final volumes = <Volume>[];
      final chapterIds = <String>{};
      var ordinal = 0;
      for (final group in groups) {
        check();
        final id = lightNovelRemoteId(group['volume_id']);
        final title = group['title'];
        if (title != null && title is! String) {
          fail(FailureContext.invalidContent);
        }
        if (group['book_id'] != null &&
            lightNovelRemoteId(group['book_id']) != key.novelId) {
          fail(FailureContext.invalidContent);
        }
        final rows = await pages(LightNovelEndpoint.chapters, {
          'book_id': key.novelId,
          'volume_id': id,
        }, 'chapter_id');
        final declaredChapters = group['chapter_count'];
        if (declaredChapters != null &&
            (declaredChapters is! int || declaredChapters != rows.length)) {
          fail(FailureContext.invalidContent);
        }
        final chapters = <Chapter>[];
        for (final row in rows) {
          if (lightNovelRemoteId(row['book_id']) != key.novelId ||
              lightNovelRemoteId(row['volume_id']) != id) {
            fail(FailureContext.invalidContent);
          }
          final chapterId = lightNovelRemoteId(row['chapter_id']);
          if (!chapterIds.add(chapterId)) fail(FailureContext.repeatedPage);
          final name = row['title'];
          if (name is! String || name.trim().isEmpty) {
            fail(FailureContext.invalidContent);
          }
          final locked = row['locked'];
          if (locked != null &&
              (locked is! int || (locked != 0 && locked != 1))) {
            fail(FailureContext.invalidContent);
          }
          // Retain restricted chapters. Reading permission is checked by SRC-009;
          // Chapter carries identity/order, not an assertion of accessibility.
          chapters.add(
            Chapter(
              key: ChapterKey(novelKey: key, chapterId: chapterId),
              title: name,
              ordinal: ordinal++,
              volumeGroupId: id,
            ),
          );
          if (ordinal > 5000) {
            throw _CatalogFailure(
              AppFailure(
                kind: FailureKind.tooLarge,
                operation: Operation.catalog,
              ),
            );
          }
        }
        volumes.add(
          Volume(groupId: id, title: title as String?, chapters: chapters),
        );
      }
      check();
      // No verified ungrouped-chapter endpoint exists. An empty volume response
      // represents an empty catalog, never a guessed volume_id=0 request.
      if (volumes.isEmpty) {
        volumes.add(
          Volume(groupId: 'ungrouped', isSynthetic: true, chapters: []),
        );
      }
      return Success(Catalog(novelKey: key, volumes: volumes));
    } on _CatalogFailure catch (error) {
      return Failure(error.failure);
    } on FormatException {
      return Failure(
        AppFailure(
          kind: FailureKind.parse,
          operation: Operation.catalog,
          context: FailureContext.invalidContent,
        ),
      );
    } on ArgumentError {
      return Failure(
        AppFailure(
          kind: FailureKind.parse,
          operation: Operation.catalog,
          context: FailureContext.invalidContent,
        ),
      );
    }
  }
}
