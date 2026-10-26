/**
 * The route table every end-to-end spec iterates.
 *
 * Kept in one place so adding a page to `app/` means adding one row here and
 * the smoke, accessibility and asset specs all pick it up.
 *
 * `title` and `heading` were read off a real `next start` build rather than
 * copied from the source, so they double as a record of the live page copy.
 */
export interface RouteSpec {
  path: string;
  /** Substring expected in <title>. */
  title: string;
  /** Substring expected in the page's first <h1>. */
  heading: string;
  /** Text that proves the page's primary data actually rendered. */
  dataMarkers: string[];
  /** Whether the page exposes a text filter input. */
  expectsSearch: boolean;
}

export const ROUTES: RouteSpec[] = [
  {
    path: '/',
    title: 'NFL Analytics',
    heading: 'NFL Season Projections',
    dataMarkers: ['Super Bowl Favorite', 'Power Rating'],
    expectsSearch: true,
  },
  {
    path: '/matchups',
    title: 'Weekly NFL Matchups',
    heading: 'Weekly Matchup Projections',
    dataMarkers: ['Select Slate', 'Model Win Probability'],
    expectsSearch: true,
  },
  {
    path: '/teams',
    title: 'Team Power Ratings',
    heading: 'Team Ratings',
    dataMarkers: ['Net EPA/Play', 'Explosive %'],
    expectsSearch: true,
  },
  {
    path: '/coaching',
    title: 'Coaching Analysis',
    heading: 'Head Coach Decision Profiles',
    dataMarkers: ['4th-Down Aggression', 'PROE'],
    expectsSearch: true,
  },
  {
    path: '/salary-cap',
    title: 'Salary Cap',
    heading: 'Positional Cap Allocation',
    dataMarkers: ['Cap Ceiling', 'Top 100 League Contracts'],
    expectsSearch: true,
  },
  {
    path: '/playoffs',
    title: 'NFL Playoff Machine',
    heading: 'Playoff Machine',
    dataMarkers: ['AFC', 'NFC'],
    expectsSearch: false,
  },
  {
    path: '/players',
    title: 'Quarterback & Player Analytics',
    heading: 'Quarterback Composite Ratings',
    dataMarkers: ['EPA / Play', 'CPOE'],
    expectsSearch: true,
  },
  {
    path: '/variants',
    title: 'Model Variants',
    heading: 'Multi-Model Architecture',
    dataMarkers: ['Ridge', 'Elo', 'Market'],
    expectsSearch: false,
  },
  {
    path: '/diagnostics',
    title: 'Model Diagnostics',
    heading: 'Model Calibration',
    dataMarkers: ['Brier', 'Calibration'],
    expectsSearch: false,
  },
  {
    path: '/gallery',
    title: 'Visual Media Gallery',
    heading: 'Automated Visualizations',
    dataMarkers: ['All Visuals'],
    expectsSearch: true,
  },
];

export const ROUTE_PATHS = ROUTES.map((r) => r.path);

/** Console messages that are environmental noise rather than app defects. */
export const IGNORED_CONSOLE_PATTERNS: RegExp[] = [
  /Download the React DevTools/i,
  /\[Fast Refresh\]/i,
  /favicon\.ico/i,
];

export function isRealConsoleError(text: string): boolean {
  return !IGNORED_CONSOLE_PATTERNS.some((p) => p.test(text));
}

/**
 * The basePath the app is built with (next.config.mjs sets `basePath: '/nfl'`,
 * prefixed by PAGES_BASE_PATH when the combined site is published).
 *
 * Specs navigate to bare paths — `page.goto('/teams')` — and the managed server
 * in scripts/serve-export.mjs redirects those under the basePath. But anything
 * that reads a URL BACK out of the page (an href, the address bar) sees the
 * prefixed, trailing-slashed form that Next actually emits: `/nfl/teams/`, not
 * `/teams`. Use linkHref() whenever a route path is compared against the DOM.
 */
export const BASE_PATH = `${process.env.PAGES_BASE_PATH ?? ''}/nfl`;

/** The href Next renders for a route path: basePath-prefixed and trailing-slashed. */
export function linkHref(path: string): string {
  return path === '/' ? `${BASE_PATH}/` : `${BASE_PATH}${path}/`;
}

export const ROUTE_HREFS = ROUTE_PATHS.map(linkHref);

/**
 * Requests that fail for reasons that are not app defects.
 *
 * Next's client router speculatively prefetches the RSC payload (`?_rsc=`) for
 * every visible link, then cancels the ones it no longer needs — on navigation,
 * or when the page is torn down at the end of a test. Those cancellations
 * surface as net::ERR_ABORTED on a URL the server answered 200 for, and which
 * route they land on varies run to run. Treating them as failures made the
 * same specs flaky on different pages each run.
 */
export function isRealRequestFailure(url: string, failureText: string): boolean {
  return !(url.includes('_rsc=') && /ERR_ABORTED/.test(failureText));
}
