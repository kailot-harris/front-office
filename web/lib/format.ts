/**
 * Null-safe number formatting helpers.
 *
 * Published JSON from the R pipeline writes `NA` as JSON `null`. Calling
 * `.toFixed()` directly on a value that may be null/undefined/NaN throws
 * during render and blanks the whole page. These helpers never invent a
 * fallback number — they render an em dash ("—") when the value isn't a
 * finite number.
 */

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

/** Formats a plain number, or "—" if null/undefined/NaN/non-finite. */
export function num(value: number | null | undefined, digits = 1): string {
  if (!isFiniteNumber(value)) return '—';
  return value.toFixed(digits);
}

/** Formats a dollar (millions) figure as "$X.XM", or "—" if not a finite number. */
export function money(value: number | null | undefined, digits = 1): string {
  if (!isFiniteNumber(value)) return '—';
  return `$${value.toFixed(digits)}M`;
}

/**
 * Formats a 0-1 probability fraction as a percentage string ("X.X%"), or
 * "—" if not a finite number. Does not assume 0 for missing data.
 */
export function percent(value: number | null | undefined, digits = 0): string {
  if (!isFiniteNumber(value)) return '—';
  return `${(value * 100).toFixed(digits)}%`;
}

/**
 * Requests a smaller size variant from NFL.com's Cloudinary-backed headshot
 * CDN (`static.www.nfl.com/image/upload/f_auto,q_auto/...`) by inserting a
 * width/height/crop transform, so thumbnail-sized headshots don't transfer
 * full-resolution images. Falls back to the original URL for any host that
 * doesn't match this known pattern.
 */
export function headshotSrc(url: string | null | undefined, size: number): string {
  if (!url) return '';
  const cloudinaryUpload = '/image/upload/';
  const idx = url.indexOf(cloudinaryUpload);
  if (url.includes('static.www.nfl.com') && idx !== -1) {
    const insertAt = idx + cloudinaryUpload.length;
    return `${url.slice(0, insertAt)}w_${size},h_${size},c_fill,${url.slice(insertAt)}`;
  }
  return url;
}
