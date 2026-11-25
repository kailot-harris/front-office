/**
 * The route table every end-to-end spec iterates.
 *
 * Kept in one place so adding a page to `app/` means adding one row here and
 * the smoke, accessibility and asset specs all pick it up. A page under `app/`
 * with no row here (or in MOVED_ROUTES) fails route-coverage.test.tsx (#82).
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
  /**
   * The elements the search filters, when they are not table rows or cards
   * (interactions.spec.ts counts `tbody tr, [class*="rounded-xl"]` by default).
   */
  resultRows?: string;
  /**
   * A sub-page reached from its parent page rather than from the sidebar
   * (#226: the Momentum Board links its methodology page). The sidebar checks
   * skip it; it must still be linked from `linkedFrom`.
   */
  linkedFrom?: string;
}

export const ROUTES: RouteSpec[] = [
  {
    path: '/',
    title: 'Season Projections & Standings',
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
    path: '/momentum',
    title: 'Momentum Board',
    heading: 'Momentum Board',
    dataMarkers: ['How this is calculated', 'Games in window'],
    expectsSearch: false,
  },
  {
    path: '/momentum/methodology',
    title: 'Momentum Board Methodology',
    heading: 'Momentum Board methodology',
    // Section headings rendered around data read from momentum_methodology.json.
    dataMarkers: ['Why flags carry no badge', 'Everything the measures study tried'],
    expectsSearch: false,
    linkedFrom: '/momentum',
  },
  {
    path: '/teams',
    title: 'Team Power Ratings',
    heading: 'Team Ratings',
    dataMarkers: ['Net EPA/Play', 'Explosive %'],
    expectsSearch: true,
  },
  {
    path: '/coaches',
    title: 'Coaching Staffs',
    heading: 'Head Coach Decision Profiles',
    dataMarkers: ['4th-Down Go Rate', 'PROE'],
    expectsSearch: true,
  },
  {
    path: '/cap-sheet',
    title: 'Payroll & Cap',
    heading: 'Positional Cap Allocation',
    dataMarkers: ['Cap Ceiling', 'Top 100 League Contracts'],
    expectsSearch: true,
  },
  {
    path: '/playoffs',
    title: 'NFL Playoff Simulator',
    heading: 'Playoff Simulator',
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
    path: '/passing',
    title: 'QB Passing Charts & Throw Maps',
    heading: 'QB Passing Charts & Throw Maps',
    dataMarkers: ['NextGenStats Throw Canvas', 'EPA / Pass'],
    expectsSearch: true,
    resultRows: 'select[aria-label="Select quarterback"] option',
  },
  {
    path: '/player-dna',
    title: 'Player DNA & Peer Comps',
    heading: 'Player DNA & Peer Comps',
    dataMarkers: ['Qualified players', 'Empirical Skill Profiles'],
    expectsSearch: true,
    resultRows: 'div.divide-y > button',
  },
  {
    path: '/clutch',
    title: 'True Clutch Index & Leverage',
    heading: 'True Clutch Index & Pressure Resilience',
    dataMarkers: ['High-Leverage Leaderboard', 'Clutch EPA vs Baseline'],
    expectsSearch: true,
  },
  {
    path: '/variants',
    title: 'Model Variants',
    heading: 'Multi-Model Architecture',
    dataMarkers: ['Ridge', 'Elo', 'Production Ensemble'],
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

/**
 * #211: renamed pages that keep their old address as a forwarding stub
 * (redirects.spec.ts). Every app/<route>/page.tsx must be in ROUTES or here; the
 * coverage test in tests/components/route-coverage.test.tsx fails otherwise (#82).
 */
export const MOVED_ROUTES: ReadonlyArray<readonly [from: string, to: string]> = [
  ['/dna', '/player-dna'],
  ['/coaching', '/coaches'],
  ['/salary-cap', '/cap-sheet'],
];

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

/** Routes linked from their parent page instead of the sidebar (RouteSpec.linkedFrom). */
export const LINKED_ROUTES = ROUTES.filter((r) => r.linkedFrom !== undefined);

/** Routes the sidebar must link to: every route except LINKED_ROUTES. */
export const SIDEBAR_ROUTE_HREFS = ROUTES.filter((r) => r.linkedFrom === undefined).map((r) => linkHref(r.path));

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
