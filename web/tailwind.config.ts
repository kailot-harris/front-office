import type { Config } from "tailwindcss";
import plugin from "tailwindcss/plugin";
import twColors from "tailwindcss/colors";

/*
 * Colour system (kailot-harris/MLB-Analytics#128, #129).
 *
 * The shared tokens in app/design-tokens.css (--fo-*) drive the shell: surface,
 * surface-raised, text, border and the accent. Light and dark follow the
 * visitor's prefers-color-scheme; there is no manual switch and no `dark` class.
 *
 * The app was written dark-first against Tailwind's palettes (text-slate-400,
 * bg-sky-500/10, ...). Rather than rewrite every class, each palette used here
 * is served through CSS variables: dark mode keeps Tailwind's stock values,
 * light mode swaps each shade for its mirror (a light text shade becomes a dark
 * one, a dark panel shade becomes a pale one), so the same class stays readable
 * on both the dark and the light surface.
 */
const PALETTES = [
  "slate", "sky", "amber", "indigo", "rose", "emerald", "red", "purple",
  "cyan", "yellow", "violet", "fuchsia", "teal",
] as const;
const SHADES = ["50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950"] as const;
type Shade = (typeof SHADES)[number];

/** Light-mode stand-in for each dark-first shade. */
const LIGHT_MIRROR: Record<Shade, Shade> = {
  "50": "950", "100": "900", "200": "900", "300": "900", "400": "800",
  "500": "700", "600": "700", "700": "300", "800": "200", "900": "100", "950": "50",
};

const withAlpha = (cssVar: string) =>
  `color-mix(in srgb, var(${cssVar}) calc(<alpha-value> * 100%), transparent)`;

type Palette = Record<Shade, string>;
const stock = twColors as unknown as Record<string, Palette>;

const paletteVars = (name: string, source: Palette) => {
  const light: Record<string, string> = {};
  const dark: Record<string, string> = {};
  for (const s of SHADES) {
    light[`--tw-c-${name}-${s}`] = source[LIGHT_MIRROR[s]];
    dark[`--tw-c-${name}-${s}`] = source[s];
  }
  return { light, dark };
};

const varPalette = (name: string) =>
  Object.fromEntries(SHADES.map((s) => [s, withAlpha(`--tw-c-${name}-${s}`)]));

const colorVariables = plugin(({ addBase }) => {
  const light: Record<string, string> = {};
  const dark: Record<string, string> = {};
  for (const p of PALETTES) {
    const v = paletteVars(p, stock[p]);
    Object.assign(light, v.light);
    Object.assign(dark, v.dark);
  }
  // The accent ramp is MLB's sapphire (Tailwind sky), with 400/500 bound to the token accent.
  // Plain white is "brightest text" in the dark-first markup, so it flips to near-black in light mode.
  light["--tw-c-white"] = stock.slate["950"];
  dark["--tw-c-white"] = "#ffffff";
  const acc = paletteVars("accent", stock.sky);
  Object.assign(light, acc.light);
  Object.assign(dark, acc.dark);
  addBase({
    ":root": light,
    "@media (prefers-color-scheme: dark)": { ":root": dark },
  });
});

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ["var(--fo-font-sans)"],
        mono: ["var(--fo-font-mono)"],
      },
      colors: {
        ...Object.fromEntries(PALETTES.map((p) => [p, varPalette(p)])),
        white: withAlpha("--tw-c-white"),
        background: withAlpha("--fo-surface"),
        foreground: withAlpha("--fo-text"),
        accent: {
          ...varPalette("accent"),
          400: withAlpha("--fo-accent"),
          500: withAlpha("--fo-accent"),
        },
        surface: withAlpha("--fo-surface"),
        "surface-raised": withAlpha("--fo-surface-raised"),
        fo: {
          text: withAlpha("--fo-text"),
          muted: withAlpha("--fo-text-muted"),
          border: withAlpha("--fo-border"),
          accent: withAlpha("--fo-accent"),
          "on-accent": withAlpha("--fo-on-accent"),
        },
      },
    },
  },
  plugins: [colorVariables],
};
export default config;
