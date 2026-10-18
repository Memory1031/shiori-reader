export const platforms = ['android', 'windows', 'macos', 'ios'] as const;
export type Platform = typeof platforms[number];
export type Download = { name: string; url: string; size: number };
export type Release = { tag: string; date: string; url: string; downloads: Partial<Record<Platform | 'windowsPortable', Download>> };
export type ErrorKind = 'network' | 'timeout' | 'rate' | 'notfound' | 'server' | 'invalid';
export class ReleaseError extends Error {
  readonly kind: ErrorKind;
  constructor(kind: ErrorKind) { super(kind); this.kind = kind; }
}
export const endpoint = 'https://api.github.com/repos/Memory1031/shiori-reader/releases/latest';
const origin = 'https://github.com/Memory1031/shiori-reader/releases';
const suffix = {
  android: 'android.apk', windows: 'windows-x64-setup.exe', windowsPortable: 'windows-x64.zip', macos: 'macos-universal.dmg', ios: 'ios-arm64-unsigned.ipa',
};
const object = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);

export function parseRelease(input: unknown): Release {
  const invalid = () => { throw new ReleaseError('invalid'); };
  if (!object(input)) return invalid();
  const tag = input.tag_name, date = input.published_at;
  if (typeof tag !== 'string' || !/^v\d+\.\d+\.\d+$/.test(tag) ||
      input.draft !== false || input.prerelease !== false ||
      input.html_url !== `${origin}/tag/${tag}` ||
      typeof date !== 'string' || !/^\d{4}-\d\d-\d\dT/.test(date) || !Number.isFinite(Date.parse(date)) ||
      !Array.isArray(input.assets)) return invalid();
  const downloads: Release['downloads'] = {};
  for (const asset of input.assets) {
    if (!object(asset) || typeof asset.name !== 'string') return invalid();
    for (const platform of Object.keys(suffix) as (keyof typeof suffix)[]) {
      const name = `shiori-reader-${tag}-${suffix[platform]}`;
      if (asset.name !== name) continue;
      if (downloads[platform] || asset.browser_download_url !== `${origin}/download/${tag}/${name}` ||
          typeof asset.size !== 'number' || !Number.isSafeInteger(asset.size) || asset.size <= 0) return invalid();
      downloads[platform] = { name, url: asset.browser_download_url, size: asset.size };
    }
  }
  return { tag, date, url: input.html_url as string, downloads };
}

export async function fetchRelease(fetcher: typeof fetch = fetch, timeout = 8000): Promise<Release> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => { controller.abort(); reject(new ReleaseError('timeout')); }, timeout);
  });
  try {
    return await Promise.race([deadline, (async () => {
      const response = await fetcher(endpoint, { signal: controller.signal, headers: { Accept: 'application/vnd.github+json' }, credentials: 'omit' });
      if (response.status === 403 || response.status === 429) throw new ReleaseError('rate');
      if (response.status === 404) throw new ReleaseError('notfound');
      if (response.status >= 500) throw new ReleaseError('server');
      if (!response.ok) throw new ReleaseError('network');
      let value: unknown;
      try { value = await response.json(); } catch { throw new ReleaseError('invalid'); }
      return parseRelease(value);
    })()]);
  } catch (error) {
    if (error instanceof ReleaseError) throw error;
    throw new ReleaseError(controller.signal.aborted ? 'timeout' : 'network');
  } finally { clearTimeout(timer); }
}

// A single request shared by components; failures may be retried explicitly.
let pending: Promise<Release> | undefined;
export function loadRelease(retry = false): Promise<Release> {
  if (retry) pending = undefined;
  return pending ??= fetchRelease();
}
