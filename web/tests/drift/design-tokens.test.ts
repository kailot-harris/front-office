import { describe, it, expect } from 'vitest';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

// app/design-tokens.css is a byte-for-byte copy of the canonical
// front-office-aggregator/assets/design-tokens.css (front-office#201).
// Do not edit it here: change the canonical file, then recopy it and update this hash.
const CANONICAL_SHA256 = 'd91f4b884ecb3148a5902f26213c1c209d54107544d9d6340fb63b1db68c0e58';

describe('shared design tokens', () => {
  it('app/design-tokens.css matches the canonical sha256', () => {
    const file = path.resolve(import.meta.dirname, '..', '..', 'app', 'design-tokens.css');
    const sha = createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    expect(sha).toBe(CANONICAL_SHA256);
  });

  it('globals.css imports the tokens', () => {
    const css = fs.readFileSync(path.resolve(import.meta.dirname, '..', '..', 'app', 'globals.css'), 'utf8');
    expect(css).toMatch(/@import ['"]\.\/design-tokens\.css['"]/);
  });
});
