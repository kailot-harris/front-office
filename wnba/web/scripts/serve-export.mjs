#!/usr/bin/env node
/**
 * Serves the static export in out/ under the app's basePath (/wnba, or
 * $PAGES_BASE_PATH/wnba), the way GitHub Pages does. `next start` cannot serve
 * an `output: 'export'` app, so Playwright's webServer uses this instead.
 *
 * Usage: node scripts/serve-export.mjs [port]
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', 'out');
const PORT = Number(process.argv[2] ?? process.env.PORT ?? 3100);
const BASE = `${process.env.PAGES_BASE_PATH ?? ''}/wnba`;
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2', '.ico': 'image/x-icon', '.txt': 'text/plain', '.webp': 'image/webp',
};

if (!fs.existsSync(ROOT)) {
  console.error('out/ does not exist: run `npm run build` first.');
  process.exit(1);
}

http
  .createServer((req, res) => {
    const url = decodeURIComponent((req.url ?? '/').split('?')[0]);
    if (url === '/' || url === '') {
      res.writeHead(302, { Location: `${BASE}/` }).end();
      return;
    }
    if (!url.startsWith(BASE)) {
      res.writeHead(404).end('not found');
      return;
    }
    let file = path.join(ROOT, url.slice(BASE.length));
    if (!file.startsWith(ROOT)) {
      res.writeHead(403).end();
      return;
    }
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    if (!fs.existsSync(file)) {
      const notFound = path.join(ROOT, '404.html');
      res.writeHead(404, { 'Content-Type': TYPES['.html'] });
      fs.createReadStream(notFound).pipe(res);
      return;
    }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] ?? 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  })
  .listen(PORT, '127.0.0.1', () => console.log(`serving ${ROOT} at http://127.0.0.1:${PORT}${BASE}/`));
