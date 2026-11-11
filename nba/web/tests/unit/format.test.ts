import { describe, expect, it } from 'vitest';
import { money, num, MISSING_VALUE } from '@/lib/format';

/**
 * #113: cap-sheet figures were formatted with `value.toFixed()` directly.
 * R writes NA as JSON null, and null/undefined/NaN/non-finite values reaching
 * `.toFixed()` throw during render, blanking the page. money()/num() must
 * return an em dash for any such value instead of throwing or inventing a
 * fallback number.
 */
describe('lib/format.ts', () => {
  const invalid = [null, undefined, NaN, Infinity, -Infinity, 'not-a-number', {}, []];

  for (const value of invalid) {
    it(`num() returns an em dash for ${JSON.stringify(value)}`, () => {
      expect(num(value)).toBe(MISSING_VALUE);
    });

    it(`money() returns an em dash for ${JSON.stringify(value)}`, () => {
      expect(money(value)).toBe(MISSING_VALUE);
    });
  }

  it('num() formats a finite number with fixed decimals', () => {
    expect(num(48.456, 1)).toBe('48.5');
    expect(num(10, 0)).toBe('10');
  });

  it('money() formats a finite number as a dollar figure in millions', () => {
    expect(money(48.456)).toBe('$48.5M');
    expect(money(0)).toBe('$0.0M');
  });
});
