import '../../shared/widgets/catalog_browsing.dart';

enum ReaderContentsKind { article, book }

/// Owned by one book reader, independent of chapter views and modal routes.
class ReaderContentsSession {
  ReaderContentsKind selected = ReaderContentsKind.article;
  CatalogBrowsingState article = CatalogBrowsingState();
  CatalogBrowsingState online = CatalogBrowsingState();
  CatalogBrowsingState local = CatalogBrowsingState();
  Object? _context;
  bool active = true;

  void readingContext(Object context) {
    if (!active || _context == context) return;
    _context = context;
    invalidateBrowsing();
  }

  void invalidateBrowsing() {
    if (!active) return;
    article.invalidate();
    online.invalidate();
    local.invalidate();
    article = CatalogBrowsingState();
    online = CatalogBrowsingState();
    local = CatalogBrowsingState();
  }

  void dispose() {
    active = false;
    article.invalidate();
    online.invalidate();
    local.invalidate();
  }
}
