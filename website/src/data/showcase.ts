import type { Locale } from '../lib/paths';

// Both locales share reviewed Chinese UI screenshots with localized descriptions.
export const bookmarkArtwork = {
  'zh-cn': 'bookmarks-zh',
  en: 'bookmarks-zh',
} as const satisfies Record<Locale, 'bookmarks-zh' | null>;
