#!/usr/bin/env node
/**
 * Renders the visitor docs (docs/WALKTHROUGH.md, docs/HOW_IT_WORKS.md) as
 * pages on the site, so the landing footer links to real pages instead of
 * GitHub's Markdown viewer. The Markdown files stay the single source; the
 * deploy runs this after assembling the site:
 *
 *   node tools/build_doc_pages.mjs site
 *
 * writes site/guide/index.html and site/how-it-works/index.html.
 *
 * Deliberately dependency-free like the other tools/*.mjs. It handles the
 * Markdown these two docs actually use (headings, paragraphs, bullet and
 * numbered lists, tables, rules, bold, italics, inline code, links) and
 * leaves $...$ / $$...$$ formulas for KaTeX to typeset in the browser.
 * tools/test_build_doc_pages.mjs pins that subset.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const PAGES = [
  { src: 'docs/WALKTHROUGH.md', slug: 'guide', description: 'How to use Front Office: find a team, read a forecast, compare players and check how accurate the models have been.' },
  { src: 'docs/HOW_IT_WORKS.md', slug: 'how-it-works', description: 'How Front Office turns public sports data into ratings, forecasts and player comparisons, and where the data runs out.' },
];

/** Links between the docs point at their page, not the .md file. */
const DOC_LINKS = { 'WALKTHROUGH.md': '../guide/', 'HOW_IT_WORKS.md': '../how-it-works/' };

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** GitHub-style heading anchor: lowercase, punctuation dropped, spaces to hyphens. */
export function slugify(text) {
  return text.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-');
}

export function inline(src) {
  // Protect inline code and math so emphasis rules never touch them.
  const keep = [];
  const stash = (html) => `\u0000${keep.push(html) - 1}\u0000`;
  let s = src.replace(/`([^`]+)`/g, (_, c) => stash(`<code>${esc(c)}</code>`));
  s = s.replace(/\$\$([^$]+)\$\$|\$([^$\n]+)\$/g, (m) => stash(esc(m)));
  s = esc(s);
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, text, href) => {
    const target = DOC_LINKS[href] ?? href;
    const external = /^https?:/.test(target) && !target.startsWith('https://kailot-harris.github.io/front-office/');
    return `<a href="${target}"${external ? ' rel="noopener noreferrer"' : ''}>${text}</a>`;
  });
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[^\w*])\*([^*\n]+)\*(?!\w)/g, '$1<em>$2</em>');
  s = s.replace(/(^|[^\w_])_([^_\n]+)_(?!\w)/g, '$1<em>$2</em>');
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => keep[Number(i)]);
}

const cells = (row) => row.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());

/** Markdown (the subset above) to an HTML fragment. Returns { title, html }. */
export function render(md) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const out = [];
  let title = '';
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    const h = line.match(/^(#{1,4})\s+(.*)$/);
    if (h) {
      const level = h[1].length;
      if (level === 1 && !title) title = h[2].trim();
      out.push(`<h${level} id="${slugify(h[2])}">${inline(h[2].trim())}</h${level}>`);
      i++; continue;
    }
    if (/^(-{3,}|\*{3,})\s*$/.test(line)) { out.push('<hr />'); i++; continue; }
    if (/^\$\$/.test(line.trim())) {
      const buf = [line.trim()];
      while (!/\$\$\s*$/.test(buf.join(' ').slice(2)) && i + 1 < lines.length) buf.push(lines[++i].trim());
      out.push(`<p class="math">${esc(buf.join(' '))}</p>`);
      i++; continue;
    }
    if (/^\|/.test(line) && i + 1 < lines.length && /^\|?\s*:?-{3,}/.test(lines[i + 1])) {
      const head = cells(line);
      i += 2;
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) rows.push(cells(lines[i++]));
      out.push('<div class="table-wrap"><table><thead><tr>' + head.map((c) => `<th scope="col">${inline(c)}</th>`).join('') +
        '</tr></thead><tbody>' + rows.map((r) => '<tr>' + r.map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>').join('') +
        '</tbody></table></div>');
      continue;
    }
    const list = line.match(/^\s*([-*]|\d+\.)\s+/);
    if (list) {
      const ordered = /\d/.test(list[1]);
      const items = [];
      while (i < lines.length && /^\s*([-*]|\d+\.)\s+/.test(lines[i])) {
        let item = lines[i++].replace(/^\s*([-*]|\d+\.)\s+/, '');
        while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*]|\d+\.)\s+/.test(lines[i])) item += ' ' + lines[i++].trim();
        items.push(`<li>${inline(item)}</li>`);
      }
      out.push(`<${ordered ? 'ol' : 'ul'}>${items.join('')}</${ordered ? 'ol' : 'ul'}>`);
      continue;
    }
    // Always take the current line, so a line no rule above claims (a lone
    // "|" row, say) becomes text instead of stalling the loop.
    const para = [lines[i++].trim()];
    while (i < lines.length && lines[i].trim() && !/^(#{1,4}\s|\||\s*([-*]|\d+\.)\s|-{3,}\s*$|\$\$)/.test(lines[i])) para.push(lines[i++].trim());
    out.push(`<p>${inline(para.join(' '))}</p>`);
  }
  return { title, html: out.join('\n') };
}

const KATEX = 'https://cdn.jsdelivr.net/npm/katex@0.16.11/dist';

export function page({ title, html }, { description, slug }) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${esc(title)} · Front Office</title>
  <meta name="description" content="${esc(description)}" />
  <link rel="canonical" href="https://kailot-harris.github.io/front-office/${slug}/" />
  <link rel="icon" href="../nfl/icon.png" type="image/png" />
  <link rel="stylesheet" href="../assets/fonts/fonts.css" />
  <link rel="stylesheet" href="../assets/design-tokens.css" />
  <link rel="stylesheet" href="${KATEX}/katex.min.css" crossorigin="anonymous" />
  <style>
    body { margin: 0; background: var(--fo-surface); color: var(--fo-text); font-family: var(--fo-font-sans); line-height: var(--fo-leading); }
    .doc-nav, main, footer { max-width: 46rem; margin: 0 auto; padding: 0 1.25rem; box-sizing: border-box; }
    .doc-nav { display: flex; gap: 1.25rem; flex-wrap: wrap; padding-top: 1.25rem; font-size: var(--fo-text-sm); }
    main { padding-bottom: 3rem; }
    h1 { font-size: 2rem; line-height: 1.2; margin: 1.5rem 0 1rem; }
    h2 { font-size: 1.35rem; margin: 2.25rem 0 0.75rem; scroll-margin-top: 1rem; }
    h3 { font-size: 1.1rem; margin: 1.75rem 0 0.5rem; }
    a { color: var(--fo-link, var(--fo-nba-accent)); text-underline-offset: 2px; }
    a:focus-visible { outline: var(--fo-focus-width) solid currentColor; outline-offset: 2px; }
    hr { border: 0; border-top: 1px solid var(--fo-border); margin: 2rem 0; }
    code { font-family: var(--fo-font-mono); font-size: 0.9em; padding: 0.1em 0.35em; border: 1px solid var(--fo-border); border-radius: var(--fo-radius-sm); }
    li { margin: 0.3rem 0; }
    .table-wrap { overflow-x: auto; }
    table { border-collapse: collapse; width: 100%; font-size: var(--fo-text-sm); }
    th, td { text-align: left; vertical-align: top; padding: 0.5rem 0.6rem; border-bottom: 1px solid var(--fo-border); }
    .math { overflow-x: auto; }
    .muted, footer { color: var(--fo-text-muted); }
    footer { border-top: 1px solid var(--fo-border); padding-top: 1rem; padding-bottom: 2rem; font-size: var(--fo-text-sm); }
  </style>
</head>
<body>
  <nav class="doc-nav" aria-label="Site">
    <a href="../">&larr; Front Office home</a>
    <a href="../guide/"${slug === 'guide' ? ' aria-current="page"' : ''}>Start here</a>
    <a href="../how-it-works/"${slug === 'how-it-works' ? ' aria-current="page"' : ''}>How the models work</a>
  </nav>
  <main>
${html}
  </main>
  <footer>Front Office &middot; Data and forecasts for the NFL, NBA, WNBA and MLB</footer>
  <script defer src="${KATEX}/katex.min.js" crossorigin="anonymous"></script>
  <script defer src="${KATEX}/contrib/auto-render.min.js" crossorigin="anonymous"
    onload="renderMathInElement(document.querySelector('main'),{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false}],throwOnError:false})"></script>
</body>
</html>
`;
}

function main() {
  const outDir = process.argv[2];
  if (!outDir) { console.error('usage: node tools/build_doc_pages.mjs <site-dir>'); process.exit(2); }
  for (const p of PAGES) {
    const doc = render(readFileSync(join(ROOT, p.src), 'utf8'));
    if (!doc.title) { console.error(`build_doc_pages: ${p.src} has no top-level heading`); process.exit(1); }
    const dir = join(outDir, p.slug);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'index.html'), page(doc, p));
    console.log(`build_doc_pages: ${p.src} -> ${p.slug}/index.html`);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
