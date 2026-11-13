#!/usr/bin/env node
/**
 * Nav-sync guard for the landing-page accordion (front-office#110).
 *
 * index.html's per-sport accordion is a hand-written <ul class="tab-list">
 * list of links. Nothing kept it in sync with each sport's own
 * web/components/Sidebar.tsx nav-item array, so the two drifted: as of the
 * 2026-11-10 comparison, NFL's accordion was missing three live Sidebar
 * tabs (/passing, /dna, /clutch -- reachable only by typing the URL
 * directly), and WNBA's accordion and Sidebar disagreed in both
 * directions.
 *
 * This script is the mechanical guard the issue asks for: it extracts the
 * {href, label} set each sport's Sidebar.tsx actually declares, extracts
 * the {href, label} set index.html's accordion actually links to for that
 * sport, and fails (non-zero exit) if they differ -- unless the exact
 * (sport, href) pair is on NAV_SYNC_EXCEPTIONS below, with a reason.
 *
 * Reads Sidebar.tsx from this repo's own read-only subtree mirrors (mlb/,
 * nba/, nfl/, wnba/ at the repo root -- kept current by `git subtree pull`)
 * rather than reaching into the sibling sport-repo checkouts, so this
 * script only depends on files that live inside this repo. Never writes to
 * those mirror directories.
 *
 * Usage:
 *   node tools/check_sport_nav_sync.mjs [path/to/index.html]
 *
 * Exits non-zero and prints every (sport, href) mismatch -- missing from
 * the accordion, missing from the Sidebar, or present in both with a
 * different label -- if any sport's Sidebar/accordion sets diverge beyond
 * the exceptions list.
 */

import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..');
const INDEX_HTML_PATH = process.argv[2]
  ? join(process.cwd(), process.argv[2])
  : join(REPO_ROOT, 'index.html');

const SPORTS = ['mlb', 'nba', 'nfl', 'wnba'];

// Accordion links that are deliberately NOT a 1:1 mirror of their sport's
// Sidebar.tsx, with a reason each. Keep this list short and specific (one
// entry per (sport, href) pair) -- it is an escape hatch for a documented,
// decided exception, not a place to silence a real drift.
//
// front-office#110: WNBA's web/app/cap-sheet and web/app/offseason pages
// exist and build successfully, but WNBA Analytics' own Sidebar.tsx does
// not link them (confirmed live against WNBA Analytics/web/components/
// Sidebar.tsx -- this is a gap in that repo's own nav, out of scope for the
// aggregator to fix by editing another repo's Sidebar.tsx). Keeping the
// accordion links means the pages stay reachable from the landing page
// until WNBA Analytics adds them to its sidebar; remove this exception
// (and drop the links, or keep them if Sidebar catches up) once that
// upstream gap is resolved.
const NAV_SYNC_EXCEPTIONS = [
  { sport: 'wnba', href: '/cap-sheet', reason: 'page exists; not yet in WNBA Sidebar.tsx nav (upstream gap, front-office#110)' },
  { sport: 'wnba', href: '/offseason', reason: 'page exists; not yet in WNBA Sidebar.tsx nav (upstream gap, front-office#110)' },
];

function readFileSafe(p) {
  try {
    return readFileSync(p, 'utf8');
  } catch {
    return null;
  }
}

function decodeHtmlEntities(s) {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&deg;/g, '°')
    .replace(/&hellip;/g, '…')
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)));
}

/**
 * Extracts {href, label} pairs from a Sidebar.tsx nav-item array. Every
 * sport's Sidebar.tsx writes each nav item as an object literal with an
 * `href:` property immediately followed (next non-blank property line) by
 * a `label:` property -- confirmed against all four sports' current
 * Sidebar.tsx as of this script's writing. If a sport ever reorders those
 * two properties this extraction will under-count, which is a loud "0
 * items found" failure below, not a silent miss.
 */
function extractSidebarNavItems(content) {
  const items = [];
  const pairRegex = /href:\s*(['"`])((?:(?!\1).)*)\1\s*,\s*\n\s*label:\s*(['"`])((?:(?!\3).)*)\3/g;
  let m;
  while ((m = pairRegex.exec(content)) !== null) {
    items.push({ href: m[2], label: m[4] });
  }
  return items;
}

/**
 * Extracts {href, label} pairs from index.html's
 * <ul class="tab-list" id="modules-{sport}">...</ul> accordion block.
 */
function extractAccordionNavItems(html, sport) {
  const ulRegex = new RegExp(`<ul[^>]*id="modules-${sport}"[^>]*>([\\s\\S]*?)<\\/ul>`, 'i');
  const ulMatch = ulRegex.exec(html);
  if (!ulMatch) return null;
  const block = ulMatch[1];
  const items = [];
  const liRegex = /<a\s+href="([^"]*)"[^>]*>([^<]*)<\/a>/g;
  let m;
  while ((m = liRegex.exec(block)) !== null) {
    const rawHref = m[1];
    // Accordion hrefs are "<sport>/" (root) or "<sport>/<slug>/"; normalize
    // to the Sidebar's own "/" or "/<slug>" form.
    const stripped = rawHref.replace(new RegExp(`^${sport}/`), '').replace(/\/$/, '');
    const normalizedHref = stripped === '' ? '/' : `/${stripped}`;
    items.push({ href: normalizedHref, label: decodeHtmlEntities(m[2]).trim() });
  }
  return items;
}

function toMap(items) {
  const map = new Map();
  for (const item of items) map.set(item.href, item.label);
  return map;
}

function main() {
  const html = readFileSafe(INDEX_HTML_PATH);
  if (html === null) {
    console.error(`check_sport_nav_sync: could not read ${INDEX_HTML_PATH}`);
    process.exit(1);
  }

  const exceptionsBySport = new Map();
  for (const ex of NAV_SYNC_EXCEPTIONS) {
    if (!exceptionsBySport.has(ex.sport)) exceptionsBySport.set(ex.sport, new Set());
    exceptionsBySport.get(ex.sport).add(ex.href);
  }

  const allFailures = [];

  for (const sport of SPORTS) {
    const sidebarPath = join(REPO_ROOT, sport, 'web', 'components', 'Sidebar.tsx');
    if (!existsSync(sidebarPath)) {
      allFailures.push(`[${sport}] Sidebar.tsx not found at ${sidebarPath} (subtree mirror missing or stale -- run the subtree sync)`);
      continue;
    }
    const sidebarContent = readFileSafe(sidebarPath);
    const sidebarItems = extractSidebarNavItems(sidebarContent);
    if (sidebarItems.length === 0) {
      allFailures.push(`[${sport}] extracted 0 nav items from Sidebar.tsx -- extraction regex may be out of date with this sport's Sidebar.tsx shape`);
      continue;
    }

    const accordionItems = extractAccordionNavItems(html, sport);
    if (accordionItems === null) {
      allFailures.push(`[${sport}] index.html has no <ul id="modules-${sport}"> accordion block`);
      continue;
    }

    const sidebarMap = toMap(sidebarItems);
    const accordionMap = toMap(accordionItems);
    const exceptions = exceptionsBySport.get(sport) ?? new Set();

    const sidebarHrefs = new Set(sidebarMap.keys());
    const accordionHrefs = new Set(accordionMap.keys());

    const missingFromAccordion = [...sidebarHrefs].filter((h) => !accordionHrefs.has(h));
    const extraInAccordion = [...accordionHrefs].filter((h) => !sidebarHrefs.has(h) && !exceptions.has(h));
    const labelMismatches = [...sidebarHrefs]
      .filter((h) => accordionHrefs.has(h) && sidebarMap.get(h) !== accordionMap.get(h))
      .map((h) => ({ href: h, sidebarLabel: sidebarMap.get(h), accordionLabel: accordionMap.get(h) }));

    for (const h of missingFromAccordion) {
      allFailures.push(`[${sport}] Sidebar tab '${h}' (${sidebarMap.get(h)}) is missing from the landing-page accordion`);
    }
    for (const h of extraInAccordion) {
      allFailures.push(`[${sport}] accordion link '${h}' (${accordionMap.get(h)}) is not a Sidebar tab and is not on the exceptions list`);
    }
    for (const lm of labelMismatches) {
      allFailures.push(`[${sport}] '${lm.href}' label mismatch: Sidebar says '${lm.sidebarLabel}', accordion says '${lm.accordionLabel}'`);
    }
  }

  if (allFailures.length > 0) {
    console.error('check_sport_nav_sync: FAILED -- landing-page accordion is out of sync with a sport Sidebar (front-office#110):');
    for (const f of allFailures) console.error(`  - ${f}`);
    console.error('');
    console.error('Fix: update the accordion <ul id="modules-<sport>"> in index.html to match that');
    console.error('sport\'s web/components/Sidebar.tsx nav items, or add a short, reasoned entry to');
    console.error('NAV_SYNC_EXCEPTIONS in this script if the divergence is deliberate.');
    process.exit(1);
  }

  console.log(`check_sport_nav_sync: OK -- accordion and Sidebar agree for all ${SPORTS.length} sports (${NAV_SYNC_EXCEPTIONS.length} documented exception(s))`);
}

main();
