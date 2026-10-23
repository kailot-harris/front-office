export interface RouteSpec {
  path: string;
  title: string;
  heading: string;
  dataMarkers: string[];
  expectsSearch: boolean;
}

export const ROUTES: RouteSpec[] = [
  {
    path: '/',
    title: 'NBA Season Projections',
    heading: 'NBA Season Projections',
    dataMarkers: ['1,000-season Monte Carlo simulation', 'Total Simulated Games'],
    expectsSearch: false,
  },
  {
    path: '/offseason',
    title: 'Offseason Moves',
    heading: 'Offseason Moves',
    dataMarkers: ['Transaction Ledger', 'Franchise Winners'],
    expectsSearch: true,
  },
  {
    path: '/cap-sheet',
    title: 'CBA Cap Sheet',
    heading: 'CBA Salary Cap, Apron & Luxury Tax Architect',
    dataMarkers: ['Apron Thermometer', 'Second Apron'],
    expectsSearch: false,
  },
  {
    path: '/variants',
    title: 'Model Variants Breakout',
    heading: 'Model Variants Breakout',
    dataMarkers: ['Production Bottom-Up BPM', 'Possession-Level RAPM'],
    expectsSearch: false,
  },
  {
    path: '/players',
    title: 'Player Projections',
    heading: 'Player Projections & Outliers',
    dataMarkers: ['Active Rotation Pool', 'Statistical Outliers'],
    expectsSearch: true,
  },
  {
    path: '/player-dna',
    title: 'Player DNA',
    heading: 'Player DNA',
    dataMarkers: ['16-D Manifold Embedding', 'Nearest Historical Comparables'],
    expectsSearch: true,
  },
  {
    path: '/defense',
    title: 'Defensive Versatility',
    heading: 'Defensive Versatility',
    dataMarkers: ['Positional Versatility', 'Rim Protection Architecture'],
    expectsSearch: true,
  },
  {
    path: '/clutch',
    title: 'True Clutch',
    heading: 'Late-Game Shot Creation',
    dataMarkers: ['True Clutch & Leverage Creation Index', 'Late-Game Shot Creation'],
    expectsSearch: true,
  },
  {
    path: '/shots',
    title: 'Player Shot Charts',
    heading: 'Player Shot Charts & Hot Zones',
    dataMarkers: ['Empirical Bayes shrinkage', 'Select Player Telemetry'],
    expectsSearch: true,
  },
  {
    path: '/coaches',
    title: 'Coaching Staffs',
    heading: 'Coaching Staffs',
    dataMarkers: ['ATO Tactical Matrix', 'Coach Impact Rating'],
    expectsSearch: false,
  },
  {
    path: '/matchups',
    title: 'Matchups: Weekly Slates',
    heading: 'Matchup Slates',
    // Both markers are page-specific on purpose. The site nav renders every
    // page's label on every page, so "Matchup Slates" alone would pass from any
    // route and prove nothing; the ribbon's ratings_source string comes from
    // matchups_slates.json itself, so it only appears once the dataset renders.
    dataMarkers: ['Projection basis:', 'Primary 4-Model Ensemble Blend'],
    expectsSearch: true,
  },
  {
    path: '/series',
    title: '7-Game Playoff Series',
    heading: '7-Game Playoff Series Matchup Simulator',
    dataMarkers: ['10,000-sim Monte Carlo engine', '8-man playoff rotation'],
    expectsSearch: false,
  },
  {
    path: '/diagnostics',
    title: 'Modeling Analysis & Diagnostics',
    heading: 'Modeling Analysis & Diagnostics',
    dataMarkers: ['Empirical reliability curves', 'Brier score'],
    expectsSearch: false,
  },
];

export const ROUTE_PATHS = ROUTES.map((r) => r.path);

export const IGNORED_CONSOLE_PATTERNS: RegExp[] = [
  /Download the React DevTools/i,
  /\[Fast Refresh\]/i,
  /favicon\.ico/i,
];

export function isRealConsoleError(text: string): boolean {
  return !IGNORED_CONSOLE_PATTERNS.some((p) => p.test(text));
}

/**
 * Next's client router speculatively prefetches the RSC payload (`?_rsc=`) of
 * every link on the page, then cancels the ones it decides it no longer needs.
 * Chrome reports each cancellation as a failed request with net::ERR_ABORTED,
 * which it is not — the router is working as designed and the target page still
 * loads. A dozen of these fire on pages carrying the full site nav.
 *
 * Narrow on purpose: only an abort, and only on a URL carrying the `_rsc`
 * marker. A prefetch that actually 404s arrives through the `response` handler
 * as a 4xx and still fails the test, which is the case that would mean a route
 * is missing from the export.
 */
export function isSpeculativePrefetchAbort(url: string, errorText?: string): boolean {
  return /[?&]_rsc=/.test(url) && (errorText ?? '').includes('net::ERR_ABORTED');
}
