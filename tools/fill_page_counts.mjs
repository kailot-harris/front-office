#!/usr/bin/env node
// Page counts derived from nav/switcher.json (front-office#91 follow-up).
//
// Elements marked data-count="nfl|nba|wnba|mlb|all" hold a page count:
//   - the integer in the element's own text (when it has no child tags), and
//   - the integer in each attribute named by data-count-attr="a,b".
// nav/switcher.json lists every sport's sidebar pages and is itself checked
// against each Sidebar.tsx (tools/test_switcher_table.mjs), so these counts
// follow the real sites.
//
//   node tools/fill_page_counts.mjs --check [files...]   exit 1 on any stale count
//   node tools/fill_page_counts.mjs --write <dir>        rewrite the site copies in <dir>
//
// Fails when a listed file has no marker, a marker names an unknown sport, or a
// marked place holds no integer: a silent no-op would publish stale numbers.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const SITE_FILES = ['index.html', 'guide/index.html', 'how-it-works/index.html'];
const CHECK_ONLY = ['README.md'];

export function counts(table) {
  const out = {};
  let all = 0;
  for (const [sport, entry] of Object.entries(table.sports)) {
    out[sport] = Object.keys(entry.pages).length;
    all += out[sport];
  }
  out.all = all;
  return out;
}

const TAG = /<([a-zA-Z][\w-]*)\b([^>]*\bdata-count="([^"]*)"[^>]*)>/g;
const ATTR = (name) => new RegExp(`(\\s${name}=")([^"]*)(")`);
const firstInt = /\d[\d,]*/;

/** Returns { html, changes: [{where, from, to}], errors: [] }. */
export function fill(html, c, file = '') {
  const changes = [];
  const errors = [];
  let markers = 0;
  const out = html.replace(TAG, (tag, name, attrs, key, offset) => {
    markers++;
    const want = c[key];
    const line = html.slice(0, offset).split('\n').length;
    const where = `${file}:${line} [${key}]`;
    if (want === undefined) { errors.push(`${where}: unknown data-count "${key}"`); return tag; }
    let newAttrs = attrs;
    const listed = (attrs.match(/\bdata-count-attr="([^"]*)"/)?.[1] ?? '').split(',').map((s) => s.trim()).filter(Boolean);
    for (const a of listed) {
      const m = newAttrs.match(ATTR(a));
      if (!m || !firstInt.test(m[2])) { errors.push(`${where}: attribute ${a} has no number`); continue; }
      const from = m[2].match(firstInt)[0];
      if (from !== String(want)) changes.push({ where: `${where} ${a}`, from, to: String(want) });
      newAttrs = newAttrs.replace(ATTR(a), (_, p, v, q) => `${p}${v.replace(firstInt, String(want))}${q}`);
    }
    return `<${name}${newAttrs}>`;
  });
  // Text: the integer inside <x data-count="k">...</x> when the content has no tags.
  let html2 = out.replace(/(<([a-zA-Z][\w-]*)\b[^>]*\bdata-count="([^"]*)"[^>]*>)([^<]*)(<\/\2>)/g, (m, open, _n, key, text, close, offset) => {
    const want = c[key];
    if (want === undefined) return m;
    const hasAttrList = /\bdata-count-attr=/.test(open);
    if (!firstInt.test(text)) {
      if (!hasAttrList) errors.push(`${file}:${out.slice(0, offset).split('\n').length} [${key}]: text has no number`);
      return m;
    }
    const from = text.match(firstInt)[0];
    if (from !== String(want)) changes.push({ where: `${file}:${out.slice(0, offset).split('\n').length} [${key}] text`, from, to: String(want) });
    return `${open}${text.replace(firstInt, String(want))}${close}`;
  });
  if (markers === 0) errors.push(`${file}: no data-count markers`);
  return { html: html2, changes, errors };
}

function main() {
  const [mode, ...rest] = process.argv.slice(2);
  const c = counts(JSON.parse(readFileSync(join(root, 'nav', 'switcher.json'), 'utf8')));
  let failed = false;
  if (mode === '--check') {
    const files = rest.length ? rest : [...SITE_FILES, ...CHECK_ONLY];
    for (const f of files) {
      const { changes, errors } = fill(readFileSync(join(root, f), 'utf8'), c, f);
      for (const e of errors) { console.error(e); failed = true; }
      for (const ch of changes) { console.error(`${ch.where}: says ${ch.from}, pages are ${ch.to}`); failed = true; }
    }
    if (failed) { console.error('Run: node tools/fill_page_counts.mjs --write . to update the committed copies.'); process.exit(1); }
    console.log(`page counts OK (${JSON.stringify(c)})`);
  } else if (mode === '--write') {
    const dir = rest[0];
    if (!dir) { console.error('usage: --write <dir>'); process.exit(2); }
    for (const f of SITE_FILES) {
      const p = join(dir, f);
      const { html, changes, errors } = fill(readFileSync(p, 'utf8'), c, f);
      for (const e of errors) { console.error(e); failed = true; }
      if (!failed) writeFileSync(p, html);
      for (const ch of changes) console.log(`${ch.where}: ${ch.from} -> ${ch.to}`);
    }
    if (dir === '.' || dir === root) {
      for (const f of CHECK_ONLY) {
        const { html, errors } = fill(readFileSync(join(root, f), 'utf8'), c, f);
        if (errors.length) { errors.forEach((e) => console.error(e)); failed = true; } else writeFileSync(join(root, f), html);
      }
    }
    if (failed) process.exit(1);
    console.log(`page counts written (${JSON.stringify(c)})`);
  } else {
    console.error('usage: fill_page_counts.mjs --check [files...] | --write <dir>');
    process.exit(2);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
