import { BASE_PATH } from './basePath';

export interface TeamMetadata {
  abbr: string;
  name: string;
  fullName: string;
  espnCode: string;
  conference: 'East' | 'West';
  division: string;
  colors: {
    primary: string;
    secondary: string;
    accent: string;
    // Issue #133: lightened variant of `primary` guaranteed to reach >= 4.5:1
    // WCAG contrast against both dark surface tokens (#100a22 / #1d1440).
    // Purely additive — computed on read in getTeamColors(), not stored
    // statically below, so it can never drift from the contrast formula.
    onDark?: string;
  };
}

// Issue #133: `colors.primary` was computed for use on light/neutral
// backgrounds (logo chips, borders) and 13/15 teams fail the WCAG 2.2 4.5:1
// text contrast minimum against this app's dark surface tokens
// (`surface` #100a22 / `surface-raised` #1d1440 in tailwind.config.ts).
// Nothing in this codebase uses `colors.primary`/`secondary`/`accent` as a
// text or stroke color today (re-verified: no `.colors.primary` et al. usage
// outside tests) — `onDark` below is purely additive so a future text/stroke
// use case has a color guaranteed to pass, without touching the existing
// swatch fields.

const hexToRgb = (hex: string): [number, number, number] => {
  const clean = hex.replace('#', '');
  const r = parseInt(clean.substring(0, 2), 16);
  const g = parseInt(clean.substring(2, 4), 16);
  const b = parseInt(clean.substring(4, 6), 16);
  return [r, g, b];
};

const rgbToHex = (r: number, g: number, b: number): string => {
  const toHex = (v: number) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
};

// WCAG 2.x relative luminance: https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
const relativeLuminance = (hex: string): number => {
  const [r, g, b] = hexToRgb(hex).map((c) => {
    const srgb = c / 255;
    return srgb <= 0.03928 ? srgb / 12.92 : Math.pow((srgb + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

// WCAG 2.x contrast ratio: https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
export const contrastRatio = (hexA: string, hexB: string): number => {
  const lA = relativeLuminance(hexA);
  const lB = relativeLuminance(hexB);
  const lighter = Math.max(lA, lB);
  const darker = Math.min(lA, lB);
  return (lighter + 0.05) / (darker + 0.05);
};

// Mixes `hex` toward white by factor `t` in [0, 1] — a simple, predictable
// way to lighten a dark team primary without changing its hue.
const mixTowardWhite = (hex: string, t: number): string => {
  const [r, g, b] = hexToRgb(hex);
  return rgbToHex(r + (255 - r) * t, g + (255 - g) * t, b + (255 - b) * t);
};

// Lightens `baseHex` by the minimum amount needed to reach >= 4.5:1 contrast
// against BOTH dark surface tokens. Steps in fine increments up to white
// (t=1), which is always >= 4.5:1 against both surfaces, so this always
// terminates with a passing color.
const DARK_SURFACES = ['#100a22', '#1d1440'] as const;

const deriveOnDark = (baseHex: string): string => {
  if (DARK_SURFACES.every((surface) => contrastRatio(baseHex, surface) >= 4.5)) {
    return baseHex;
  }
  for (let step = 1; step <= 200; step++) {
    const t = step / 200;
    const candidate = mixTowardWhite(baseHex, t);
    if (DARK_SURFACES.every((surface) => contrastRatio(candidate, surface) >= 4.5)) {
      return candidate;
    }
  }
  return '#ffffff';
};

export const WNBA_TEAMS_METADATA: Record<string, TeamMetadata> = {
  ATL: {
    abbr: 'ATL',
    name: 'Dream',
    fullName: 'Atlanta Dream',
    espnCode: 'atl',
    conference: 'East',
    division: 'Eastern',
    colors: { primary: '#C8102E', secondary: '#41748D', accent: '#DCE1E5' },
  },
  CHI: {
    abbr: 'CHI',
    name: 'Sky',
    fullName: 'Chicago Sky',
    espnCode: 'chi',
    conference: 'East',
    division: 'Eastern',
    colors: { primary: '#418FDE', secondary: '#FEE123', accent: '#000000' },
  },
  CON: {
    abbr: 'CON',
    name: 'Sun',
    fullName: 'Connecticut Sun',
    espnCode: 'conn',
    conference: 'East',
    division: 'Eastern',
    colors: { primary: '#F05023', secondary: '#002D62', accent: '#FDBB30' },
  },
  DAL: {
    abbr: 'DAL',
    name: 'Wings',
    fullName: 'Dallas Wings',
    espnCode: 'dal',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#0C2340', secondary: '#C4D600', accent: '#00A3E0' },
  },
  GS: {
    abbr: 'GS',
    name: 'Valkyries',
    fullName: 'Golden State Valkyries',
    espnCode: 'gs',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#552583', secondary: '#FDB927', accent: '#000000' },
  },
  IND: {
    abbr: 'IND',
    name: 'Fever',
    fullName: 'Indiana Fever',
    espnCode: 'ind',
    conference: 'East',
    division: 'Eastern',
    colors: { primary: '#002D62', secondary: '#C8102E', accent: '#FDBB30' },
  },
  LA: {
    abbr: 'LA',
    name: 'Sparks',
    fullName: 'Los Angeles Sparks',
    espnCode: 'la',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#552583', secondary: '#FDB927', accent: '#007A33' },
  },
  LV: {
    abbr: 'LV',
    name: 'Aces',
    fullName: 'Las Vegas Aces',
    espnCode: 'lv',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#000000', secondary: '#C4CED4', accent: '#BA9653' },
  },
  MIN: {
    abbr: 'MIN',
    name: 'Lynx',
    fullName: 'Minnesota Lynx',
    espnCode: 'min',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#002B5C', secondary: '#78BE20', accent: '#00A3E0' },
  },
  NY: {
    abbr: 'NY',
    name: 'Liberty',
    fullName: 'New York Liberty',
    espnCode: 'ny',
    conference: 'East',
    division: 'Eastern',
    colors: { primary: '#000000', secondary: '#6ECEB2', accent: '#FDBB30' },
  },
  PHX: {
    abbr: 'PHX',
    name: 'Mercury',
    fullName: 'Phoenix Mercury',
    espnCode: 'phx',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#552583', secondary: '#F36F21', accent: '#8B2131' },
  },
  POR: {
    abbr: 'POR',
    name: 'Fire',
    fullName: 'Portland Fire',
    espnCode: 'por',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#E03A3E', secondary: '#000000', accent: '#FDBB30' },
  },
  SEA: {
    abbr: 'SEA',
    name: 'Storm',
    fullName: 'Seattle Storm',
    espnCode: 'sea',
    conference: 'West',
    division: 'Western',
    colors: { primary: '#00471B', secondary: '#FEE123', accent: '#F05023' },
  },
  TOR: {
    abbr: 'TOR',
    name: 'Tempo',
    fullName: 'Toronto Tempo',
    espnCode: 'tor',
    conference: 'East',
    division: 'Eastern',
    colors: { primary: '#CE1141', secondary: '#000000', accent: '#A1A1A4' },
  },
  WSH: {
    abbr: 'WSH',
    name: 'Mystics',
    fullName: 'Washington Mystics',
    espnCode: 'wsh',
    conference: 'East',
    division: 'Eastern',
    colors: { primary: '#002B5C', secondary: '#C8102E', accent: '#C4CED4' },
  },
};

export const getTeamLogoUrl = (teamAbbr: string): string => {
  const normalized = teamAbbr?.toUpperCase();
  return `${BASE_PATH}/logos/${normalized}_logo.png`;
};

export const getTeamColors = (teamAbbr: string) => {
  const meta = WNBA_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  const colors = meta?.colors || { primary: '#6366f1', secondary: '#4f46e5', accent: '#1e1b4b' };
  return { ...colors, onDark: deriveOnDark(colors.primary) };
};
