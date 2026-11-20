import type { Config } from 'tailwindcss';

/** A Tailwind color backed by a design token, with opacity-modifier support. */
const token = (name: string) =>
  `color-mix(in srgb, var(${name}) calc(<alpha-value> * 100%), transparent)`;

const config: Config = {
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
        background: 'var(--background)',
        foreground: 'var(--foreground)',
        accent: {
          50: '#ecfdf5',
          400: '#34d399',
          500: '#10b981',
          600: '#059669',
          700: '#047857',
          900: '#064e3b',
          950: '#022c22',
        },
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
