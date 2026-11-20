import type { Config } from "tailwindcss";
import plugin from "tailwindcss/plugin";
import { themedColors, themedVariables } from "./lib/themePalette";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        // Resolve through the shared tokens (app/design-tokens.css), which put
        // the geist package's --font-geist-* variables first.
        sans: ["var(--fo-font-sans)"],
        mono: ["var(--fo-font-mono)"],
      },
      colors: {
        background: "var(--background)",
        foreground: "var(--foreground)",
        // Palettes flip with prefers-color-scheme; see lib/themePalette.ts.
        ...themedColors(),
        // Shared --fo-* tokens (app/design-tokens.css, data-site="nba").
        // color-mix keeps Tailwind's /opacity modifiers working on CSS variables.
        surface: "color-mix(in srgb, var(--fo-surface) calc(<alpha-value> * 100%), transparent)",
        "surface-raised": "color-mix(in srgb, var(--fo-surface-raised) calc(<alpha-value> * 100%), transparent)",
        fo: {
          text: "var(--fo-text)",
          muted: "var(--fo-text-muted)",
          border: "var(--fo-border)",
          accent: "var(--fo-accent)",
          "on-accent": "var(--fo-on-accent)",
          success: "var(--fo-success)",
          warning: "var(--fo-warning)",
          danger: "var(--fo-danger)",
        },
      },
    },
  },
  plugins: [plugin(({ addBase }) => addBase(themedVariables()))],
};
export default config;
