// Pins the Markdown subset tools/build_doc_pages.mjs supports, and that both
// real docs render with no raw Markdown left over. Run: node tools/test_build_doc_pages.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { render, inline, slugify, PAGES } from './build_doc_pages.mjs';

assert.equal(slugify('Appendix: formulas'), 'appendix-formulas');
assert.equal(inline('**bold** and *it* and `a*b*c`'), '<strong>bold</strong> and <em>it</em> and <code>a*b*c</code>');
assert.equal(inline('[How](HOW_IT_WORKS.md)'), '<a href="../how-it-works/">How</a>');
assert.match(inline('[x](https://example.com)'), /rel="noopener noreferrer"/);
assert.equal(inline('rate $\sigma_x$ here'), 'rate $\sigma_x$ here');
const r = render('# T\n\n- one\n- two\n\n1. a\n2. b\n\n| A | B |\n| :--- | :--- |\n| **x** | y |\n\n$$a_b$$\n\n---\npara\nline');
assert.equal(r.title, 'T');
for (const frag of ['<ul><li>one</li><li>two</li></ul>', '<ol><li>a</li><li>b</li></ol>', '<td><strong>x</strong></td>', '<p class="math">$$a_b$$</p>', '<hr />', '<p>para line</p>'])
  assert.ok(r.html.includes(frag), frag);
for (const p of PAGES) {
  const { title, html } = render(readFileSync(new URL('../' + p.src, import.meta.url), 'utf8'));
  assert.ok(title, p.src);
  assert.doesNotMatch(html.replace(/<code>.*?<\/code>/g, ''), /\*\*|\]\(|^#/m, `${p.src}: raw markdown left`);
}
console.log('test_build_doc_pages: OK');
