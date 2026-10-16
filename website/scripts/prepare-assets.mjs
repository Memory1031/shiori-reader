import sharp from 'sharp';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { assets } from './assets.mjs';

const root = new URL('../../', import.meta.url);
const output = new URL('../public/media/', import.meta.url);
await mkdir(output, { recursive: true });
const dimensions = {};
for (const [name, asset] of Object.entries(assets)) {
  const input = fileURLToPath(new URL(asset.source, root));
  const { width, height } = await sharp(input).metadata();
  dimensions[name] = { width, height, widths: asset.widths };
  await Promise.all(asset.widths.map(size => sharp(input).resize({ width: size })
    .webp({ quality: 86, effort: 5 }).toFile(fileURLToPath(new URL(`${name}-${size}.webp`, output)))));
}
await writeFile(new URL('dimensions.json', output), JSON.stringify(dimensions));
await sharp(fileURLToPath(new URL(assets.logo.source, root))).resize(64, 64).png()
  .toFile(fileURLToPath(new URL('favicon.png', output)));
for (const lang of ['zh', 'en']) {
  const cover = await sharp(fileURLToPath(new URL(assets[`cover-${lang}`].source, root)))
    .resize(360, 540, { fit: 'contain', background: '#faf8f4' }).toBuffer();
  const logo = await sharp(fileURLToPath(new URL(assets.logo.source, root))).resize(140).toBuffer();
  const text = Buffer.from(`<svg width="1200" height="630"><text x="90" y="295" font-family="sans-serif" font-size="92" fill="#302c2b">Shiori</text><text x="94" y="365" font-family="sans-serif" font-size="28" fill="#52756b">EPUB / TXT · Android · iOS · Windows · macOS</text></svg>`);
  await sharp({ create: { width: 1200, height: 630, channels: 3, background: '#faf8f4' } })
    .composite([{ input: cover, left: 790, top: 45 }, { input: logo, left: 88, top: 48 }, { input: text }])
    .jpeg({ quality: 88 }).toFile(fileURLToPath(new URL(`share-${lang}.jpg`, output)));
}
console.log(`Prepared ${Object.keys(assets).length} selected assets from repository originals.`);
