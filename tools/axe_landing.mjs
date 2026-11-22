#!/usr/bin/env node
// Accessibility check for the landing page (front-office#206) and the guide pages /guide/ and
// /how-it-works/ (front-office#218): axe in light and dark mode,
// failing on serious or critical violations. Serves the page with tools/serve_landing_preview.mjs,
// using tools/fixtures/landing/<sport> as digest data unless LANDING_DATA_<SPORT> is set.
// Needs playwright and @axe-core/playwright (CI installs them with --no-save).
import { spawn } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { AxeBuilder } from '@axe-core/playwright';

const here = dirname(fileURLToPath(import.meta.url));
const PORT = process.env.AXE_PORT || '4191';
const env = { ...process.env, PORT };
for (const s of ['nfl', 'nba', 'wnba', 'mlb']) {
  env['LANDING_DATA_' + s.toUpperCase()] ??= join(here, 'fixtures', 'landing', s);
}
const server = spawn(process.execPath, [join(here, 'serve_landing_preview.mjs')], { env, stdio: 'ignore' });
const url = `http://localhost:${PORT}/front-office/`;
const PAGES = [
  { path: '', ready: () => /loaded/i.test(document.getElementById('dg-status')?.textContent || '') },
  { path: 'guide/', ready: () => document.readyState === 'complete' },
  { path: 'how-it-works/', ready: () => document.readyState === 'complete' && !!document.querySelector('.katex') },
];
let failed = 0;
try {
  for (let i = 0; i < 50; i++) { try { await fetch(url); break; } catch { await new Promise(r => setTimeout(r, 100)); } }
  const browser = await chromium.launch();
  for (const colorScheme of ['light', 'dark']) {
   for (const p of PAGES) {
    const context = await browser.newContext({ colorScheme });
    const page = await context.newPage();
    await page.goto(url + p.path);
    await page.waitForFunction(p.ready);
    const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
    const bad = violations.filter(v => v.impact === 'serious' || v.impact === 'critical');
    console.log(`/${p.path} ${colorScheme}: ${violations.length} violations, ${bad.length} serious or critical`);
    for (const v of bad) {
      console.log(`  ${v.impact} ${v.id}: ${v.help}`);
      for (const n of v.nodes.slice(0, 12)) console.log("    " + n.target.join(" ") + "  " + (n.any[0]?.message || ""));
    }
    failed += bad.length;
    await context.close();
   }
  }
  await browser.close();
} finally { server.kill(); }
process.exit(failed ? 1 : 0);
