import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { releaseFixture } from '../tests/fixtures.ts';

const base = process.env.WEBSITE_URL ?? 'http://127.0.0.1:4321/shiori-reader/';
const output = fileURLToPath(new URL('../../.tooling/evidence/website/', import.meta.url));
await mkdir(output, { recursive: true });
const channel = process.env.WEBSITE_BROWSER ?? (process.platform === 'win32' ? 'chrome' : undefined);
const browser = await chromium.launch({ channel, headless: true });
const api = 'https://api.github.com/repos/Memory1031/shiori-reader/releases/latest';
const release = releaseFixture();
const results = [];
const problems = [];
try {
  const context = await browser.newContext({ reducedMotion: 'reduce' });
  await context.route(api, route => route.fulfill({ json: release }));
  const page = await context.newPage();
  page.on('pageerror', error => problems.push(error.message));
  page.on('response', response => { if (response.url().startsWith(base) && response.status() >= 400) problems.push(`${response.status()}: ${response.url()}`); });
  for (const locale of ['zh-cn', 'en']) for (const type of ['', 'download/']) for (const width of [360, 390, 430, 768, 1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: width < 768 ? 844 : 1000 });
    await page.goto(`${base}${locale}/${type}`);
    await page.locator('[data-version]').filter({ hasText: release.tag_name }).waitFor();
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all(Array.from(document.images).map(image => { image.loading = 'eager'; return image.decode(); }));
    });
    const metrics = await page.evaluate(() => ({ width: innerWidth, content: document.documentElement.scrollWidth, broken: Array.from(document.images).filter(i => !i.naturalWidth).length }));
    assert.ok(metrics.content <= width, `${locale}/${type} overflows at ${width}: ${metrics.content}`);
    assert.equal(metrics.broken, 0);
    assert.equal(await page.locator('h1').count(), 1);
    assert.equal(await page.locator('.install-grid article').count(), type ? 4 : 0);
    assert.equal(await page.locator('[data-install-note]').count(), type ? 0 : 1);
    assert.equal(await page.locator('a.icon-link').count(), 2);
    for (const icon of await page.locator('a.icon-link').all()) {
      assert.equal(await icon.getAttribute('aria-label'), locale === 'en' ? 'GitHub repository' : 'GitHub 仓库');
      assert.equal((await icon.innerText()).trim(), '');
      assert.equal(await icon.locator('svg').count(), 1);
    }
    if (!type && width === 390) assert.ok(await page.locator('.hero-phone').evaluate(node => node.getBoundingClientRect().width > 220), 'Mobile phone should be the primary visual');
    assert.equal(await page.locator('.language').getAttribute('href'), `/shiori-reader/${locale === 'en' ? 'zh-cn' : 'en'}/${type}`);
    const label = `${locale}-${type ? 'download' : 'home'}-${width}`;
    await page.screenshot({ path: `${output}/${label}.png`, fullPage: false });
    if (width === 390 || width === 1440) {
      const audit = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
      assert.deepEqual(audit.violations.map(v => ({ id: v.id, nodes: v.nodes.map(n => n.target) })), [], label);
      await page.screenshot({ path: `${output}/${label}-full.png`, fullPage: true });
      if (!type) {
        await page.locator('#search').screenshot({ path: `${output}/${label}-search.png` });
        await page.locator('#bookmarks').screenshot({ path: `${output}/${label}-bookmarks.png` });
      }
    }
    results.push({ locale, page: type || 'home', width, ...metrics });
  }
  for (const locale of ['zh-cn', 'en']) for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(base + locale + '/download/');
    await page.locator('[data-platform="windows"]').click();
    const primary = page.locator('[data-package]'), portable = page.locator('[data-portable]');
    await primary.waitFor({ state: 'visible' });
    assert.ok((await primary.getAttribute('href')).endsWith('-windows-x64-setup.exe'));
    assert.ok((await portable.getAttribute('href')).endsWith('-windows-x64.zip'));
    assert.equal(await portable.isVisible(), true);
    assert.ok((await primary.innerText()).includes(locale === 'en' ? 'recommended' : '推荐'));
    await page.locator('[data-download]').screenshot({ path: output + '/' + locale + '-windows-download-' + width + '.png' });
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${base}en/`);
  const menu = page.locator('[data-menu]');
  await menu.click();
  assert.equal(await menu.getAttribute('aria-expanded'), 'true');
  await page.keyboard.press('Tab');
  assert.ok(await page.locator('#site-nav a').first().evaluate(node => node === document.activeElement));
  await page.keyboard.press('Escape');
  assert.equal(await menu.getAttribute('aria-expanded'), 'false');
  assert.ok(await menu.evaluate(node => node === document.activeElement));
  await page.locator('#faq summary').first().focus();
  await page.keyboard.press('Enter');
  assert.equal(await page.locator('#faq details').first().getAttribute('open'), '');
  await page.locator('.reading-gallery > summary').click();
  await page.locator('[data-show="1"]').click();
  assert.equal(await page.locator('[data-slide="1"]').isVisible(), true);
  await page.screenshot({ path: `${output}/en-mobile-gallery.png`, fullPage: true });
  const panel = page.locator('[data-download]');
  await panel.locator('[data-platform="ios"]').click();
  assert.ok((await panel.locator('[data-install-note]').innerText()).includes('unsigned'));
  assert.ok((await panel.locator('[data-install-guide]').getAttribute('href')).endsWith('/en/download/#install-ios'));
  assert.ok((await panel.locator('[data-package]').getAttribute('href')).endsWith('-ios-arm64-unsigned.ipa'));
  await page.keyboard.press('Home');
  assert.equal(await panel.locator('[data-platform="android"]').getAttribute('aria-selected'), 'true');
  await page.keyboard.press('End');
  assert.equal(await panel.locator('[data-platform="ios"]').getAttribute('aria-selected'), 'true');
  await page.evaluate(() => document.documentElement.style.fontSize = '200%');
  await page.screenshot({ path: `${output}/en-mobile-large-text.png`, fullPage: true });
  // Critical navigation must work while the deferred bundle is still unavailable.
  const slow = await browser.newContext({ viewport: { width: 390, height: 844 }, reducedMotion: 'reduce' });
  await slow.route(api, route => route.fulfill({ json: releaseFixture() }));
  const firstPaint = await slow.newPage();
  const waitingScripts = [];
  await firstPaint.route('**/_astro/*.js', route => new Promise(resolve => {
    waitingScripts.push(async () => { await route.continue(); resolve(); });
  }));
  await firstPaint.goto(`${base}zh-cn/`, { waitUntil: 'commit' });
  await firstPaint.locator('[data-slide="1"]').waitFor({ state: 'attached' });
  await firstPaint.locator('link[rel="stylesheet"]').first().evaluate(link => link.sheet ? undefined : new Promise(resolve => link.addEventListener('load', resolve, { once: true })));
  assert.equal(await firstPaint.locator('#site-nav').isVisible(), false);
  assert.equal(await firstPaint.locator('[data-slide="1"]').isVisible(), false);
  const beforeGallery = await firstPaint.locator('[data-gallery]').boundingBox();
  await firstPaint.locator('[data-menu]').click();
  assert.equal(await firstPaint.locator('#site-nav').isVisible(), true);
  await firstPaint.keyboard.press('Escape');
  assert.equal(await firstPaint.locator('#site-nav').isVisible(), false);
  await firstPaint.screenshot({ path: `${output}/mobile-before-bundle.png` });
  await Promise.all(waitingScripts.map(resume => resume()));
  await firstPaint.locator('.gallery.interactive').waitFor();
  const afterGallery = await firstPaint.locator('[data-gallery]').boundingBox();
  assert.ok(Math.abs(beforeGallery.height - afterGallery.height) <= 1, 'Gallery jumps when the bundle initializes');
  await slow.close();
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), '200% text overflow');
  await page.screenshot({ path: `${output}/en-mobile-large-text.png`, fullPage: true });
  // Selecting a platform while a request is pending must use the latest selection.
  const delayed = await browser.newContext();
  const nextRelease = releaseFixture('v0.0.1');
  let respond;
  await delayed.route(api, route => new Promise(resolve => { respond = async () => { await route.fulfill({ json: nextRelease }); resolve(); }; }));
  const waiting = await delayed.newPage();
  await waiting.goto(`${base}en/download/`);
  await waiting.locator('[data-platform="ios"]').click();
  await respond();
  await waiting.locator('[data-version]').filter({ hasText: nextRelease.tag_name }).waitFor();
  assert.ok((await waiting.locator('[data-package]').getAttribute('href')).endsWith('-ios-arm64-unsigned.ipa'));
  await delayed.close();
  for (const kind of ['missing', 'rate', 'server', 'notfound', 'invalid', 'network', 'timeout']) {
    const ctx = await browser.newContext();
    await ctx.route(api, route => {
      if (kind === 'timeout') return new Promise(() => {});
      if (kind === 'network') return route.abort('failed');
      if (kind === 'missing') { const data = releaseFixture(); data.assets = []; return route.fulfill({ json: data }); }
      if (kind === 'invalid') return route.fulfill({ json: { unexpected: true } });
      return route.fulfill({ status: kind === 'rate' ? 403 : kind === 'server' ? 500 : 404, json: {} });
    });
    const p = await ctx.newPage();
    await p.goto(`${base}en/download/`);
    await p.locator('[data-download][aria-busy="false"]').waitFor();
    assert.equal(await p.locator('[data-package]').isVisible(), false);
    assert.equal(await p.getByRole('link', { name: 'Release downloads' }).isVisible(), true);
    if (kind !== 'missing') assert.equal(await p.locator('[data-retry]').isVisible(), true);
    if (kind === 'rate') {
      await p.screenshot({ path: `${output}/download-rate-limit.png`, fullPage: true });
      await ctx.unroute(api);
      await ctx.route(api, route => route.fulfill({ json: releaseFixture() }));
      await p.locator('[data-retry]').click();
      await p.locator('[data-version]').filter({ hasText: release.tag_name }).waitFor();
      assert.equal(await p.locator('[data-package]').isVisible(), true);
    }
    await ctx.close();
  }
  const nojs = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
  const plain = await nojs.newPage();
  for (const locale of ['zh-cn', 'en']) {
    await plain.goto(`${base}${locale}/download/`);
    assert.ok(await plain.locator('a[href$="/releases/latest"]').count() >= 1);
    assert.equal(await plain.locator('.language').isVisible(), true);
  }
  await plain.goto(`${base}zh-cn/`);
  assert.equal(await plain.locator('#site-nav').isVisible(), true);
  assert.equal(await plain.locator('[data-slide="1"]').isVisible(), true);
  await plain.goto(base);
  assert.equal(await plain.getByRole('link', { name: '进入中文官网' }).isVisible(), true);
  assert.equal(await plain.getByRole('link', { name: 'Continue in English' }).isVisible(), true);
  await nojs.close();
  if (process.env.WEBSITE_LIVE_RELEASE === '1') {
    const live = await browser.newContext();
    const p = await live.newPage();
    await p.goto(`${base}en/download/`);
    await p.locator('[data-download][aria-busy="false"]').waitFor();
    assert.match(await p.locator('[data-version]').innerText(), /^v\d+\.\d+\.\d+$/);
    for (const platform of ['android', 'windows', 'macos', 'ios']) {
      await p.locator(`[data-platform="${platform}"]`).click();
      assert.ok((await p.locator('[data-package]').getAttribute('href')).startsWith('https://github.com/Memory1031/shiori-reader/releases/download/'));
    }
    await p.screenshot({ path: `${output}/live-release.png`, fullPage: true });
    await live.close();
  }
  assert.deepEqual(problems, []);
  await writeFile(`${output}/results.json`, JSON.stringify({ results, problems, browser: browser.version() }, null, 2));
  console.log(`Verified ${results.length} page/viewport combinations, 8 axe audits, menu/keyboard/gallery, async switching, error/retry states, 200% text, no-JS fallbacks. Screenshots: ${output}`);
} finally { await browser.close(); }
