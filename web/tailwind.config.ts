import type { Config } from 'tailwindcss';

/** A Tailwind color backed by a design token, with opacity-modifier support. */
const token = (name: string) =>
  `color-mix(in srgb, var(${name}) calc(<alpha-value> * 100%), transparent)`;

/** Palette shades backed by app/palette.css, which swaps them for light mode. */
const PALETTES = ['slate', 'emerald', 'amber', 'cyan', 'rose', 'red', 'blue', 'indigo', 'purple', 'teal', 'sky', 'orange', 'green', 'yellow'];
const SHADES = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950];
const channel = (name: string) => `rgb(var(--c-${name}) / <alpha-value>)`;
const schemePalettes = Object.fromEntries(
  PALETTES.map((p) => [p, Object.fromEntries(SHADES.map((s) => [s, channel(`${p}-${s}`)]))]),
);

const config: Config = {
  // Dark and light follow prefers-color-scheme; there is no manual switch.
  darkMode: 'media',
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['var(--font-geist-sans)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-geist-mono)', 'ui-monospace', 'monospace'],
      },
      colors: {
        ...schemePalettes,
        white: channel('white'),
        black: channel('black'),
        background: 'var(--background)',
        foreground: 'var(--foreground)',
        accent: Object.fromEntries([50, 400, 500, 600, 700, 900, 950].map((s) => [s, channel(`accent-${s}`)])),
        // Mapped to the shared --fo-* tokens (design-tokens.css, data-site="nfl").
        // color-mix keeps Tailwind's opacity modifiers (bg-surface-raised/50) working.
        surface: token('--fo-surface'),
        'surface-raised': token('--fo-surface-raised'),
        'fo-text': token('--fo-text'),
        'fo-muted': token('--fo-text-muted'),
        'fo-accent': token('--fo-accent'),
        'on-accent': token('--fo-on-accent'),
      },
    },
  },
  plugins: [],
};
export default config;
