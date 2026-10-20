// Mirrors next.config.mjs's basePath computation: this app is published as part of the
// combined front-office site at <user>.github.io/front-office/nfl/, not domain root, so any
// asset referenced by a hardcoded "/..." string (manual <img src>, fetch()) needs this prefix
// or it 404s in production. next.config.mjs can't be imported by client/server app code, so the
// same `PAGES_BASE_PATH + '/nfl'` logic is duplicated here rather than shared.
const repoBase = process.env.PAGES_BASE_PATH ?? '';
export const BASE_PATH = `${repoBase}/nfl`;
