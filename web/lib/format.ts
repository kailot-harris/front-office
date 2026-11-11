// ==============================================================================
// format.ts
// Shared number-formatting helpers that never crash the render.
//
// #113: Cap-sheet figures were rendered with `value.toFixed()` directly. R
// writes `NA` as JSON `null`, and any null/undefined/NaN/non-finite value
// reaching `.toFixed()` throws during render and blanks the whole page. These
// helpers return an em dash for anything that is not a finite number instead
// of inventing a fallback number.
// ==============================================================================

const isFiniteNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value);

/** Em dash shown in place of a missing/invalid figure. */
export const MISSING_VALUE = '—';

/**
 * Formats a plain number with fixed decimals, or an em dash when the value
 * is null, undefined, NaN, or otherwise not a finite number.
 */
export function num(value: unknown, decimals = 1): string {
  if (!isFiniteNumber(value)) return MISSING_VALUE;
  return value.toFixed(decimals);
}

/**
 * Formats a dollar figure in millions (e.g. "$48.5M"), or an em dash when the
 * value is null, undefined, NaN, or otherwise not a finite number.
 */
export function money(value: unknown, decimals = 1): string {
  if (!isFiniteNumber(value)) return MISSING_VALUE;
  return `$${value.toFixed(decimals)}M`;
}
