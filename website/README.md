# Shiori 官网

Astro 静态网站，入口为 `/shiori-reader/zh-cn/` 和 `/shiori-reader/en/`，各有独立下载页。
需要 Node.js 22.22.0 及以上；CI 固定 Node 22，依赖通过 npm lockfile 锁定。

```sh
cd website
npm ci
npm run dev
npm run check
npm test
npm run build
npm run preview
```

`npm run test:browser` 对已启动的本地预览执行浏览器检查，默认地址为
`http://127.0.0.1:4321/shiori-reader/`，可用 `WEBSITE_URL` 修改。
Linux / macOS 首次使用需要 `npx playwright install chromium`；Windows 默认使用已安装的 Chrome。
可通过 `WEBSITE_BROWSER` 指定 Playwright 浏览器 channel。截图输出到仓库忽略目录 `.tooling/evidence/website/`。

## 素材与文案

`scripts/assets.mjs` 维护素材白名单；构建前从仓库现有截图、品牌图和原创演示小说封面生成 WebP、图标与分享图，输出 `public/media/`，不重复提交原图或生成文件。
`src/data/showcase.ts` 单独控制各语言的书签展示图片。当前中文使用真实 Android 书签图，英文使用文字介绍；替换图片时同步白名单与说明，不使用未经认可的界面。
中英文文案位于 `src/i18n/copy.ts`，由同一类型约束。

## 下载与部署

浏览器请求官方 GitHub Releases latest API，校验正式标签、来源和安装包名称，使用返回的下载地址。
构建不查询 Releases，不固化应用版本；新正式版发布后无需重建官网。API 失败或禁用 JavaScript 时仍可通过 Releases 下载。

`.github/workflows/pages.yml` 独立执行检查、构建与 Pages 部署；PR 仅构建，不部署。
仓库 Settings → Pages → Build and deployment → Source 选择 **GitHub Actions**。
生产地址为 <https://memory1031.github.io/shiori-reader/>，部署来源为 develop。
