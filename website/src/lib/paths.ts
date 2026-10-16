export const base = '/shiori-reader';
export const repository = 'https://github.com/Memory1031/shiori-reader';
export const latestRelease = `${repository}/releases/latest`;
export type Locale = 'zh-cn' | 'en';
export const locales: Locale[] = ['zh-cn', 'en'];
export const route = (locale: Locale, page = '') => `${base}/${locale}/${page ? `${page}/` : ''}`;
export const media = (name: string) => `${base}/media/${name}`;
