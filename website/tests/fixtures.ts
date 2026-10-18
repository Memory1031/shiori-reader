export function releaseFixture(tag = 'v0.0.0') {
  const root = 'https://github.com/Memory1031/shiori-reader/releases';
  const names = ['android.apk', 'windows-x64-setup.exe', 'windows-x64.zip', 'macos-universal.dmg', 'ios-arm64-unsigned.ipa'];
  return {
    tag_name: tag, draft: false, prerelease: false, published_at: '2026-10-16T09:43:45Z', html_url: `${root}/tag/${tag}`,
    assets: names.map(suffix => ({ name: `shiori-reader-${tag}-${suffix}`, size: 20_000_000, browser_download_url: `${root}/download/${tag}/shiori-reader-${tag}-${suffix}` })),
  };
}
