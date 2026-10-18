import assert from 'node:assert/strict';
import test from 'node:test';
import { fetchRelease, parseRelease, ReleaseError, type ErrorKind } from '../src/lib/releases.ts';
import { releaseFixture } from './fixtures.ts';

for (const tag of ['v0.0.1', 'v2.12.34', 'v10.20.30']) {
  test(`accepts five exact official packages for ${tag}`, () => {
    const result = parseRelease(releaseFixture(tag));
    assert.equal(result.tag, tag);
    assert.deepEqual(Object.keys(result.downloads), ['android', 'windows', 'windowsPortable', 'macos', 'ios']);
    assert.ok(result.downloads.ios?.url.endsWith('-ios-arm64-unsigned.ipa'));
  });
}
test('missing platform and unrelated checksum/update assets do not become downloads', () => {
  const input = releaseFixture();
  input.assets = input.assets.filter(a => !a.name.endsWith('android.apk'));
  for (const name of ['SHA256SUMS.txt', 'release-info.json', 'update-manifest.json', 'shiori-reader-v1.4.0-macos-universal.zip', 'shiori-reader-v1.3.9-android.apk']) {
    input.assets.push({ name, browser_download_url: `https://example.com/${name}`, size: 1024 });
  }
  const result = parseRelease(input);
  assert.equal(result.downloads.android, undefined);
  assert.equal(Object.keys(result.downloads).length, 4);
});
test('release without installers produces an empty download selection', () => {
  const input = releaseFixture(); input.assets = [];
  assert.deepEqual(parseRelease(input).downloads, {});
});
const invalidCases: [string, (data: Record<string, unknown>) => void][] = [
  ['foreign release', d => { d.html_url = 'https://github.com/other/shiori-reader/releases/tag/v1.4.0'; }],
  ['draft', d => { d.draft = true; }],
  ['prerelease', d => { d.prerelease = true; }],
  ['unbounded tag', d => { d.tag_name = '../other'; }],
  ['wrong date', d => { d.published_at = 'not a date'; }],
  ['missing asset array', d => { d.assets = null; }],
  ['duplicate expected file', d => { const a = d.assets as unknown[]; a.push(a[0]); }],
  ['unexpected host', d => { (d.assets as Record<string, unknown>[])[0]!.browser_download_url = 'https://evil.example/installer.apk'; }],
  ['query on installer URL', d => { const a = (d.assets as Record<string, unknown>[])[0]!; a.browser_download_url += '?next=evil'; }],
  ['wrong release in installer URL', d => { const a = (d.assets as Record<string, unknown>[])[0]!; a.browser_download_url = String(a.browser_download_url).replace('/download/' + String(d.tag_name) + '/', '/download/v99.99.99/'); }],
  ['zero file size', d => { (d.assets as Record<string, unknown>[])[0]!.size = 0; }],
];
for (const [label, mutate] of invalidCases) test(`rejects ${label}`, () => {
  const input = releaseFixture(); mutate(input);
  assert.throws(() => parseRelease(input), (e: unknown) => e instanceof ReleaseError && e.kind === 'invalid');
});
for (const invalid of [null, [], 'text', {}, { message: 'Not Found' }]) test(`rejects malformed data ${JSON.stringify(invalid)}`, () => {
  assert.throws(() => parseRelease(invalid), ReleaseError);
});
for (const [status, kind] of [[403, 'rate'], [429, 'rate'], [404, 'notfound'], [500, 'server']] as const) {
  test(`maps HTTP ${status} to actionable ${kind} failure`, async () => {
    const mock = (async () => new Response('{}', { status })) as typeof fetch;
    await assert.rejects(fetchRelease(mock), (e: unknown) => e instanceof ReleaseError && e.kind === kind);
  });
}
test('bounds even a request which never resolves', async () => {
  const mock = (() => new Promise<Response>(() => {})) as typeof fetch;
  await assert.rejects(fetchRelease(mock, 5), (e: unknown) => e instanceof ReleaseError && e.kind === 'timeout');
});
for (const [label, fetcher, kind] of [
  ['invalid JSON', async () => new Response('broken'), 'invalid'],
  ['network failure', async () => { throw new TypeError('offline'); }, 'network'],
] as [string, typeof fetch, ErrorKind][]) test(label, async () => {
  await assert.rejects(fetchRelease(fetcher), (e: unknown) => e instanceof ReleaseError && e.kind === kind);
});
test('fetches the official endpoint without credentials', async () => {
  const mock = (async (url, options) => {
    assert.equal(url, 'https://api.github.com/repos/Memory1031/shiori-reader/releases/latest');
    assert.equal(options?.credentials, 'omit');
    assert.equal(new Headers(options?.headers).has('Authorization'), false);
    return Response.json(releaseFixture());
  }) as typeof fetch;
  assert.equal((await fetchRelease(mock)).tag, releaseFixture().tag_name);
});

test('legacy ZIP remains available without guessing a missing Setup EXE URL', () => {
  const input = releaseFixture();
  input.assets = input.assets.filter(a => !a.name.endsWith('-setup.exe'));
  const result = parseRelease(input);
  assert.equal(result.downloads.windows, undefined);
  assert.ok(result.downloads.windowsPortable?.url.endsWith('-windows-x64.zip'));
});
