import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../../../domain/content_identity.dart';
import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import 'lightnovel_api.dart';
import 'lightnovel_identity.dart';
import 'lightnovel_detail.dart';

final class LightNovelChapter {
  LightNovelChapter(this.api);
  final LightNovelApi api;
  Future<Result<ChapterContent>> load(
    ChapterKey key,
    CancellationToken token,
  ) async {
    if (token.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.chapter));
    }
    try {
      if (key.novelKey.sourceId != lightNovelSourceId) return _invalid();
      lightNovelRemoteId(key.novelKey.novelId);
      lightNovelRemoteId(key.chapterId);
      final result = await api.request(LightNovelEndpoint.chapter, {
        'book_id': key.novelKey.novelId,
        'chapter_id': key.chapterId,
      }, cancellation: token);
      if (result case Failure(:final failure)) return Failure(failure);
      if (token.isCancelled) {
        return Failure(AppFailure.cancelled(Operation.chapter));
      }
      final data = (result as Success<Map<String, dynamic>>).value;
      if (lightNovelKey(data['book_id']) != key.novelKey ||
          lightNovelRemoteId(data['chapter_id']) != key.chapterId) {
        return _invalid();
      }
      if (data['locked'] == 1) {
        return Failure(
          AppFailure(
            kind: FailureKind.accessRestricted,
            operation: Operation.chapter,
          ),
        );
      }
      if (data['locked'] is! int || data['locked'] != 0) return _invalid();
      final title = data['title'], snapshot = data['body_snapshot'];
      if (title is! String || title.trim().isEmpty || snapshot is! Map) {
        return _invalid();
      }
      final body = snapshot['body_html'], text = snapshot['body_text'];
      if ((body != null && body is! String) ||
          (text != null && text is! String)) {
        return _invalid();
      }
      final blocks = <ContentBlock>[];
      if (body is String && body.trim().isNotEmpty) {
        final fragment = html.parseFragment(body);
        if (fragment.querySelector('form,input[type=password]') != null) {
          return Failure(
            AppFailure(
              kind: FailureKind.accessRestricted,
              operation: Operation.chapter,
            ),
          );
        }
        blocks.addAll(_Body(key).parse(fragment));
      } else if (text is String && text.trim().isNotEmpty) {
        // Snapshot plain text is still full-snapshot content, never preview.
        for (final line in ContentIdentity.normalizeText(text).split('\n')) {
          blocks.add(ParagraphBlock(text: line));
        }
      } else {
        return _invalid();
      }
      return Success(ChapterContent(key: key, title: title, blocks: blocks));
    } on FormatException {
      return _invalid();
    } on ArgumentError {
      return _invalid();
    }
  }

  Failure<ChapterContent> _invalid() => Failure(
    AppFailure(
      kind: FailureKind.parse,
      operation: Operation.chapter,
      context: FailureContext.invalidContent,
    ),
  );
}

final class _Body {
  _Body(this.key);
  final ChapterKey key;
  final blocks = <ContentBlock>[];
  var text = StringBuffer();
  void flush({bool empty = false}) {
    var value = text.toString().replaceAll(RegExp(r'^[ \t\n]+|[ \t\n]+$'), '');
    text = StringBuffer();
    if (value.isEmpty && !empty) return;
    var indent = 0;
    while (value.startsWith('　') && indent < 8) {
      indent++;
      value = value.substring(1);
    }
    blocks.add(ParagraphBlock(text: value, leadingIndent: indent));
  }

  List<ContentBlock> parse(DocumentFragment root) {
    visit(root, 0);
    flush();
    return blocks;
  }

  void visit(Node node, int depth) {
    if (depth > 128) throw const FormatException('Nesting limit');
    if (node is Text) {
      text.write(node.data.replaceAll(RegExp(r'[\t\r\n ]+'), ' '));
      return;
    }
    if (node is! Element) {
      for (final child in node.nodes) {
        visit(child, depth + 1);
      }
      return;
    }
    final tag = node.localName;
    if ({
      'script',
      'style',
      'iframe',
      'object',
      'template',
      'noscript',
      'button',
      'input',
      'rp',
    }.contains(tag)) {
      return;
    }
    if (tag == 'figcaption' &&
        node.parent?.localName == 'figure' &&
        node.parent?.querySelector('img') != null) {
      return;
    }
    if (tag == 'br') {
      text.write('\n');
      return;
    }
    if (tag == 'hr') {
      flush();
      blocks.add(DividerBlock());
      return;
    }
    if (tag == 'img') {
      flush();
      final src = node.attributes['data-src']?.trim().isNotEmpty == true
          ? node.attributes['data-src']
          : node.attributes['data-original']?.trim().isNotEmpty == true
          ? node.attributes['data-original']
          : node.attributes['src'];
      if (src == null || src.trim().isEmpty) {
        throw const FormatException('Missing image');
      }
      final uri = Uri.parse('https://www.lightnovel.fun/').resolve(src);
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          uri.hasFragment ||
          !{'www.lightnovel.fun', 'api.lightnovel.fun'}.contains(uri.host)) {
        throw const FormatException('Invalid image');
      }
      final locator = ContentIdentity.digest('lightnovel-image-locator', [
        uri.origin,
        uri.path,
      ]);
      final media = MediaRef(
        sourceId: lightNovelSourceId,
        mediaId: 'image:v1:${key.novelKey.novelId}:${key.chapterId}:$locator',
      );
      int? dimension(String name) {
        final n = int.tryParse(node.attributes[name] ?? '');
        return n != null && n > 0 ? n : null;
      }

      Element? figure = node.parent;
      while (figure != null && figure.localName != 'figure') {
        figure = figure.parent;
      }
      final caption = figure?.querySelector('figcaption');
      blocks.add(
        ImageBlock(
          media: media,
          width: dimension('width'),
          height: dimension('height'),
          alt: node.attributes['alt'],
          caption: caption == null ? null : plainDetailText(caption.innerHtml),
        ),
      );
      return;
    }
    if (tag == 'rt') {
      text.write('（');
      for (final child in node.nodes) {
        visit(child, depth + 1);
      }
      text.write('）');
      return;
    }
    if (RegExp(r'^h[1-6]$').hasMatch(tag ?? '') &&
        node.querySelector('img') == null) {
      flush();
      final value = plainDetailText(node.innerHtml);
      if (value.isNotEmpty) {
        blocks.add(
          HeadingBlock(text: value, level: int.parse(tag!.substring(1))),
        );
      }
      return;
    }
    final boundary = {
      'p',
      'div',
      'section',
      'article',
      'li',
      'blockquote',
      'figure',
      'pre',
    }.contains(tag);
    if (boundary) flush();
    final before = blocks.length;
    for (final child in node.nodes) {
      visit(child, depth + 1);
    }
    if (boundary) flush(empty: tag == 'p' && blocks.length == before);
    if (blocks.length > 20000) throw const FormatException('Block limit');
  }
}
