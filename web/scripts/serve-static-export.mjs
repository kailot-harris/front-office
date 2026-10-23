/**
 * Static file server for the `next build` export in `out/`.
 *
 * WHY THIS EXISTS. next.config.mjs sets `output: 'export'`, and `next start`
 * refuses to run against an exported site at all ("next start does not work
 * with output: export"). The Playwright config used to launch `next start`
 * anyway, so its managed webServer died on boot and the whole E2E stage
 * reported 0 tests instead of failing - the suite claimed coverage it did not
 * have. This serves the real shipped artifact instead, which is also closer to
 * production than `next dev` would be: GitHub Pages serves these same files.
 *
 * TWO THINGS THE EXPORT NEEDS FROM A SERVER.
 *
 * 1. basePath. next.config.mjs builds with basePath `${PAGES_BASE_PATH}/nba`,
 *    so every asset and client-side link in the HTML is absolute and prefixed:
 *    /nba/_next/..., /nba/data/*.json. But `out/` is itself the basePath root -
 *    out/index.html IS /nba/. So the prefix is accepted and stripped rather
 *    than being a real directory, and the same files are reachable with or
 *    without it. That lets the specs keep using unprefixed paths ('/players')
 *    while the pages' own prefixed asset URLs resolve.
 *
 * 2. trailingSlash. The export writes directories of index.html, so a request
 *    for an extensionless path is served that directory's index.html directly
 *    with a 200 - no redirect, because tests/e2e/smoke.spec.ts asserts
 *    response.status() === 200 on each route.
 *
 * Deliberately dependency-free (node:http + node:fs) rather than `npx serve`:
 * the test suite should not reach the network to start, and the basePath
 * aliasing above is not something a generic static server does.
 */
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { join, extname, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_DIR = fileURLToPath(new URL('..', import.meta.url));
const OUT_DIR = join(WEB_DIR, 'out');
const PORT = Number(process.env.E2E_PORT ?? 3100);
const HOST = process.env.E2E_HOST ?? '127.0.0.1';
// Mirrors next.config.mjs. Keep in step with it if the slug or repo base moves.
const BASE_PATH = `${process.env.PAGES_BASE_PATH ?? ''}/nba`;

if (!existsSync(join(OUT_DIR, 'index.html'))) {
  console.error(
    `[serve-static-export] No export found at ${OUT_DIR}.\n` +
      `Run \`npx next build\` first - the E2E stage tests the built artifact, not the source.`
  );
  process.exit(1);
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.map': 'application/json; charset=utf-8',
};

/** Request path -> a file inside out/, or null if it escapes or does not exist. */
function resolveFile(urlPath) {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(urlPath, 'http://localhost').pathname);
  } catch {
    return null;
  }

  // Accept and strip the build's basePath (see note 1 above).
  if (pathname === BASE_PATH) pathname = '/';
  else if (pathname.startsWith(`${BASE_PATH}/`)) pathname = pathname.slice(BASE_PATH.length);

  // Containment check before touching the filesystem: normalize resolves any
  // ../ segments, and the result must still sit under out/.
  const candidate = normalize(join(OUT_DIR, pathname));
  if (candidate !== OUT_DIR && !candidate.startsWith(OUT_DIR + sep)) return null;

  const tries = extname(candidate)
    ? [candidate]
    : // Extensionless: the directory's index.html, then the flat-file form
      // (`/404` -> out/404.html) the exporter also emits.
      [join(candidate, 'index.html'), `${candidate}.html`];

  for (const file of tries) {
    if (existsSync(file) && statSync(file).isFile()) return file;
  }
  return null;
}

function send(res, status, file) {
  res.writeHead(status, {
    'Content-Type': MIME[extname(file)] ?? 'application/octet-stream',
    'Cache-Control': 'no-store',
  });
  createReadStream(file).pipe(res);
}

const server = createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { Allow: 'GET, HEAD' }).end();
    return;
  }

  const file = resolveFile(req.url ?? '/');
  if (file) {
    send(res, 200, file);
    return;
  }

  // Unknown path: the exported 404 page, with a real 404 so a spec asserting
  // on status still sees the miss.
  const notFound = join(OUT_DIR, '404.html');
  if (existsSync(notFound)) {
    send(res, 404, notFound);
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('404 Not Found\n');
});

server.listen(PORT, HOST, () => {
  console.log(`[serve-static-export] ${OUT_DIR} on http://${HOST}:${PORT} (basePath ${BASE_PATH})`);
});
