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

void main() {
  late RequestScheduler scheduler;
  late LightNovelSource source;
  late TestAdapter adapter;
  late Map<String, dynamic> data;
  final token = CancellationSource().token;
  final key = lightNovelKey(31607);
  setUp(() {
    scheduler = RequestScheduler(startInterval: Duration.zero);
    data = {
      'book_id': 31607,
      'title': 'Synthetic title',
      'author_name': 'Synthetic author',
      'status': 1,
    };
    adapter = TestAdapter(
      (_) =>
          response(bytes: utf8.encode(jsonEncode({'code': 0, 'data': data}))),
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
    'observed detail projection preserves identity author and unknown status',
    () async {
      final fixture = jsonDecode(
        File(
          'test/fixtures/lightnovel/initial-http-observations.json',
        ).readAsStringSync(),
      );
      // Locate the already-recorded detail operation, not the search projection.
      final observations = (fixture as Map).values
          .whereType<List>()
          .expand((v) => v)
          .whereType<Map>();
      final observation = observations.firstWhere(
        (r) => r['url']?.toString().endsWith('get-book-detail') ?? false,
      );
      data = Map<String, dynamic>.from(
        observation['responseProjection']['data'],
      );
      final detail =
          (await source.getNovelDetail(key, cancellation: token)
                  as Success<NovelDetail>)
              .value;
      expect(detail.summary.key, key);
      expect(detail.summary.authors, ['葵关南']);
      expect(detail.status, NovelStatus.unknown);
      expect(
        jsonDecode(utf8.decode(adapter.requests.single.data as List<int>)),
        {'book_id': '31607', 'with_volumes': 0},
      );
    },
  );
  test(
    'missing optional fields succeeds, malformed required identity/title fails',
    () async {
      data = {'book_id': 31607, 'title': 'Title'};
      final result =
          (await source.getNovelDetail(key, cancellation: token)
                  as Success<NovelDetail>)
              .value;
      expect(result.summary.authors, isEmpty);
      expect(result.summary.cover, isNull);
      for (final bad in [
        <String, dynamic>{},
        {'book_id': 1, 'title': 'Other'},
        {'book_id': 31607, 'title': ''},
        {'book_id': 31607, 'title': '<form>Login</form>'},
        {'book_id': 31607, 'title': 'Title', 'author_name': []},
      ]) {
        data = bad;
        expect(
          await source.getNovelDetail(key, cancellation: token),
          isA<Failure>(),
        );
      }
    },
  );
  test('foreign keys and pre-cancel never dispatch', () async {
    expect(
      await source.getNovelDetail(
        NovelKey(sourceId: SourceId('other'), novelId: '31607'),
        cancellation: token,
      ),
      isA<Failure>(),
    );
    expect(
      (await source.getNovelDetail(
                key,
                cancellation: (CancellationSource()..cancel()).token,
              )
              as Failure)
          .failure
          .isCancellation,
      true,
    );
    expect(adapter.requests, isEmpty);
  });
  test('login HTML and invalid UTF8 never become details', () async {
    source.close();
    for (final bytes in [
      utf8.encode('<html><form>Login</form></html>'),
      [0xff, 0xfe],
    ]) {
      final broken = LightNovelSource(
        scheduler: scheduler,
        logger: AppLogger(),
        adapter: TestAdapter((_) => response(bytes: bytes)),
      );
      expect(
        await broken.getNovelDetail(key, cancellation: token),
        isA<Failure>(),
      );
      broken.close();
    }
  });
  test(
    'synthetic synopsis HTML removes active nodes, decodes entities and keeps paragraphs',
    () async {
      data['summary_short'] =
          '<p>One &amp; two<br>Line</p><script>secret()</script><style>.bad{}</style><p>End <a href="https://example.test">link</a></p>';
      data['tags'] = [' Tag ', '<b>Other</b>', 'Tag'];
      final result =
          (await source.getNovelDetail(key, cancellation: token)
                  as Success<NovelDetail>)
              .value;
      expect(result.synopsis, 'One & two\nLine\n\nEnd link');
      expect(result.tags, ['Tag', 'Other']);
      expect(result.status, NovelStatus.unknown);
      expect(result.sourceUpdatedAt, isNull);
    },
  );
  test(
    'absolute and synthetic relative covers yield secret-free book-role identity',
    () async {
      data['cover_url'] =
          'https://api.lightnovel.fun/upload-files/synthetic.jpg?m=secret&t=one';
      final a =
          (await source.getNovelDetail(key, cancellation: token)
                  as Success<NovelDetail>)
              .value
              .summary
              .cover;
      data['cover_url'] = '/upload-files/synthetic.jpg?m=other&t=two';
      final b =
          (await source.getNovelDetail(key, cancellation: token)
                  as Success<NovelDetail>)
              .value
              .summary
              .cover;
      expect(a, b);
      expect(a!.mediaId, 'cover:v1:31607');
      expect(a.toJson().toString(), isNot(contains('secret')));
      for (final url in [
        'javascript:alert(1)',
        'http://api.lightnovel.fun/x',
        'https://evil.test/x',
        'https://u:p@api.lightnovel.fun/x',
      ]) {
        data['cover_url'] = url;
        expect(
          await source.getNovelDetail(key, cancellation: token),
          isA<Failure>(),
        );
      }
    },
  );
  test(
    'optional field type changes are diagnosed rather than silently erased',
    () async {
      for (final field in ['summary_short', 'cover_url', 'tags']) {
        data[field] = 123;
        expect(
          await source.getNovelDetail(key, cancellation: token),
          isA<Failure>(),
        );
        data.remove(field);
      }
    },
  );
}
