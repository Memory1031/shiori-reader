import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'src/evidence.dart';
import 'src/transport.dart';

export 'src/evidence.dart';
export 'src/transport.dart';

typedef EvidenceStep = ({String name, Future<Json> Function() run});

class Probe {
  Probe({required this.fixtures, required this.transport});
  final Directory fixtures;
  final BudgetTransport transport;

  Json _read(String path) => object(
    jsonDecode(File.fromUri(fixtures.uri.resolve(path)).readAsStringSync()),
  );

  Future<Json> _post(String operation, Map<String, Object?> body) async {
    final response = await transport.request(
      'POST',
      Uri.parse('$site$apiPrefix$operation'),
      body: body,
    );
    require(response.mime == 'application/json', 'json_mime_rejected');
    return envelope(jsonDecode(utf8.decode(response.bytes)));
  }

  List<EvidenceStep> _offlineSteps() => [
    (
      name: 'fixture_integrity',
      run: () async {
        final manifest = _read('manifest.json');
        require(
          manifest['schemaVersion'] == 1 && manifest['task'] == 'SRC-002',
          'fixture_manifest_changed',
        );
        final entries = manifest['entries'] as List<dynamic>;
        require(entries.length == 15, 'fixture_count_changed');
        final paths = <String>{};
        for (final value in entries) {
          final entry = object(value);
          final path = entry['path'] as String;
          require(
            RegExp(
                  r'^[a-z0-9_-]+(?:/[a-z0-9_-]+)*(?:\.[a-z0-9_-]+)*\.(json|html|png)$',
                ).hasMatch(path) &&
                !path.startsWith('/') &&
                paths.add(path),
            'fixture_path_invalid',
          );
          final file = File.fromUri(fixtures.uri.resolve(path));
          require(
            sha256.convert(file.readAsBytesSync()).toString() ==
                entry['sha256'],
            'fixture_hash_mismatch',
          );
          if (path.endsWith('.json')) _read(path);
        }
        return {
          'verifiedManifestEntries': entries.length,
          'provenance':
              'SRC-002 projections/transcriptions/synthetic, not full responses',
        };
      },
    ),
    (
      name: 'fixture_identity',
      run: () async {
        final observations =
            _read('initial-http-observations.json')['observations']
                as List<dynamic>;
        final search = envelope(object(observations[1])['responseProjection']);
        assertBook(selectTarget(rows(search), 'book_id', bookId));
        final detail = envelope(object(observations[2])['responseProjection']);
        assertBook(detail);
        require(
          detail['default_volume_id'] == volumeId &&
              detail['default_chapter_id'] == chapterId,
          'default_identity_changed',
        );
        final summary = _read('captured/chapter-309555-summary.json');
        assertChapter(summary);
        final body = object(object(summary['bodySummaries'])['body_snapshot']);
        require(
          body['paragraphTagCount'] == 4084 && body['imageTagCount'] == 14,
          'body_observation_changed',
        );
        return {
          'bookId': bookId,
          'volumeId': volumeId,
          'chapterId': chapterId,
          'bodyEvidence':
              'structure statistics only; original body not retained',
        };
      },
    ),
    (
      name: 'fixture_pagination',
      run: () async {
        final seen = <int>{};
        for (var page = 0; page < 3; page++) {
          final fixture = _read('captured/search-page-$page.json');
          final data = envelope(fixture['response']);
          require(
            object(fixture['request'])['page'] == page &&
                object(data['pagination'])['page'] == page + 1,
            'pagination_mismatch',
          );
          for (final row in rows(data)) {
            require(
              row['book_id'] is int && seen.add(row['book_id'] as int),
              'search_identity_duplicated',
            );
          }
        }
        final empty = envelope(_read('captured/search-empty.json')['response']);
        require(
          rows(empty).isEmpty &&
              empty['has_next'] == 0 &&
              object(empty['pagination'])['page_count'] == 1,
          'empty_page_mismatch',
        );
        return {
          'requestPageBase': 0,
          'responsePageBase': 1,
          'checkedPages': 3,
          'emptyPageChecked': true,
        };
      },
    ),
    (
      name: 'fixture_catalog',
      run: () async {
        final expected = <int, List<int>>{
          44117: [309555, 309556],
          9918: [208472],
          9919: [208477],
          46122: [317939, 317940, 317941, 317959, 323103, 323197],
        };
        final seen = <int>{};
        for (final entry in expected.entries) {
          final data = envelope(
            _read('captured/catalog-${entry.key}.json')['response'],
          );
          assertSingleCatalogPage(data, 'chapter_id');
          final items = rows(data);
          require(
            jsonEncode(items.map((row) => row['chapter_id']).toList()) ==
                jsonEncode(entry.value),
            'catalog_order_changed',
          );
          for (final row in items) {
            require(
              row['book_id'] == bookId &&
                  row['volume_id'] == entry.key &&
                  row['locked'] == 0 &&
                  seen.add(row['chapter_id'] as int),
              'catalog_relation_mismatch',
            );
          }
        }
        return {
          'volumes': expected.length,
          'uniqueChapters': seen.length,
          'sourceOrderPreserved': true,
        };
      },
    ),
    (
      name: 'synthetic_body_image',
      run: () async {
        final html = File.fromUri(
          fixtures.uri.resolve('synthetic/chapter-shape.html'),
        ).readAsStringSync();
        final body = inspectBody(html, '自行编写的合成正文');
        require(
          body.statistics['nonemptyTextParagraphCount'] == 4 &&
              body.statistics['imageCount'] == 1 &&
              body.statistics['rubyCount'] == 1,
          'synthetic_structure_mismatch',
        );
        final decoded = decodeIllustration(
          File.fromUri(
            fixtures.uri.resolve('assets/synthetic-checker.png'),
          ).readAsBytesSync(),
          'image/png',
        );
        require(
          decoded['width'] == 2 && decoded['height'] == 2,
          'synthetic_image_mismatch',
        );
        return {
          'provenance': 'SYNTHETIC, not live evidence',
          'body': body.statistics,
          'image': decoded,
        };
      },
    ),
  ];

  List<EvidenceStep> _liveSteps() {
    BodyEvidence? body;
    return [
      (
        name: 'search',
        run: () async {
          final data = await _post('bff/apk-search-result-v1', {
            'q': '玩乐关系',
            'scope': '',
            'source': '',
            'primary_tag': '',
            'channel_code': '',
            'work_type': '',
            'source_type': '',
            'filters': {},
            'word_count_bucket': '',
            'status_bucket': '',
            'page': 0,
            'pageSize': 20,
            'sort': 'relevance',
            'preset': '',
          });
          assertBook(selectTarget(rows(data), 'book_id', bookId));
          require(
            object(data['pagination'])['page'] == 1,
            'pagination_mismatch',
          );
          return {
            'query': '玩乐关系',
            'bookId': bookId,
            'title': bookTitle,
            'author': author,
          };
        },
      ),
      (
        name: 'detail',
        run: () async {
          final data = await _post('new-content-read/get-book-detail', {
            'book_id': '$bookId',
            'with_volumes': 0,
          });
          assertBook(data);
          require(
            data['default_volume_id'] == volumeId &&
                data['default_chapter_id'] == chapterId,
            'default_identity_changed',
          );
          return {
            'bookId': bookId,
            'defaultVolumeId': volumeId,
            'defaultChapterId': chapterId,
          };
        },
      ),
      (
        name: 'volumes',
        run: () async {
          final data = await _post('new-content-read/get-book-volumes', {
            'book_id': '$bookId',
            'page': 1,
            'pageSize': 50,
          });
          assertSingleCatalogPage(data, 'volume_id');
          selectTarget(rows(data), 'volume_id', volumeId);
          return {
            'volumeCount': rows(data).length,
            'selectedVolumeId': volumeId,
            'page': 1,
            'pageCount': 1,
          };
        },
      ),
      (
        name: 'chapters',
        run: () async {
          final data = await _post('new-content-read/get-volume-chapters', {
            'book_id': '$bookId',
            'volume_id': '$volumeId',
            'page': 1,
            'pageSize': 50,
          });
          assertSingleCatalogPage(data, 'chapter_id');
          assertChapter(selectTarget(rows(data), 'chapter_id', chapterId));
          return {
            'selectedChapterId': chapterId,
            'selectedVolumeChapterCount': rows(data).length,
            'page': 1,
            'pageCount': 1,
          };
        },
      ),
      (
        name: 'chapter_text',
        run: () async {
          final data = await _post('new-content-read/get-chapter-detail', {
            'book_id': '$bookId',
            'chapter_id': '$chapterId',
          });
          body = chapterBody(data);
          return {
            'bookId': bookId,
            'volumeId': volumeId,
            'chapterId': chapterId,
            'bodyField': 'body_snapshot',
            ...body!.statistics,
          };
        },
      ),
      (
        name: 'illustration_decode',
        run: () async {
          // Current body URL, query intact; never persist or reconstruct signing.
          final uri = Uri.parse(
            '$site/reader/$bookId/$chapterId',
          ).resolve(body!.imageSources.first);
          validateTarget(uri, 'GET');
          final response = await transport.request('GET', uri);
          final decoded = decodeIllustration(response.bytes, response.mime);
          return {
            ...decoded,
            'bodyImageIndex': 0,
            'origin': 'https://api.lightnovel.fun',
            'queryPresent': uri.hasQuery,
            'observedKnownQueryKeys': [
              'm',
              't',
            ].where(uri.queryParameters.containsKey).toList(),
            'queryValuesRetained': false,
          };
        },
      ),
    ];
  }

  Future<Json> run() async {
    final report = <String, dynamic>{
      'schemaVersion': 1,
      'task': 'SRC-003',
      'mode': transport.live ? 'live' : 'offline',
      'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'dartVersion': Platform.version.split(' ').first,
      'platform': Platform.operatingSystem,
      'budget': transport.limit,
      'retryPolicy': 'none',
      'spacingMilliseconds': transport.spacing.inMilliseconds,
      'credentials': 'no Cookie/Authorization/session import',
      'productionSourceGate': 'NOT_EVALUATED_SRC004',
      'status': 'PASS',
    };
    final stages = <Json>[];
    var failed = false;
    for (final step in [
      ..._offlineSteps(),
      if (transport.live) ..._liveSteps(),
    ]) {
      if (failed) {
        stages.add({'stage': step.name, 'status': 'SKIPPED'});
        continue;
      }
      final start = transport.attempts.length;
      final watch = Stopwatch()..start();
      try {
        final evidence = await step.run();
        stages.add({
          'stage': step.name,
          'status': 'PASS',
          'httpAttempts': transport.attempts.length - start,
          'durationMilliseconds': watch.elapsedMilliseconds,
          'evidence': evidence,
        });
      } catch (error) {
        failed = true;
        report['status'] = 'FAIL';
        stages.add({
          'stage': step.name,
          'status': 'FAIL',
          'httpAttempts': transport.attempts.length - start,
          'durationMilliseconds': watch.elapsedMilliseconds,
          'failureCode': error is ProbeFailure
              ? error.code
              : 'invalid_evidence',
          'rawErrorRetained': false,
        });
      }
    }
    report['stages'] = stages;
    report['httpAttempts'] = transport.attempts.length;
    report['attempts'] = transport.attempts;
    report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    return report;
  }
}
