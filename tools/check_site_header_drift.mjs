#!/usr/bin/env node
/**
 * Site-header drift check (front-office#218).
 *
 * The shared site header is copied by hand into three pages (chosen over a JS injector so the
 * nav works without JavaScript). The copies must be identical except for which link carries
 * aria-current="page", and each page must mark exactly its own link.
 *
 * Usage: node tools/check_site_header_drift.mjs [repo-root]
 * Exit 0 when all copies match; 1 (with a >>> [FAIL] line per problem) otherwise.
 */
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PAGES = [
  { file: 'index.html', current: '/front-office/' },
  { file: 'guide/index.html', current: '/front-office/guide/' },
  { file: 'how-it-works/index.html', current: '/front-office/how-it-works/' },
];

export function extractHeader(html) {
  const start = html.indexOf('<div class="site-header" data-site-header>');
  if (start === -1) return null;
  const end = html.indexOf('</div>', start);
  return end === -1 ? null : html.slice(start, end + '</div>'.length).replace(/\r\n/g, '\n');
}

export function check(root) {
  const errors = [];
  let reference = null;
  for (const p of PAGES) {
    let html;
    try { html = readFileSync(join(root, p.file), 'utf8'); } catch { errors.push(`${p.file}: missing`); continue; }
    const h = extractHeader(html);
    if (!h) { errors.push(`${p.file}: no site header`); continue; }
    const marked = [...h.matchAll(/<a href="([^"]+)" aria-current="page">/g)].map((m) => m[1]);
    if (marked.length !== 1 || marked[0] !== p.current) {
      errors.push(`${p.file}: aria-current should mark only ${p.current}, found [${marked.join(', ')}]`);
    }
    const norm = h.replace(/ aria-current="page"/g, '');
    if (reference === null) reference = { file: p.file, norm };
    else if (norm !== reference.norm) errors.push(`${p.file}: header differs from ${reference.file}`);
  }
  return errors;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const root = process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), '..');
  const errors = check(root);
  for (const e of errors) console.log(`>>> [FAIL] ${e}`);
  if (!errors.length) console.log(`>>> [OK] site header identical on ${PAGES.length} pages`);
  process.exit(errors.length ? 1 : 0);
}
