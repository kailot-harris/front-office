import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

// front-office#201: web/app/design-tokens.css is a byte-for-byte copy of the
// aggregator's canonical assets/design-tokens.css. Never edit it here; change
// the canonical file, then recopy it and update this hash.
const CANONICAL_SHA256 = 'd91f4b884ecb3148a5902f26213c1c209d54107544d9d6340fb63b1db68c0e58';
const TOKENS = path.resolve(import.meta.dirname, '../../app/design-tokens.css');

describe('shared design tokens', () => {
  it('matches the canonical sha256 byte-for-byte', () => {
    const hash = createHash('sha256').update(fs.readFileSync(TOKENS)).digest('hex');
    expect(hash).toBe(CANONICAL_SHA256);
  });

  it('is imported by the root layout, which sets data-site="wnba"', () => {
    const layout = fs.readFileSync(path.resolve(import.meta.dirname, '../../app/layout.tsx'), 'utf8');
    expect(layout).toMatch(/import '\.\/design-tokens\.css'/);
    expect(layout).toMatch(/data-site="wnba"/);
  });
});
