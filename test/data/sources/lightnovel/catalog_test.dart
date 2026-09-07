import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_identity.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';
import '../../network/network_test_support.dart';

Map<String, dynamic> page(
  List<Map<String, dynamic>> rows, {
  int number = 1,
  int count = 1,
  int? total,
}) => {
  'list': rows,
  'pagination': {
    'page': number,
    'page_count': count,
    'page_size': 50,
    'total': total ?? rows.length,
  },
};
Map<String, dynamic> chapter(
  int id,
  int volume, {
  int book = 31607,
  int locked = 0,
}) => {
  'chapter_id': id,
  'book_id': book,
  'volume_id': volume,
  'title': 'Synthetic $id',
  'locked': locked,
};
Catalog value(Result<Catalog> r) => (r as Success<Catalog>).value;
void main() {
  late RequestScheduler scheduler;
  late LightNovelSource source;
  late TestAdapter adapter;
  late Map<String, dynamic> Function(String, Map<String, dynamic>) respond;
  final key = lightNovelKey(31607), token = CancellationSource().token;
  setUp(() {
    scheduler = RequestScheduler(startInterval: Duration.zero);
    respond = (path, body) => path.endsWith('get-book-volumes')
        ? page([
            {'volume_id': 9, 'title': 'Extra'},
            {'volume_id': 2},
          ])
        : page([
            chapter(
              int.parse(body['volume_id']) * 10,
              int.parse(body['volume_id']),
            ),
          ]);
    adapter = TestAdapter(
      (request) => response(
        bytes: utf8.encode(
          jsonEncode({
            'code': 0,
            'data': respond(
              request.path,
              jsonDecode(utf8.decode(request.data as List<int>)),
            ),
          }),
        ),
      ),
    );
    source = LightNovelSource(
      scheduler: scheduler,
      logger: AppLogger(),
      adapter: adapter,
    );
  });
  tearDown(() {
    source.close();
    scheduler.close();
  });
  test('captured four-volume ten-chapter order and stable revision', () async {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/lightnovel/initial-http-observations.json',
              ).readAsStringSync(),
            )
            as Map;
    final rows = fixture.values
        .whereType<List>()
        .expand((v) => v)
        .whereType<Map>();
    final volumes = rows.firstWhere(
      (r) => r['url']?.toString().endsWith('get-book-volumes') ?? false,
    )['responseProjection']['data'];
    respond = (path, body) => path.endsWith('get-book-volumes')
        ? Map<String, dynamic>.from(volumes)
        : Map<String, dynamic>.from(
            jsonDecode(
              File(
                'test/fixtures/lightnovel/captured/catalog-${body['volume_id']}.json',
              ).readAsStringSync(),
            )['response']['data'],
          );
    final a = value(await source.getCatalog(key, cancellation: token));
    final b = value(await source.getCatalog(key, cancellation: token));
    expect(a.volumes.map((v) => v.groupId), ['44117', '9918', '9919', '46122']);
    expect(a.flatChapters.length, 10);
    expect(a.flatChapters.map((c) => c.ordinal), List.generate(10, (i) => i));
    expect(a.revision, b.revision);
    expect(adapter.requests.length, 10);
  });
  test(
    'source order, missing names, locked rows and cross-book identity survive',
    () async {
      final a = value(await source.getCatalog(key, cancellation: token));
      expect(a.volumes.map((v) => v.groupId), ['9', '2']);
      expect(a.volumes.last.title, isNull);
      respond = (path, body) => path.endsWith('get-book-volumes')
          ? page([
              {'volume_id': 9},
            ])
          : page([chapter(90, 9, book: int.parse(body['book_id']), locked: 1)]);
      final other = value(
        await source.getCatalog(lightNovelKey(123), cancellation: token),
      );
      expect(
        other.flatChapters.single.key.chapterId,
        a.flatChapters.first.key.chapterId,
      );
      expect(other.flatChapters.single.key, isNot(a.flatChapters.first.key));
    },
  );
  test(
    'synthetic multi-page volumes and chapters aggregate without sorting',
    () async {
      respond = (path, body) {
        final n = body['page'] as int;
        if (path.endsWith('get-book-volumes')) {
          return page(
            [
              {'volume_id': n == 1 ? 9 : 2},
            ],
            number: n,
            count: 2,
            total: 2,
          );
        }
        final v = int.parse(body['volume_id']);
        return page([chapter(v * 10 + n, v)], number: n, count: 2, total: 2);
      };
      final result = value(await source.getCatalog(key, cancellation: token));
      expect(result.flatChapters.map((c) => c.key.chapterId), [
        '91',
        '92',
        '21',
        '22',
      ]);
      expect(adapter.requests.length, 6);
    },
  );
  test(
    'empty volume list creates empty synthetic group without guessed request',
    () async {
      respond = (_, _) => page([]);
      final result = value(await source.getCatalog(key, cancellation: token));
      expect(result.volumes.single.isSynthetic, true);
      expect(result.flatChapters, isEmpty);
      expect(adapter.requests.length, 1);
    },
  );
  test(
    'duplicate and conflicting chapter identities fail whole aggregate',
    () async {
      respond = (path, body) => path.endsWith('get-book-volumes')
          ? page([
              {'volume_id': 9},
              {'volume_id': 2},
            ])
          : page([chapter(1, int.parse(body['volume_id']))]);
      expect(
        (await source.getCatalog(key, cancellation: token) as Failure)
            .failure
            .context,
        FailureContext.repeatedPage,
      );
      respond = (path, body) => path.endsWith('get-book-volumes')
          ? page([
              {'volume_id': 9},
            ])
          : page([chapter(1, 2)]);
      expect(await source.getCatalog(key, cancellation: token), isA<Failure>());
    },
  );
  test(
    'repeated page, duplicate volumes, changing totals and excessive pages stop',
    () async {
      for (final mode in ['repeat', 'duplicate', 'total', 'limit']) {
        respond = (path, body) {
          final n = body['page'] as int;
          if (mode == 'duplicate') {
            return page([
              {'volume_id': 9},
              {'volume_id': 9},
            ]);
          }
          if (mode == 'limit') return page([], count: 101, total: 5001);
          return page(
            [
              {'volume_id': n},
            ],
            number: mode == 'repeat' ? 1 : n,
            count: 2,
            total: mode == 'total' && n == 2 ? 3 : 2,
          );
        };
        expect(
          await source.getCatalog(key, cancellation: token),
          isA<Failure>(),
        );
      }
    },
  );
  test(
    'later volume HTTP failure returns failure, never partial catalog',
    () async {
      source.close();
      var attempts = 0;
      adapter = TestAdapter((request) {
        attempts++;
        if (attempts == 3) return response(status: 403);
        return response(
          bytes: utf8.encode(
            jsonEncode({
              'code': 0,
              'data': attempts == 1
                  ? page([
                      {'volume_id': 9},
                      {'volume_id': 2},
                    ])
                  : page([chapter(90, 9)]),
            }),
          ),
        );
      });
      source = LightNovelSource(
        scheduler: scheduler,
        logger: AppLogger(),
        adapter: adapter,
      );
      expect(
        (await source.getCatalog(key, cancellation: token) as Failure)
            .failure
            .kind,
        FailureKind.accessRestricted,
      );
      expect(attempts, 3);
    },
  );
  test(
    'cancellation between pages stops aggregate; title changes revision',
    () async {
      final first = value(await source.getCatalog(key, cancellation: token));
      final previous = respond;
      respond = (path, body) {
        final r = previous(path, body);
        if (path.endsWith('get-book-volumes')) {
          r['list'][0]['title'] = 'Changed';
        }
        return r;
      };
      expect(
        value(await source.getCatalog(key, cancellation: token)).revision,
        isNot(first.revision),
      );
      final cancelled = CancellationSource();
      respond = (path, body) {
        cancelled.cancel();
        return page([
          {'volume_id': 9},
        ]);
      };
      final before = adapter.requests.length;
      expect(
        (await source.getCatalog(key, cancellation: cancelled.token) as Failure)
            .failure
            .isCancellation,
        true,
      );
      expect(adapter.requests.length, before + 1);
    },
  );
}
