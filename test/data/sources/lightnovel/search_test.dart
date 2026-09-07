import 'dart:async';
import 'package:shiori/data/sources/lightnovel/lightnovel_api.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import '../../network/network_test_support.dart';
import 'package:shiori/shared/app_logger.dart';

Map<String, dynamic> data(
  int page,
  List<int> ids, {
  int count = 2,
  int total = 40,
}) => {
  'list': [
    for (final id in ids)
      {
        'book_id': id,
        'title': 'Synthetic $id',
        'author_name': 'Synthetic author',
      },
  ],
  'pagination': {
    'page': page,
    'page_size': 20,
    'page_count': count,
    'total': total,
  },
  'has_next': page < count ? 1 : 0,
  'total': total,
};
SearchPage value(Result<SearchPage> r) => (r as Success<SearchPage>).value;
void main() {
  late RequestScheduler scheduler;
  late LightNovelSource source;
  late TestAdapter adapter;
  late Map<String, dynamic> next;
  final token = CancellationSource().token;
  setUp(() {
    scheduler = RequestScheduler(startInterval: Duration.zero);
    next = data(1, [1, 2]);
    adapter = TestAdapter(
      (_) =>
          response(bytes: utf8.encode(jsonEncode({'code': 0, 'data': next}))),
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
  test(
    'first, next, last pages; query encoding and consumed cursor cannot repeat',
    () async {
      final first = value(
        await source.search('  中文 & +  ', cancellation: token),
      );
      expect(first.items.first.authors, ['Synthetic author']);
      expect(first.items.first.cover?.mediaId, 'cover:v1:1');
      expect(first.items.first.cover?.sourceId, lightNovelSourceId);
      expect(first.nextCursor!.opaqueValue, isNot(contains('中文')));
      final payload = jsonDecode(
        utf8.decode(adapter.requests.single.data as List<int>),
      );
      expect(payload['q'], '中文 & +');
      expect(payload['page'], 0);
      next = data(2, [3], total: 3);
      final last = value(
        await source.search(
          '中文 & +',
          cursor: first.nextCursor,
          cancellation: token,
        ),
      );
      expect(last.nextCursor, isNull);
      expect(
        jsonDecode(
          utf8.decode(adapter.requests.last.data as List<int>),
        )['page'],
        1,
      );
      expect(
        await source.search(
          '中文 & +',
          cursor: first.nextCursor,
          cancellation: token,
        ),
        isA<Failure>(),
      );
      expect(adapter.requests.length, 2);
    },
  );
  test('captured empty page_count=1 and whitespace query terminate', () async {
    final fixture = jsonDecode(
      File(
        'test/fixtures/lightnovel/captured/search-empty.json',
      ).readAsStringSync(),
    );
    next = Map<String, dynamic>.from(fixture['response']['data']);
    expect(
      value(await source.search('none', cancellation: token)).items,
      isEmpty,
    );
    expect(
      value(await source.search('  ', cancellation: token)).nextCursor,
      isNull,
    );
    expect(adapter.requests.length, 1);
  });
  test(
    'captured ID/page projections with explicitly synthetic titles preserve three-page order',
    () async {
      SearchCursor? cursor;
      for (var page = 0; page < 3; page++) {
        final fixture = jsonDecode(
          File(
            'test/fixtures/lightnovel/captured/search-page-$page.json',
          ).readAsStringSync(),
        );
        next = Map<String, dynamic>.from(fixture['response']['data']);
        final ids = [for (final row in next['list']) row['book_id'].toString()];
        for (final row in next['list']) {
          row['title'] = 'Synthetic ${row['book_id']}';
        }
        final result = value(
          await source.search('恋爱', cursor: cursor, cancellation: token),
        );
        expect(result.items.map((item) => item.key.novelId), ids);
        cursor = result.nextCursor;
      }
    },
  );
  test(
    'query mismatch and pre-cancel do not dispatch or consume valid cursor',
    () async {
      final first = value(await source.search('a', cancellation: token));
      expect(
        await source.search('b', cursor: first.nextCursor, cancellation: token),
        isA<Failure>(),
      );
      final stopped = CancellationSource()..cancel();
      expect(
        (await source.search(
                  'a',
                  cursor: first.nextCursor,
                  cancellation: stopped.token,
                )
                as Failure)
            .failure
            .isCancellation,
        true,
      );
      expect(adapter.requests.length, 1);
      next = data(2, [3]);
      expect(
        await source.search('a', cursor: first.nextCursor, cancellation: token),
        isA<Success>(),
      );
    },
  );
  test(
    'repeated page and cross-page ID stop without losing retry cursor',
    () async {
      final first = value(await source.search('a', cancellation: token));
      expect(
        (await source.search('a', cursor: first.nextCursor, cancellation: token)
                as Failure)
            .failure
            .context,
        FailureContext.repeatedPage,
      );
      next = data(2, [1]);
      expect(
        (await source.search('a', cursor: first.nextCursor, cancellation: token)
                as Failure)
            .failure
            .context,
        FailureContext.repeatedPage,
      );
      next = data(2, [3]);
      expect(
        await source.search('a', cursor: first.nextCursor, cancellation: token),
        isA<Success>(),
      );
    },
  );
  test(
    'broken fields, duplicate IDs and inconsistent next flag are parse failures',
    () async {
      for (final malformed in [
        <String, dynamic>{},
        data(1, [1, 1]),
        data(1, [0]),
        data(1, [1])..['has_next'] = 0,
        data(1, []),
      ]) {
        next = malformed;
        expect(
          (await source.search('a', cancellation: token) as Failure)
              .failure
              .kind,
          FailureKind.parse,
        );
      }
      next = data(1, [1]);
      next['list'][0].remove('title');
      expect(await source.search('a', cancellation: token), isA<Failure>());
      next = data(1, [1]);
      next['list'][0]['author_name'] = [];
      expect(await source.search('a', cancellation: token), isA<Failure>());
    },
  );
  test(
    'cancelled in-flight search returns cancellation; discover remains unsupported without request',
    () async {
      source.close();
      final started = Completer<void>(), release = Completer<void>();
      adapter = TestAdapter((_) async {
        started.complete();
        await release.future;
        return response(
          bytes: utf8.encode(jsonEncode({'code': 0, 'data': next})),
        );
      });
      source = LightNovelSource(
        scheduler: scheduler,
        logger: AppLogger(),
        adapter: adapter,
      );
      final caller = CancellationSource();
      final work = source.search('a', cancellation: caller.token);
      await started.future;
      caller.cancel();
      release.complete();
      expect((await work as Failure).failure.isCancellation, true);
      expect(
        (await source.discover(cancellation: token) as Failure).failure.kind,
        FailureKind.unsupported,
      );
      expect(adapter.requests.length, 1);
    },
  );
  test(
    'observed target title and author map without inventing missing fields',
    () async {
      next = {
        'list': [
          {
            'book_id': 31607,
            'title': '桌游咖（玩乐关系/玩玩的戀愛關係）',
            'author_name': '葵关南',
          },
        ],
        'pagination': {'page': 1, 'page_size': 20, 'total': 1, 'page_count': 1},
      };
      final result = value(await source.search('玩乐关系', cancellation: token));
      expect(result.items.single.title, '桌游咖（玩乐关系/玩玩的戀愛關係）');
      expect(result.items.single.authors, ['葵关南']);
      expect(result.nextCursor, isNull);
    },
  );
  test(
    'cursor retention is bounded and evicted cursor cannot send a request',
    () async {
      final first = value(await source.search('first', cancellation: token));
      for (var i = 0; i < 32; i++) {
        await source.search('q$i', cancellation: token);
      }
      final count = adapter.requests.length;
      expect(
        (await source.search(
                  'first',
                  cursor: first.nextCursor,
                  cancellation: token,
                )
                as Failure)
            .failure
            .context,
        FailureContext.invalidCursor,
      );
      expect(adapter.requests.length, count);
    },
  );
}
