/// A host address, never an EPUB URL. HTTPS also reaches WebView2's
/// Fetch-based navigation delegate, which cancels it before network access.
const epubLinkPrefix = 'https://shiori.invalid/link/';

String epubLinkAddress(int id) => '$epubLinkPrefix$id';

int? epubLinkId(String? address) {
  final match = RegExp(
    r'^https://shiori\.invalid/link/(0|[1-9][0-9]{0,3})$',
  ).firstMatch(address ?? '');
  return match == null ? null : int.parse(match[1]!);
}
