// Synthetic HTTP only. Never delegates to a socket adapter.
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/contracts/contracts.dart';

class MvpFixture implements HttpClientAdapter {
  Operation? broken;
  bool offline = false;
  int calls = 0;
  final stages = <String>[];
  final image = fixturePng(240, 320, 4);
  static const imageUrl = 'https://www.lightnovel.fun/mvp-synthetic.png';
  Map<String, Object?> page(List<Map<String, Object?>> rows, int size) => {
    'list': rows,
    'pagination': {
      'page': 1,
      'page_size': size,
      'page_count': 1,
      'total': rows.length,
    },
    'has_next': 0,
    'total': rows.length,
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls++;
    if (offline) throw StateError('MVP offline transport invoked');
    final path = request.uri.path;
    if (path.endsWith('mvp-synthetic.png')) {
      stages.add('media');
      return ResponseBody.fromBytes(
        image,
        200,
        headers: {
          'content-type': ['image/png'],
        },
      );
    }
    final body = jsonDecode(utf8.decode(request.data as List<int>)) as Map;
    late Operation stage;
    late Map<String, Object?> data;
    if (path.endsWith('apk-search-result-v1')) {
      stage = Operation.search;
      data = page([
        {
          'book_id': 1,
          'title': 'MVP Sample',
          'author_name': 'Synthetic author',
        },
      ], 20);
      if (broken == stage) (data['list'] as List).first.remove('title');
    } else if (path.endsWith('get-book-detail')) {
      stage = Operation.novelDetail;
      data = {
        'book_id': 1,
        'title': 'MVP Sample',
        'author_name': 'Synthetic author',
        'status': 1,
        'cover_url': imageUrl,
      };
      if (broken == stage) data.remove('title');
    } else if (path.endsWith('get-book-volumes')) {
      stage = Operation.catalog;
      data = page([
        {'volume_id': 1, 'title': 'MVP Volume'},
      ], 50);
      if (broken == stage) data['items'] = data.remove('list');
    } else if (path.endsWith('get-volume-chapters')) {
      stage = Operation.catalog;
      data = page([
        for (var i = 1; i <= 2; i++)
          {
            'chapter_id': i,
            'book_id': 1,
            'volume_id': 1,
            'title': 'MVP Chapter $i',
            'locked': 0,
          },
      ], 50);
    } else if (path.endsWith('get-chapter-detail')) {
      stage = Operation.chapter;
      data = {
        'book_id': 1,
        'chapter_id': int.parse(body['chapter_id'].toString()),
        'title': 'MVP Chapter ${body['chapter_id']}',
        'locked': 0,
        'body_snapshot': {
          'body_html':
              '<img src="$imageUrl" width="240" height="320" alt="MVP image">${List.generate(80, (i) => '<p>MVP paragraph $i. This is self-authored offline reading content for deterministic regression.</p>').join()}',
          'body_text': 'MVP',
        },
      };
      if (broken == stage) {
        data['renamed_snapshot'] = data.remove('body_snapshot');
      }
    } else {
      throw StateError('Unexpected fixture endpoint');
    }
    stages.add(stage.name);
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'code': 0, 'data': data})),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
