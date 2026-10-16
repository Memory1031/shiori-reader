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
const results = [];
const problems = [];
try {
  const context = await browser.newContext({ reducedMotion: 'reduce' });
  await context.route(api, route => route.fulfill({ json: releaseFixture() }));
  const page = await context.newPage();
  page.on('pageerror', error => problems.push(error.message));
  page.on('response', response => { if (response.url().startsWith(base) && response.status() >= 400) problems.push(`${response.status()}: ${response.url()}`); });
  for (const locale of ['zh-cn', 'en']) for (const type of ['', 'download/']) for (const width of [360, 390, 430, 768, 1280, 1440, 1920]) {
    await page.setViewportSize({ width, height: width < 768 ? 844 : 1000 });
    await page.goto(`${base}${locale}/${type}`);
    await page.locator('[data-version]').filter({ hasText: 'v1.4.0' }).waitFor();
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all(Array.from(document.images).map(image => { image.loading = 'eager'; return image.decode(); }));
    });
    const metrics = await page.evaluate(() => ({ width: innerWidth, content: document.documentElement.scrollWidth, broken: Array.from(document.images).filter(i => !i.naturalWidth).length }));
    assert.ok(metrics.content <= width, `${locale}/${type} overflows at ${width}: ${metrics.content}`);
    assert.equal(metrics.broken, 0);
    assert.equal(await page.locator('h1').count(), 1);
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
  await page.locator('summary').first().focus();
  await page.keyboard.press('Enter');
  assert.equal(await page.locator('details').first().getAttribute('open'), '');
  await page.locator('[data-show="1"]').click();
  assert.equal(await page.locator('[data-slide="1"]').isVisible(), true);
  await page.screenshot({ path: `${output}/en-mobile-gallery.png`, fullPage: true });
  const panel = page.locator('[data-download]');
  await panel.locator('[data-platform="ios"]').click();
  assert.ok((await panel.locator('[data-package]').getAttribute('href')).endsWith('-ios-arm64-unsigned.ipa'));
  await page.keyboard.press('Home');
  assert.equal(await panel.locator('[data-platform="android"]').getAttribute('aria-selected'), 'true');
  await page.keyboard.press('End');
  assert.equal(await panel.locator('[data-platform="ios"]').getAttribute('aria-selected'), 'true');
  await page.evaluate(() => document.documentElement.style.fontSize = '200%');
  await page.screenshot({ path: `${output}/en-mobile-large-text.png`, fullPage: true });
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), '200% text overflow');
  await page.screenshot({ path: `${output}/en-mobile-large-text.png`, fullPage: true });
  // Selecting a platform while a request is pending must use the latest selection.
  const delayed = await browser.newContext();
  let respond;
  await delayed.route(api, route => new Promise(resolve => { respond = async () => { await route.fulfill({ json: releaseFixture('v1.5.0') }); resolve(); }; }));
  const waiting = await delayed.newPage();
  await waiting.goto(`${base}en/download/`);
  await waiting.locator('[data-platform="ios"]').click();
  await respond();
  await waiting.locator('[data-version]').filter({ hasText: 'v1.5.0' }).waitFor();
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
    assert.equal(await p.getByRole('link', { name: 'Open GitHub Releases' }).isVisible(), true);
    if (kind !== 'missing') assert.equal(await p.locator('[data-retry]').isVisible(), true);
    if (kind === 'rate') {
      await p.screenshot({ path: `${output}/download-rate-limit.png`, fullPage: true });
      await ctx.unroute(api);
      await ctx.route(api, route => route.fulfill({ json: releaseFixture() }));
      await p.locator('[data-retry]').click();
      await p.locator('[data-version]').filter({ hasText: 'v1.4.0' }).waitFor();
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
