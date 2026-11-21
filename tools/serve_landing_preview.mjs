#!/usr/bin/env node
/**
 * Local preview of the landing page under the production base path (/front-office/).
 * Serves this repo's files, and maps /front-office/<sport>/data/<file> to
 * <sport data dir>/<file>. By default that is <sport>/web/public/data in the subtree mirror;
 * override with LANDING_DATA_<SPORT>=<dir> (e.g. a sport worktree's web/public/data).
 * Slideshow media: set LANDING_MEDIA_<SPORT>=<dir> to serve <sport>/media|animations/<file> from it.
 * Usage: node tools/serve_landing_preview.mjs [port]
 */
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT || process.argv[2] || 4173);
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.webp': 'image/webp', '.mp4': 'video/mp4',
  '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.gif': 'image/gif' };

function resolve(urlPath) {
  const p = decodeURIComponent(urlPath.split('?')[0]);
  if (!p.startsWith('/front-office/')) return null;
  const rel = p.slice('/front-office/'.length);
  const m = rel.match(/^(nfl|nba|wnba|mlb)\/data\/([\w.-]+\.json)$/);
  if (m) {
    const dir = process.env['LANDING_DATA_' + m[1].toUpperCase()] || join(ROOT, m[1], 'web', 'public', 'data');
    return join(dir, m[2]);
  }
  const mm = rel.match(/^(nfl|nba|wnba|mlb)\/(media|animations)\/([\w.-]+\.(?:gif|png))$/);
  if (mm && process.env['LANDING_MEDIA_' + mm[1].toUpperCase()]) return join(process.env['LANDING_MEDIA_' + mm[1].toUpperCase()], mm[3]);
  if (rel.split('/').includes('..')) return null;
  const safe = normalize(rel || 'index.html');
  return join(ROOT, safe.endsWith('/') || safe === '' ? safe + 'index.html' : safe);
}

createServer(async (req, res) => {
  if (req.url === '/' ) { res.writeHead(302, { Location: '/front-office/' }); return res.end(); }
  let file = resolve(req.url);
  if (!file) { res.writeHead(404); return res.end('not found'); }
  if (req.url.split('?')[0].endsWith('/')) file = join(file.replace(/index\.html$/, ''), 'index.html');
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': TYPES[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404); res.end('not found');
  }
}).listen(PORT, () => console.log(`Landing preview: http://localhost:${PORT}/front-office/`));
