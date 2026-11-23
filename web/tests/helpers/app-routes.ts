/**
 * Routes read from the filesystem (#82): every `app/<route>/page.tsx` is a route.
 * Tests build their route lists from here so adding a page cannot leave a
 * hand-kept list behind.
 */
import { readdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { MOVED_ROUTES } from '../e2e/routes';

const APP_DIR = path.resolve(import.meta.dirname, '..', '..', 'app');

/** Every route under app/, as '/' or '/name'. Route groups `(x)` add no segment. */
export function appRoutes(dir = APP_DIR, prefix = ''): string[] {
  const out: string[] = [];
  if (existsSync(path.join(dir, 'page.tsx'))) out.push(prefix || '/');
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (!e.isDirectory() || e.name.startsWith('_') || e.name.startsWith('[')) continue;
    const seg = e.name.startsWith('(') ? '' : `/${e.name}`;
    out.push(...appRoutes(path.join(dir, e.name), prefix + seg));
  }
  return out.sort();
}

/** Routes that render a real page: app routes minus the forwarding stubs. */
export function servedRoutes(): string[] {
  const moved = new Set(MOVED_ROUTES.map(([from]) => from));
  return appRoutes().filter((r) => !moved.has(r));
}
