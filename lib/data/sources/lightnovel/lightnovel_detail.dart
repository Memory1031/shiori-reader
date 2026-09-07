import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import 'lightnovel_api.dart';
import 'lightnovel_identity.dart';

final class LightNovelDetail {
  LightNovelDetail(this.api);
  final LightNovelApi api;
  Future<Result<NovelDetail>> load(
    NovelKey key,
    CancellationToken token,
  ) async {
    if (token.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.novelDetail));
    }
    try {
      if (key.sourceId != lightNovelSourceId) return _invalid();
      lightNovelRemoteId(key.novelId);
      final response = await api.request(LightNovelEndpoint.detail, {
        'book_id': key.novelId,
        'with_volumes': 0,
      }, cancellation: token);
      if (response case Failure(:final failure)) return Failure(failure);
      if (token.isCancelled) {
        return Failure(AppFailure.cancelled(Operation.novelDetail));
      }
      final data = (response as Success<Map<String, dynamic>>).value;
      if (lightNovelKey(data['book_id']) != key) return _invalid();
      final title = data['title'], author = data['author_name'];
      if (title is! String ||
          title.trim().isEmpty ||
          RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>').hasMatch(title) ||
          (author != null && author is! String)) {
        return _invalid();
      }
      final synopsis = data['summary_short'], tags = data['tags'];
      final cover = data['cover_url'];
      if ((synopsis != null && synopsis is! String) ||
          (tags != null && (tags is! List || tags.any((t) => t is! String))) ||
          (cover != null && cover is! String)) {
        return _invalid();
      }
      MediaRef? coverRef;
      if (cover is String && cover.trim().isNotEmpty) {
        final uri = Uri.parse('https://www.lightnovel.fun/').resolve(cover);
        if (uri.scheme != 'https' ||
            uri.userInfo.isNotEmpty ||
            uri.port != 443 ||
            !{'www.lightnovel.fun', 'api.lightnovel.fun'}.contains(uri.host) ||
            uri.hasFragment) {
          return _invalid();
        }
        // SRC-010 resolves the book's cover role by rereading its detail.
        // No expiring URL or query parameter enters this durable identity.
        coverRef = MediaRef(
          sourceId: lightNovelSourceId,
          mediaId: 'cover:v1:${key.novelId}',
        );
      }
      return Success(
        NovelDetail(
          synopsis: synopsis is String ? plainDetailText(synopsis) : '',
          tags: tags is List
              ? tags
                    .cast<String>()
                    .map(plainDetailText)
                    .where((t) => t.isNotEmpty)
                    .toSet()
              : const [],
          summary: NovelSummary(
            key: key,
            cover: coverRef,
            title: title,
            authors: author is String && author.trim().isNotEmpty
                ? [author.trim()]
                : [],
          ),
        ),
      );
    } on FormatException {
      return _invalid();
    } on ArgumentError {
      return _invalid();
    }
  }

  Failure<NovelDetail> _invalid() => Failure(
    AppFailure(
      kind: FailureKind.parse,
      operation: Operation.novelDetail,
      context: FailureContext.invalidContent,
    ),
  );
}

/// Decode HTML once; resulting text is never interpreted as markup again.
String plainDetailText(String input) {
  final fragment = html.parseFragment(input);
  final buffer = StringBuffer();
  void visit(Node node) {
    if (node is Text) {
      buffer.write(node.data);
      return;
    }
    if (node is Element) {
      if ({
        'script',
        'style',
        'iframe',
        'object',
        'template',
        'form',
        'noscript',
      }.contains(node.localName)) {
        return;
      }
      if ({
        'p',
        'div',
        'br',
        'li',
        'section',
        'h1',
        'h2',
        'h3',
      }.contains(node.localName)) {
        buffer.write('\n');
      }
    }
    for (final child in node.nodes) {
      visit(child);
    }
    if (node is Element &&
        {'p', 'div', 'li', 'section'}.contains(node.localName)) {
      buffer.write('\n');
    }
  }

  visit(fragment);
  return buffer
      .toString()
      .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
