/**
 * WCAG 2.x contrast-ratio helpers (relative luminance + contrast ratio), plus a small
 * search routine that lightens a color just enough to clear a target contrast ratio
 * against one or more background surfaces.
 *
 * Used by `lib/teams.ts` (#133) to derive each team's `onDark` text/stroke color: the raw
 * team primaries are tuned for logos/swatches on light chrome and 28/32 of them fail
 * 4.5:1 against this app's dark surfaces (`#04140f`, `#0a2018`) when used as text.
 */

export interface RGB {
  r: number;
  g: number;
  b: number;
}

export function hexToRgb(hex: string): RGB {
  const clean = hex.replace('#', '');
  const full = clean.length === 3 ? clean.split('').map((c) => c + c).join('') : clean;
  const num = parseInt(full, 16);
  return {
    r: (num >> 16) & 255,
    g: (num >> 8) & 255,
    b: num & 255,
  };
}

export function rgbToHex({ r, g, b }: RGB): string {
  const toHex = (n: number) => Math.round(Math.min(255, Math.max(0, n))).toString(16).padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`.toUpperCase();
}

// WCAG relative luminance: https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
function channelToLinear(c: number): number {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

export function relativeLuminance(rgb: RGB): number {
  const r = channelToLinear(rgb.r);
  const g = channelToLinear(rgb.g);
  const b = channelToLinear(rgb.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio between two colors, in [1, 21]. */
export function contrastRatio(hexA: string, hexB: string): number {
  const lA = relativeLuminance(hexToRgb(hexA));
  const lB = relativeLuminance(hexToRgb(hexB));
  const lighter = Math.max(lA, lB);
  const darker = Math.min(lA, lB);
  return (lighter + 0.05) / (darker + 0.05);
}

/** Mix `hex` toward white by `amount` (0 = unchanged, 1 = pure white). */
function lightenHex(hex: string, amount: number): string {
  const { r, g, b } = hexToRgb(hex);
  return rgbToHex({
    r: r + (255 - r) * amount,
    g: g + (255 - g) * amount,
    b: b + (255 - b) * amount,
  });
}

/**
 * Lighten `hex` toward white just enough that its contrast ratio against every color in
 * `backgrounds` is >= `minRatio`. Walks amount from 0 to 1 in fixed steps (plenty of
 * precision for a one-time derivation over 32 teams, and deterministic/dependency-free).
 * Falls back to white if even full lightening can't clear the ratio (never happens for any
 * real team primary against these dark surfaces, but keeps the function total).
 */
export function findOnDarkColor(hex: string, backgrounds: string[], minRatio = 4.5): string {
  const meetsAll = (candidate: string) => backgrounds.every((bg) => contrastRatio(candidate, bg) >= minRatio);

  if (meetsAll(hex)) return hex.toUpperCase();

  const steps = 200;
  for (let i = 1; i <= steps; i++) {
    const candidate = lightenHex(hex, i / steps);
    if (meetsAll(candidate)) return candidate;
  }
  return '#FFFFFF';
}
