import defaultColors from 'tailwindcss/colors';

/**
 * Automatic light/dark palettes (NBA_analytics#215).
 *
 * The site was written dark-first: text-slate-100 on bg-surface, borders in
 * slate-800, accents in the -400 shades. Rather than doubling every class with
 * a `dark:` variant, each palette the site uses is a set of CSS variables.
 * Dark mode (prefers-color-scheme: dark) gets Tailwind's real values, so the
 * existing dark design is unchanged and stays the reference. Light mode gets
 * the mirrored shade (slate-100 text becomes slate-900, a slate-800 border
 * becomes slate-200, emerald-400 text becomes emerald-700), which keeps every
 * text pairing at WCAG AA on the light --fo-surface tokens.
 */
export const THEMED_PALETTES = [
  'slate', 'zinc', 'gray', 'neutral', 'emerald', 'green', 'amber', 'yellow', 'indigo',
  'rose', 'red', 'sky', 'cyan', 'blue', 'orange', 'violet', 'purple', 'teal', 'lime', 'pink', 'fuchsia',
] as const;

const SHADES = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950] as const;
type Shade = (typeof SHADES)[number];

/** Light-mode shade used in place of each dark-mode shade. Text shades land on 700+ for AA on light surfaces. */
const LIGHT_SHADE: Record<Shade, Shade> = {
  50: 950, 100: 900, 200: 800, 300: 800, 400: 700, 500: 700,
  600: 300, 700: 200, 800: 200, 900: 100, 950: 50,
};

function channels(hex: string): string {
  const h = hex.replace('#', '');
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)).join(' ');
}

type PaletteName = (typeof THEMED_PALETTES)[number] | 'accent';
const source = (name: PaletteName) =>
  (defaultColors as unknown as Record<string, Record<Shade, string>>)[name === 'accent' ? 'indigo' : name];

/** Tailwind color config: every shade reads its CSS variable, keeping /opacity modifiers. */
export function themedColors(): Record<string, Record<string, string>> {
  const out: Record<string, Record<string, string>> = {};
  for (const name of [...THEMED_PALETTES, 'accent'] as PaletteName[]) {
    out[name] = {};
    for (const s of SHADES) out[name][s] = `rgb(var(--c-${name}-${s}) / <alpha-value>)`;
  }
  out.accent.DEFAULT = 'var(--fo-accent)';
  out.white = { DEFAULT: 'rgb(var(--c-white) / <alpha-value>)' } as Record<string, string>;
  return out;
}

/** CSS variables for both schemes (light default, dark under the media query). */
export function themedVariables() {
  const light: Record<string, string> = { '--c-white': channels('#0f172a') };
  const dark: Record<string, string> = { '--c-white': channels('#ffffff') };
  for (const name of [...THEMED_PALETTES, 'accent'] as PaletteName[]) {
    const pal = source(name);
    for (const s of SHADES) {
      dark[`--c-${name}-${s}`] = channels(pal[s]);
      light[`--c-${name}-${s}`] = channels(pal[LIGHT_SHADE[s]]);
    }
  }
  return { ':root': light, '@media (prefers-color-scheme: dark)': { ':root': dark } };
}
