export interface TeamMetadata {
  abbr: string;
  name: string;
  fullName: string;
  espnCode: string;
  colors: {
    primary: string;
    secondary: string;
    accent: string;
    /**
     * #133: a lightened variant of `primary`, computed (not hand-picked) to
     * reach >= 4.5:1 WCAG contrast against both of this app's dark surface
     * tokens (`#0a0920` and `#14123a`). Purely additive -- nothing reads this
     * field yet, and `primary`/`secondary`/`accent` are unchanged and keep
     * being used exactly as before everywhere else. Use this field instead
     * of `primary` the first time a team color is used for text or a thin
     * stroke on this app's dark background.
     */
    onDark: string;
  };
}

type RawTeamMetadata = Omit<TeamMetadata, 'colors'> & {
  colors: Omit<TeamMetadata['colors'], 'onDark'>;
};

const RAW_NBA_TEAMS_METADATA: Record<string, RawTeamMetadata> = {
  ATL: {
    abbr: 'ATL',
    name: 'Hawks',
    fullName: 'Atlanta Hawks',
    espnCode: 'atl',
    colors: { primary: '#E03A3E', secondary: '#C1D32F', accent: '#26282A' },
  },
  BOS: {
    abbr: 'BOS',
    name: 'Celtics',
    fullName: 'Boston Celtics',
    espnCode: 'bos',
    colors: { primary: '#007A33', secondary: '#BA9653', accent: '#000000' },
  },
  BKN: {
    abbr: 'BKN',
    name: 'Nets',
    fullName: 'Brooklyn Nets',
    espnCode: 'bkn',
    colors: { primary: '#000000', secondary: '#FFFFFF', accent: '#707271' },
  },
  CHA: {
    abbr: 'CHA',
    name: 'Hornets',
    fullName: 'Charlotte Hornets',
    espnCode: 'cha',
    colors: { primary: '#1D1160', secondary: '#00788C', accent: '#A1A1A4' },
  },
  CHI: {
    abbr: 'CHI',
    name: 'Bulls',
    fullName: 'Chicago Bulls',
    espnCode: 'chi',
    colors: { primary: '#CE1141', secondary: '#000000', accent: '#FFFFFF' },
  },
  CLE: {
    abbr: 'CLE',
    name: 'Cavaliers',
    fullName: 'Cleveland Cavaliers',
    espnCode: 'cle',
    colors: { primary: '#860038', secondary: '#041E42', accent: '#FDBB30' },
  },
  DAL: {
    abbr: 'DAL',
    name: 'Mavericks',
    fullName: 'Dallas Mavericks',
    espnCode: 'dal',
    colors: { primary: '#00538C', secondary: '#002B5E', accent: '#B8C4CA' },
  },
  DEN: {
    abbr: 'DEN',
    name: 'Nuggets',
    fullName: 'Denver Nuggets',
    espnCode: 'den',
    colors: { primary: '#0E2240', secondary: '#FEC524', accent: '#8B2131' },
  },
  DET: {
    abbr: 'DET',
    name: 'Pistons',
    fullName: 'Detroit Pistons',
    espnCode: 'det',
    colors: { primary: '#C8102E', secondary: '#1D42BA', accent: '#BEC0C2' },
  },
  GSW: {
    abbr: 'GSW',
    name: 'Warriors',
    fullName: 'Golden State Warriors',
    espnCode: 'gsw',
    colors: { primary: '#1D428A', secondary: '#FFC72C', accent: '#000000' },
  },
  HOU: {
    abbr: 'HOU',
    name: 'Rockets',
    fullName: 'Houston Rockets',
    espnCode: 'hou',
    colors: { primary: '#CE1141', secondary: '#000000', accent: '#9EA2A2' },
  },
  IND: {
    abbr: 'IND',
    name: 'Pacers',
    fullName: 'Indiana Pacers',
    espnCode: 'ind',
    colors: { primary: '#002D62', secondary: '#FDBB30', accent: '#BEC0C2' },
  },
  LAC: {
    abbr: 'LAC',
    name: 'Clippers',
    fullName: 'LA Clippers',
    espnCode: 'lac',
    colors: { primary: '#C8102E', secondary: '#1D428A', accent: '#000000' },
  },
  LAL: {
    abbr: 'LAL',
    name: 'Lakers',
    fullName: 'Los Angeles Lakers',
    espnCode: 'lal',
    colors: { primary: '#552583', secondary: '#FDB927', accent: '#000000' },
  },
  MEM: {
    abbr: 'MEM',
    name: 'Grizzlies',
    fullName: 'Memphis Grizzlies',
    espnCode: 'mem',
    colors: { primary: '#5D76A9', secondary: '#12173F', accent: '#F5B112' },
  },
  MIA: {
    abbr: 'MIA',
    name: 'Heat',
    fullName: 'Miami Heat',
    espnCode: 'mia',
    colors: { primary: '#98002E', secondary: '#F9A01B', accent: '#000000' },
  },
  MIL: {
    abbr: 'MIL',
    name: 'Bucks',
    fullName: 'Milwaukee Bucks',
    espnCode: 'mil',
    colors: { primary: '#00471B', secondary: '#EEE1C6', accent: '#0077C0' },
  },
  MIN: {
    abbr: 'MIN',
    name: 'Timberwolves',
    fullName: 'Minnesota Timberwolves',
    espnCode: 'min',
    colors: { primary: '#0C2340', secondary: '#236192', accent: '#78BE20' },
  },
  NOP: {
    abbr: 'NOP',
    name: 'Pelicans',
    fullName: 'New Orleans Pelicans',
    espnCode: 'no',
    colors: { primary: '#0C2340', secondary: '#C8102E', accent: '#85714D' },
  },
  NYK: {
    abbr: 'NYK',
    name: 'Knicks',
    fullName: 'New York Knicks',
    espnCode: 'nyk',
    colors: { primary: '#006BB6', secondary: '#F58426', accent: '#BEC0C2' },
  },
  OKC: {
    abbr: 'OKC',
    name: 'Thunder',
    fullName: 'Oklahoma City Thunder',
    espnCode: 'okc',
    colors: { primary: '#007AC1', secondary: '#EF3B24', accent: '#FDBB30' },
  },
  ORL: {
    abbr: 'ORL',
    name: 'Magic',
    fullName: 'Orlando Magic',
    espnCode: 'orl',
    colors: { primary: '#0077C0', secondary: '#C4CED4', accent: '#000000' },
  },
  PHI: {
    abbr: 'PHI',
    name: '76ers',
    fullName: 'Philadelphia 76ers',
    espnCode: 'phi',
    colors: { primary: '#006BB6', secondary: '#ED174C', accent: '#002B5C' },
  },
  PHX: {
    abbr: 'PHX',
    name: 'Suns',
    fullName: 'Phoenix Suns',
    espnCode: 'phx',
    colors: { primary: '#1D1160', secondary: '#E56020', accent: '#000000' },
  },
  POR: {
    abbr: 'POR',
    name: 'Trail Blazers',
    fullName: 'Portland Trail Blazers',
    espnCode: 'por',
    colors: { primary: '#E03A3E', secondary: '#000000', accent: '#FFFFFF' },
  },
  SAC: {
    abbr: 'SAC',
    name: 'Kings',
    fullName: 'Sacramento Kings',
    espnCode: 'sac',
    colors: { primary: '#5A2D81', secondary: '#63727A', accent: '#000000' },
  },
  SAS: {
    abbr: 'SAS',
    name: 'Spurs',
    fullName: 'San Antonio Spurs',
    espnCode: 'sas',
    colors: { primary: '#C4CED4', secondary: '#000000', accent: '#8A8D8F' },
  },
  TOR: {
    abbr: 'TOR',
    name: 'Raptors',
    fullName: 'Toronto Raptors',
    espnCode: 'tor',
    colors: { primary: '#CE1141', secondary: '#000000', accent: '#A1A1A4' },
  },
  UTA: {
    abbr: 'UTA',
    name: 'Jazz',
    fullName: 'Utah Jazz',
    espnCode: 'utah',
    colors: { primary: '#002B5C', secondary: '#F9A01B', accent: '#00471B' },
  },
  WAS: {
    abbr: 'WAS',
    name: 'Wizards',
    fullName: 'Washington Wizards',
    espnCode: 'was',
    colors: { primary: '#002B5C', secondary: '#E31837', accent: '#C4CED4' },
  },
};

// ------------------------------------------------------------------------------
// #133: derive an `onDark` text/stroke-safe variant of each team's `primary`
// color that reaches >= 4.5:1 WCAG 2.x contrast against both dark surface
// tokens this app uses (`#0a0920` and `#14123a`). Computed via the real
// relative-luminance/contrast-ratio formulas (WCAG 2.x 1.4.3), not guessed,
// so it stays correct if a team's `primary` hex ever changes.
// ------------------------------------------------------------------------------
export const DARK_SURFACE_TOKENS = ['#0a0920', '#14123a'] as const;

const hexToRgb = (hex: string): [number, number, number] => {
  const h = hex.replace('#', '');
  const bigint = parseInt(h, 16);
  return [(bigint >> 16) & 255, (bigint >> 8) & 255, bigint & 255];
};

const rgbToHex = (r: number, g: number, b: number): string => {
  const toHex = (v: number) =>
    Math.round(Math.min(255, Math.max(0, v)))
      .toString(16)
      .padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`.toUpperCase();
};

// WCAG 2.x relative luminance (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance)
const relativeLuminance = (r: number, g: number, b: number): number => {
  const srgb = [r, g, b].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * srgb[0] + 0.7152 * srgb[1] + 0.0722 * srgb[2];
};

// WCAG 2.x contrast ratio (https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio)
export const wcagContrastRatio = (hexA: string, hexB: string): number => {
  const [r1, g1, b1] = hexToRgb(hexA);
  const [r2, g2, b2] = hexToRgb(hexB);
  const l1 = relativeLuminance(r1, g1, b1);
  const l2 = relativeLuminance(r2, g2, b2);
  const lighter = Math.max(l1, l2);
  const darker = Math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
};

const rgbToHsl = (r: number, g: number, b: number): [number, number, number] => {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h = 0;
  const l = (max + min) / 2;
  const d = max - min;
  let s = 0;
  if (d !== 0) {
    s = d / (1 - Math.abs(2 * l - 1));
    switch (max) {
      case r:
        h = ((g - b) / d) % 6;
        break;
      case g:
        h = (b - r) / d + 2;
        break;
      default:
        h = (r - g) / d + 4;
        break;
    }
    h *= 60;
    if (h < 0) h += 360;
  }
  return [h, s, l];
};

const hslToRgb = (h: number, s: number, l: number): [number, number, number] => {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let r = 0;
  let g = 0;
  let b = 0;
  if (h < 60) {
    r = c; g = x; b = 0;
  } else if (h < 120) {
    r = x; g = c; b = 0;
  } else if (h < 180) {
    r = 0; g = c; b = x;
  } else if (h < 240) {
    r = 0; g = x; b = c;
  } else if (h < 300) {
    r = x; g = 0; b = c;
  } else {
    r = c; g = 0; b = x;
  }
  return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
};

// Binary search for the minimum HSL lightness (same hue/saturation as
// `primaryHex`) whose resulting color reaches >= 4.5:1 contrast against
// every token in `DARK_SURFACE_TOKENS`. Luminance increases monotonically
// with lightness and the surfaces are both near-black, so contrast against
// each surface increases monotonically with lightness too -- white (L=1)
// always passes, which bounds the search.
const deriveOnDark = (primaryHex: string, minRatio = 4.5): string => {
  const [r, g, b] = hexToRgb(primaryHex);
  const [h, s] = rgbToHsl(r, g, b);

  const passes = (l: number): boolean => {
    const [rr, gg, bb] = hslToRgb(h, s, l);
    const candidate = rgbToHex(rr, gg, bb);
    return DARK_SURFACE_TOKENS.every((bg) => wcagContrastRatio(candidate, bg) >= minRatio);
  };

  let lo = 0;
  let hi = 1;
  // hi=1 is pure white given hue/sat, which always clears 4.5:1 against a
  // near-black surface -- guaranteed terminating, convergent search.
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (passes(mid)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  const [rr, gg, bb] = hslToRgb(h, s, hi);
  return rgbToHex(rr, gg, bb);
};

export const NBA_TEAMS_METADATA: Record<string, TeamMetadata> = Object.fromEntries(
  Object.entries(RAW_NBA_TEAMS_METADATA).map(([abbr, meta]) => [
    abbr,
    {
      ...meta,
      colors: {
        ...meta.colors,
        onDark: deriveOnDark(meta.colors.primary),
      },
    },
  ])
);

export const getTeamLogoUrl = (teamAbbr: string): string => {
  const meta = NBA_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  const code = meta?.espnCode || teamAbbr?.toLowerCase();
  return `https://a.espncdn.com/i/teamlogos/nba/500/${code}.png`;
};

export const getTeamColors = (teamAbbr: string): TeamMetadata['colors'] => {
  const meta = NBA_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  return (
    meta?.colors || {
      primary: '#6366f1',
      secondary: '#4f46e5',
      accent: '#1e1b4b',
      onDark: deriveOnDark('#6366f1'),
    }
  );
};
