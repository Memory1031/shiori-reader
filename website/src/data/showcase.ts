import type { Locale } from '../lib/paths';

// Replace a locale's bookmark image here when a reviewed release screenshot exists.
// English intentionally uses prose until appropriate English artwork is available.
export const bookmarkArtwork = {
  'zh-cn': 'bookmarks-zh',
  en: null,
} as const satisfies Record<Locale, 'bookmarks-zh' | null>;
