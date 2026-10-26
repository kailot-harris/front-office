#!/usr/bin/env node
/**
 * Static file server for the exported site, used as Playwright's managed webServer.
 *
 * `next start` CANNOT serve this app: next.config.mjs sets `output: 'export'`, and
 * next start exits 1 with "does not work with output: export". That is why the e2e
 * stage silently ran zero tests for as long as the config pointed at it. What ships
 * is the contents of `out/` uploaded to GitHub Pages, so a plain static server over
 * `out/` is also the closer analogue of production.
 *
 * BASE PATH HANDLING — the one subtlety here.
 *
 * The export is built with `basePath: '/nfl'`, so every emitted URL inside the HTML
 * is `/nfl/_next/...`, while the files themselves sit at the root of `out/`. Content
 * is therefore served ONLY under the basePath, and an unprefixed request is handled
 * by prefix:
 *
 *   - PAGE requests without the prefix are 308-REDIRECTED to it: `/matchups`
 *     becomes `/nfl/matchups/`. This is what lets tests/e2e/* keep writing
 *     `page.goto('/matchups')` against a bare-host baseURL, while the URL the
 *     browser actually lands on still carries the basePath. That matters: Next's
 *     client router derives its own notion of the current path from the real URL,
 *     so serving pages at the bare path instead makes usePathname, <Link> and
 *     route prefetching all disagree with the build — active-nav state breaks and
 *     prefetches abort. Redirecting keeps the client on the same URL shape as prod.
 *   - BUILD-EMITTED ASSET requests (/_next/*, /data/*) are NOT redirected; an
 *     unprefixed one 404s on purpose. This app has already shipped the bug where a
 *     hand-written asset path lost its prefix and 404'd only in production (see the
 *     comment in lib/basePath.ts); papering over that here would let the same class
 *     of bug pass the suite.
 *
 * Also mirrors `trailingSlash: true` by 308-redirecting `/nfl/matchups` to
 * `/nfl/matchups/`, as Pages and next start both do.
 */
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { join, extname, resolve, sep } from 'node:path';

const ROOT = resolve(process.argv[3] ?? 'out');
const PORT = Number(process.argv[2] ?? process.env.E2E_PORT ?? 3100);
const BASE_PATH = `${process.env.PAGES_BASE_PATH ?? ''}/nfl`;

/** Paths the build emits with the basePath baked in; the prefix is not optional for these. */
const BUILD_EMITTED = [/^\/_next\//, /^\/data\//];

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
};

async function statOrNull(path) {
  try {
    return await stat(path);
  } catch {
    return null;
  }
}

/** Resolve a request pathname to a file inside ROOT, or a redirect, or nothing. */
async function resolveTarget(pathname) {
  let rest;
  if (pathname === BASE_PATH) return { redirect: `${BASE_PATH}/` };
  else if (pathname.startsWith(`${BASE_PATH}/`)) rest = pathname.slice(BASE_PATH.length);
  else if (BUILD_EMITTED.some((p) => p.test(pathname))) return { missing: true };
  else return { redirect: `${BASE_PATH}${pathname}` };

  // join() normalizes away any ../ in the request, but a traversal can still
  // resolve outside ROOT, so the containment check below is the actual guarantee
  // rather than the normalization.
  const candidate = resolve(join(ROOT, `.${rest}`));
  if (candidate !== ROOT && !candidate.startsWith(ROOT + sep)) return { missing: true };

  const direct = await statOrNull(candidate);
  if (direct?.isFile()) return { file: candidate };

  if (direct?.isDirectory()) {
    // trailingSlash: true — a directory URL without the slash is a 308, same as prod.
    if (!pathname.endsWith('/')) return { redirect: `${pathname}/` };
    const index = join(candidate, 'index.html');
    if ((await statOrNull(index))?.isFile()) return { file: index };
    return { missing: true };
  }

  const asHtml = `${candidate}.html`;
  if ((await statOrNull(asHtml))?.isFile()) return { file: asHtml };

  return { missing: true };
}

function send(res, status, file) {
  res.writeHead(status, {
    'content-type': TYPES[extname(file)] ?? 'application/octet-stream',
    'cache-control': 'no-store',
  });
  createReadStream(file).pipe(res);
}

const server = createServer(async (req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { allow: 'GET, HEAD' }).end('Method Not Allowed');
    return;
  }

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    res.writeHead(400, { 'content-type': 'text/plain' }).end('Bad Request');
    return;
  }

  const target = await resolveTarget(pathname);

  if (target.redirect) {
    const search = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
    res.writeHead(308, { location: `${target.redirect}${search}` }).end();
    return;
  }

  if (target.file) {
    send(res, 200, target.file);
    return;
  }

  const notFound = join(ROOT, '404.html');
  if ((await statOrNull(notFound))?.isFile()) send(res, 404, notFound);
  else res.writeHead(404, { 'content-type': 'text/plain' }).end('Not Found');
});

const missing = await statOrNull(ROOT);
if (!missing?.isDirectory()) {
  console.error(`serve-export: ${ROOT} does not exist — run \`npm run build\` first.`);
  process.exit(1);
}

server.listen(PORT, '127.0.0.1', () => {
  console.error(`serve-export: serving ${ROOT} at http://127.0.0.1:${PORT}${BASE_PATH}/`);
});
