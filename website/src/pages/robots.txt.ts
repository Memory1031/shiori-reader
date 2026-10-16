import type { APIRoute } from 'astro';
export const GET: APIRoute = () => new Response('User-agent: *\nAllow: /\nSitemap: https://memory1031.github.io/shiori-reader/sitemap.xml\n');
