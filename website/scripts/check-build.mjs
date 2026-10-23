import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { assets } from './assets.mjs';
const root = fileURLToPath(new URL('../dist/', import.meta.url));
const base = '/shiori-reader/';
assert.ok(Object.values(assets).filter(a => a.source.startsWith('assets/screenshots/'))
  .every(a => a.source.startsWith('assets/screenshots/current/')), 'Use the reviewed current screenshots');
async function files(directory) { return (await Promise.all((await readdir(directory, { withFileTypes: true })).map(e => e.isDirectory() ? files(path.join(directory, e.name)) : path.join(directory, e.name)))).flat(); }
const all = await files(root);
for (const file of all) {
  if (!file.endsWith('.html')) continue;
  const html = await readFile(file, 'utf8');
  assert.ok(!/[A-Z]:\\(?:Users|Code|Software)\\/.test(html), 'Machine path leaked');
  assert.ok(html.includes('hreflang="en"') && html.includes('hreflang="zh-CN"'));
  assert.ok(html.includes('rel="canonical"'));
  assert.ok(html.includes('https://github.com/Memory1031/shiori-reader/releases/latest'), 'Missing non-JS fallback');
  for (const match of html.matchAll(/(?:href|src)="([^"#]+)(?:#[^"]*)?"/g)) {
    const url = match[1];
    if (!url.startsWith('/')) continue;
    assert.ok(url.startsWith(base), `Incorrect base: ${url}`);
    let target = path.join(root, decodeURIComponent(url.slice(base.length).split('?')[0]));
    if (url.endsWith('/')) target = path.join(target, 'index.html');
    assert.ok((await stat(target)).isFile(), `Missing ${url}`);
  }
}
for (const locale of ['zh-cn', 'en']) for (const page of ['', 'download/']) {
  const html = await readFile(path.join(root, locale, page, 'index.html'), 'utf8');
  assert.match(html, new RegExp(`lang="${locale === 'en' ? 'en' : 'zh-CN'}"`));
  assert.equal((html.match(/<h1[ >]/g) ?? []).length, 1);
  if (!page) {
    assert.ok(html.includes('/bookmarks-zh-'), 'Both locales should show the shared bookmark screenshot');
    assert.ok(!/\/(?:reader|shelf)-en-/.test(html), 'Screenshots should share Chinese UI artwork');
  }
}
console.log('Static routes, language metadata, local resources, fallback links and artwork policy verified.');
