import { describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';

/**
 * app/design-tokens.css is a byte-for-byte copy of the canonical
 * front-office-aggregator/assets/design-tokens.css (front-office#201).
 * Never edit it here: change the canonical file, then copy it to every sport
 * and update this hash. Pinned to LF in .gitattributes so checkout on Windows
 * cannot change the bytes.
 */
const CANONICAL_SHA256 = 'd91f4b884ecb3148a5902f26213c1c209d54107544d9d6340fb63b1db68c0e58';

describe('shared design tokens', () => {
  it('app/design-tokens.css matches the canonical sha256', () => {
    const bytes = readFileSync(path.resolve(__dirname, '../../app/design-tokens.css'));
    expect(createHash('sha256').update(bytes).digest('hex')).toBe(CANONICAL_SHA256);
  });
});
