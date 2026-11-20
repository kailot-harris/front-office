import type { Config } from "tailwindcss";

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
        accent: {
          DEFAULT: "var(--fo-accent)",
          50: "#eef2ff",
          400: "#818cf8",
          500: "#6366f1",
          600: "#4f46e5",
          700: "#4338ca",
          900: "#312e81",
          950: "#1e1b4b",
        },
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
  plugins: [],
};
export default config;
