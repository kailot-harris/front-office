/**
 * Shared design tokens (kailot-harris/front-office#201).
 *
 * app/design-tokens.css is a byte-for-byte copy of the aggregator's canonical
 * assets/design-tokens.css. Never edit it here: change the canonical file,
 * regenerate its sha256, and copy it to every sport. .gitattributes pins it to
 * LF so a Windows checkout cannot change the bytes.
 */
import { describe, expect, it } from 'vitest';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const CANONICAL_SHA256 = 'd91f4b884ecb3148a5902f26213c1c209d54107544d9d6340fb63b1db68c0e58';
const WEB_ROOT = path.resolve(import.meta.dirname, '..', '..');

describe('shared design tokens', () => {
  it('app/design-tokens.css matches the canonical sha256', () => {
    const bytes = fs.readFileSync(path.join(WEB_ROOT, 'app', 'design-tokens.css'));
    expect(crypto.createHash('sha256').update(bytes).digest('hex')).toBe(CANONICAL_SHA256);
  });

  it('is imported by the root layout, which sets data-site="nfl"', () => {
    const layout = fs.readFileSync(path.join(WEB_ROOT, 'app', 'layout.tsx'), 'utf-8');
    expect(layout).toMatch(/import ['"]\.\/design-tokens\.css['"]/);
    expect(layout).toContain('data-site="nfl"');
  });
});
