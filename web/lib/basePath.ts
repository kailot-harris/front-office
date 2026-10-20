// Mirrors next.config.mjs's basePath: the site is published to GitHub Pages at
// kailot-harris.github.io/front-office/wnba/, not domain root, so any asset referenced by a
// hardcoded "/..." string (manual <img src>, fetch()) needs this prefix or it 404s in production
// while still looking correct in `next dev`, where there's no subpath. `next build` always sets
// NODE_ENV=production, so this and next.config.mjs stay in sync without a separate env var.
export const BASE_PATH = process.env.NODE_ENV === 'production' ? '/front-office/wnba' : '';
