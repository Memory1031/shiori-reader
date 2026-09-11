/// Closed reasons only: never include a signed URL in errors or diagnostics.
enum LightNovelImageIssue {
  missing,
  malformed,
  scheme,
  credentials,
  port,
  fragment,
  host,
}

final class LightNovelImageException implements Exception {
  const LightNovelImageException(this.issue);
  final LightNovelImageIssue issue;
}

Uri lightNovelMediaUri(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    throw const LightNovelImageException(LightNovelImageIssue.missing);
  }
  try {
    final uri = Uri.parse('https://www.lightnovel.fun/').resolve(raw);
    final issue = uri.scheme != 'https'
        ? LightNovelImageIssue.scheme
        : uri.userInfo.isNotEmpty
        ? LightNovelImageIssue.credentials
        : uri.port != 443
        ? LightNovelImageIssue.port
        : uri.hasFragment
        ? LightNovelImageIssue.fragment
        : !(uri.host == 'lightnovel.fun' ||
              uri.host.endsWith('.lightnovel.fun'))
        ? LightNovelImageIssue.host
        : null;
    if (issue != null) throw LightNovelImageException(issue);
    return uri;
  } on FormatException {
    throw const LightNovelImageException(LightNovelImageIssue.malformed);
  }
}
