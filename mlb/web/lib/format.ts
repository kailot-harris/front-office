/**
 * Shared number/money formatting helpers.
 *
 * Published JSON is written by the R pipeline, which serializes R's `NA` as
 * JSON `null`. Any component that blindly calls `.toFixed()` on a field that
 * can be `NA` upstream will throw during render and blank the page. These
 * helpers centralize the guard: null, undefined, NaN, and non-finite values
 * (Infinity/-Infinity) all render as an em dash instead of crashing or
 * printing "NaN" / "Infinity" / "undefined".
 */

const EM_DASH = '—';

function isDisplayable(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

/**
 * Format a plain number with a fixed number of decimal places.
 * Returns an em dash for null, undefined, NaN, or non-finite values.
 */
export function num(value: number | null | undefined, decimals = 1): string {
  if (!isDisplayable(value)) return EM_DASH;
  return value.toFixed(decimals);
}

/**
 * Format a dollar amount in millions, e.g. money(244) -> "$244.0M".
 * Returns an em dash for null, undefined, NaN, or non-finite values.
 */
export function money(value: number | null | undefined, decimals = 1): string {
  if (!isDisplayable(value)) return EM_DASH;
  return `$${value.toFixed(decimals)}M`;
}
