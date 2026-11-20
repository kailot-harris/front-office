import type { Config } from "tailwindcss";
import defaultColors from "tailwindcss/colors";
import plugin from "tailwindcss/plugin";

/**
 * Colors follow the shared front-office tokens (web/app/design-tokens.css,
 * front-office#201) and the visitor's prefers-color-scheme (WNBA#229).
 *
 * - `surface`, `surface-raised` and `fo-*` read the --fo-* tokens directly, so
 *   the Violet Nebula palette (COLORWAY_IMPLEMENTATION_PLAN.md section 1)
 *   comes from one place and flips with the color scheme.
 * - Every Tailwind palette class (slate, amber, emerald, ...) and `white` read
 *   a CSS variable. Dark mode keeps Tailwind's own values, which is what this
 *   site was designed against. Light mode mirrors each scale (50<->950,
 *   100<->900, ... 400<->600) and swaps white for the token text color, so
 *   `text-slate-100` on `bg-surface` stays high-contrast in both modes without
 *   a `dark:` variant on every element.
 */
const MIRRORED = [
  "slate", "gray", "zinc", "neutral", "stone", "red", "orange", "amber",
  "yellow", "lime", "green", "emerald", "teal", "cyan", "sky", "blue",
  "indigo", "violet", "purple", "fuchsia", "pink", "rose",
] as const;
const SHADES = ["50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950"] as const;
const mirror = (s: string) => (s === "50" ? "950" : s === "950" ? "50" : String(1000 - Number(s)));

const channels = (hex: string) => {
  const h = hex.replace("#", "");
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)).join(" ");
};
const palette = defaultColors as unknown as Record<string, Record<string, string>>;

const lightVars: Record<string, string> = { "--c-white": "15 23 42" };
const darkVars: Record<string, string> = { "--c-white": "255 255 255" };
const colors: Record<string, Record<string, string>> = {};
for (const name of MIRRORED) {
  colors[name] = {};
  for (const s of SHADES) {
    lightVars[`--c-${name}-${s}`] = channels(palette[name][mirror(s)]);
    darkVars[`--c-${name}-${s}`] = channels(palette[name][s]);
    colors[name][s] = `rgb(var(--c-${name}-${s}) / <alpha-value>)`;
  }
}

/** A --fo-* token as a Tailwind color that still honours `/50` opacity modifiers. */
const token = (v: string): string =>
  (({ opacityValue }: { opacityValue?: string }) =>
    opacityValue === undefined || opacityValue === "1"
      ? `var(${v})`
      : `color-mix(in srgb, var(${v}) calc(${opacityValue} * 100%), transparent)`) as unknown as string;

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ["var(--font-geist-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-geist-mono)", "ui-monospace", "monospace"],
      },
      colors: {
        ...colors,
        white: "rgb(var(--c-white) / <alpha-value>)",
        background: token("--fo-surface"),
        foreground: token("--fo-text"),
        // The site accent is Tailwind's violet scale (identical hex values).
        accent: { ...colors.violet, DEFAULT: token("--fo-accent") as unknown as string },
        surface: token("--fo-surface"),
        "surface-raised": token("--fo-surface-raised"),
        fo: {
          text: token("--fo-text"),
          muted: token("--fo-text-muted"),
          border: token("--fo-border"),
          accent: token("--fo-accent"),
          "on-accent": token("--fo-on-accent"),
        },
      },
    },
  },
  plugins: [
    plugin(({ addBase }) => {
      addBase({
        ":root": lightVars,
        "@media (prefers-color-scheme: dark)": { ":root": darkVars },
      });
    }),
  ],
};
export default config;
