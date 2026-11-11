import { BASE_PATH } from './basePath';

export interface TeamMetadata {
  abbr: string;
  teamId: number;
  name: string;
  fullName: string;
  espnCode: string;
  league: 'AL' | 'NL';
  division: string;
  colors: {
    primary: string;
    secondary: string;
    accent: string;
    // Lightened variant of `primary`, guaranteed >= 4.5:1 WCAG contrast
    // against both of the app's dark surface tokens (#040a1a and #0b1530),
    // for use as text/stroke color on dark backgrounds (issue #133).
    onDark: string;
  };
}

export const MLB_TEAMS_METADATA: Record<string, TeamMetadata> = {
  ARI: {
    abbr: 'ARI',
    teamId: 109,
    name: 'Diamondbacks',
    fullName: 'Arizona Diamondbacks',
    espnCode: 'ari',
    league: 'NL',
    division: 'NL West',
    colors: { primary: '#A71930', secondary: '#E3D4AD', accent: '#30CED8', onDark: '#E7445E' },
  },
  ATL: {
    abbr: 'ATL',
    teamId: 144,
    name: 'Braves',
    fullName: 'Atlanta Braves',
    espnCode: 'atl',
    league: 'NL',
    division: 'NL East',
    colors: { primary: '#CE1141', secondary: '#13274F', accent: '#EAAA00', onDark: '#F32C5E' },
  },
  BAL: {
    abbr: 'BAL',
    teamId: 110,
    name: 'Orioles',
    fullName: 'Baltimore Orioles',
    espnCode: 'bal',
    league: 'AL',
    division: 'AL East',
    colors: { primary: '#DF4601', secondary: '#000000', accent: '#FFFFFF', onDark: '#E84800' },
  },
  BOS: {
    abbr: 'BOS',
    teamId: 111,
    name: 'Red Sox',
    fullName: 'Boston Red Sox',
    espnCode: 'bos',
    league: 'AL',
    division: 'AL East',
    colors: { primary: '#BD3039', secondary: '#0C2340', accent: '#FFFFFF', onDark: '#D8555D' },
  },
  CHC: {
    abbr: 'CHC',
    teamId: 112,
    name: 'Cubs',
    fullName: 'Chicago Cubs',
    espnCode: 'chc',
    league: 'NL',
    division: 'NL Central',
    colors: { primary: '#0E3386', secondary: '#CC3433', accent: '#FFFFFF', onDark: '#477BF0' },
  },
  CHW: {
    abbr: 'CHW',
    teamId: 145,
    name: 'White Sox',
    fullName: 'Chicago White Sox',
    espnCode: 'chw',
    league: 'AL',
    division: 'AL Central',
    colors: { primary: '#27251F', secondary: '#C4CED4', accent: '#FFFFFF', onDark: '#87806A' },
  },
  CIN: {
    abbr: 'CIN',
    teamId: 113,
    name: 'Reds',
    fullName: 'Cincinnati Reds',
    espnCode: 'cin',
    league: 'NL',
    division: 'NL Central',
    colors: { primary: '#C6011F', secondary: '#000000', accent: '#FFFFFF', onDark: '#FF082D' },
  },
  CLE: {
    abbr: 'CLE',
    teamId: 114,
    name: 'Guardians',
    fullName: 'Cleveland Guardians',
    espnCode: 'cle',
    league: 'AL',
    division: 'AL Central',
    colors: { primary: '#00385D', secondary: '#E50022', accent: '#FFFFFF', onDark: '#0085DD' },
  },
  COL: {
    abbr: 'COL',
    teamId: 115,
    name: 'Rockies',
    fullName: 'Colorado Rockies',
    espnCode: 'col',
    league: 'NL',
    division: 'NL West',
    colors: { primary: '#333366', secondary: '#C4CED4', accent: '#000000', onDark: '#7A7ABF' },
  },
  DET: {
    abbr: 'DET',
    teamId: 116,
    name: 'Tigers',
    fullName: 'Detroit Tigers',
    espnCode: 'det',
    league: 'AL',
    division: 'AL Central',
    colors: { primary: '#0C2340', secondary: '#FA4616', accent: '#FFFFFF', onDark: '#3781DE' },
  },
  HOU: {
    abbr: 'HOU',
    teamId: 117,
    name: 'Astros',
    fullName: 'Houston Astros',
    espnCode: 'hou',
    league: 'AL',
    division: 'AL West',
    colors: { primary: '#002D62', secondary: '#EB6E1F', accent: '#F4911E', onDark: '#0E7DFF' },
  },
  KC: {
    abbr: 'KC',
    teamId: 118,
    name: 'Royals',
    fullName: 'Kansas City Royals',
    espnCode: 'kc',
    league: 'AL',
    division: 'AL Central',
    colors: { primary: '#004687', secondary: '#BD9B60', accent: '#FFFFFF', onDark: '#007FF5' },
  },
  LAA: {
    abbr: 'LAA',
    teamId: 108,
    name: 'Angels',
    fullName: 'Los Angeles Angels',
    espnCode: 'laa',
    league: 'AL',
    division: 'AL West',
    colors: { primary: '#BA0021', secondary: '#003263', accent: '#C4CED4', onDark: '#FF0531' },
  },
  LAD: {
    abbr: 'LAD',
    teamId: 119,
    name: 'Dodgers',
    fullName: 'Los Angeles Dodgers',
    espnCode: 'lad',
    league: 'NL',
    division: 'NL West',
    colors: { primary: '#005A9C', secondary: '#EF3E42', accent: '#FFFFFF', onDark: '#0083E3' },
  },
  MIA: {
    abbr: 'MIA',
    teamId: 146,
    name: 'Marlins',
    fullName: 'Miami Marlins',
    espnCode: 'mia',
    league: 'NL',
    division: 'NL East',
    colors: { primary: '#00A3E0', secondary: '#EF3340', accent: '#000000', onDark: '#00A3E0' },
  },
  MIL: {
    abbr: 'MIL',
    teamId: 158,
    name: 'Brewers',
    fullName: 'Milwaukee Brewers',
    espnCode: 'mil',
    league: 'NL',
    division: 'NL Central',
    colors: { primary: '#12284B', secondary: '#FFC52F', accent: '#FFFFFF', onDark: '#4A80D8' },
  },
  MIN: {
    abbr: 'MIN',
    teamId: 142,
    name: 'Twins',
    fullName: 'Minnesota Twins',
    espnCode: 'min',
    league: 'AL',
    division: 'AL Central',
    colors: { primary: '#002B5C', secondary: '#D31145', accent: '#B9975B', onDark: '#0A7DFF' },
  },
  NYM: {
    abbr: 'NYM',
    teamId: 121,
    name: 'Mets',
    fullName: 'New York Mets',
    espnCode: 'nym',
    league: 'NL',
    division: 'NL East',
    colors: { primary: '#002D72', secondary: '#FF5910', accent: '#FFFFFF', onDark: '#267BFF' },
  },
  NYY: {
    abbr: 'NYY',
    teamId: 147,
    name: 'Yankees',
    fullName: 'New York Yankees',
    espnCode: 'nyy',
    league: 'AL',
    division: 'AL East',
    colors: { primary: '#003087', secondary: '#E4002C', accent: '#C4CED4', onDark: '#307AFF' },
  },
  ATH: {
    abbr: 'ATH',
    teamId: 133,
    name: 'Athletics',
    fullName: 'Athletics',
    espnCode: 'oak',
    league: 'AL',
    division: 'AL West',
    colors: { primary: '#003831', secondary: '#EFB21E', accent: '#FFFFFF', onDark: '#00917F' },
  },
  OAK: {
    abbr: 'ATH',
    teamId: 133,
    name: 'Athletics',
    fullName: 'Athletics',
    espnCode: 'oak',
    league: 'AL',
    division: 'AL West',
    colors: { primary: '#003831', secondary: '#EFB21E', accent: '#FFFFFF', onDark: '#00917F' },
  },
  PHI: {
    abbr: 'PHI',
    teamId: 143,
    name: 'Phillies',
    fullName: 'Philadelphia Phillies',
    espnCode: 'phi',
    league: 'NL',
    division: 'NL East',
    colors: { primary: '#E81828', secondary: '#002D72', accent: '#FFFFFF', onDark: '#F03645' },
  },
  PIT: {
    abbr: 'PIT',
    teamId: 134,
    name: 'Pirates',
    fullName: 'Pittsburgh Pirates',
    espnCode: 'pit',
    league: 'NL',
    division: 'NL Central',
    colors: { primary: '#27251F', secondary: '#FDB827', accent: '#FFFFFF', onDark: '#87806A' },
  },
  SD: {
    abbr: 'SD',
    teamId: 135,
    name: 'Padres',
    fullName: 'San Diego Padres',
    espnCode: 'sd',
    league: 'NL',
    division: 'NL West',
    colors: { primary: '#2F241D', secondary: '#FFC425', accent: '#FFFFFF', onDark: '#9F7860' },
  },
  SEA: {
    abbr: 'SEA',
    teamId: 136,
    name: 'Mariners',
    fullName: 'Seattle Mariners',
    espnCode: 'sea',
    league: 'AL',
    division: 'AL West',
    colors: { primary: '#0C2C56', secondary: '#005C5C', accent: '#C4CED4', onDark: '#307FE7' },
  },
  SF: {
    abbr: 'SF',
    teamId: 137,
    name: 'Giants',
    fullName: 'San Francisco Giants',
    espnCode: 'sf',
    league: 'NL',
    division: 'NL West',
    colors: { primary: '#FD5A1E', secondary: '#27251F', accent: '#EFD19F', onDark: '#FD5A1E' },
  },
  STL: {
    abbr: 'STL',
    teamId: 138,
    name: 'Cardinals',
    fullName: 'St. Louis Cardinals',
    espnCode: 'stl',
    league: 'NL',
    division: 'NL Central',
    colors: { primary: '#C41E3A', secondary: '#0C2340', accent: '#FEDB00', onDark: '#E7435E' },
  },
  TB: {
    abbr: 'TB',
    teamId: 139,
    name: 'Rays',
    fullName: 'Tampa Bay Rays',
    espnCode: 'tb',
    league: 'AL',
    division: 'AL East',
    colors: { primary: '#092C5C', secondary: '#8FBCE6', accent: '#F5D130', onDark: '#2B7EEF' },
  },
  TEX: {
    abbr: 'TEX',
    teamId: 140,
    name: 'Rangers',
    fullName: 'Texas Rangers',
    espnCode: 'tex',
    league: 'AL',
    division: 'AL West',
    colors: { primary: '#003278', secondary: '#C0111F', accent: '#FFFFFF', onDark: '#1C7BFF' },
  },
  TOR: {
    abbr: 'TOR',
    teamId: 141,
    name: 'Blue Jays',
    fullName: 'Toronto Blue Jays',
    espnCode: 'tor',
    league: 'AL',
    division: 'AL East',
    colors: { primary: '#134A8E', secondary: '#1D2D5C', accent: '#E8291C', onDark: '#2C80E8' },
  },
  WSH: {
    abbr: 'WSH',
    teamId: 120,
    name: 'Nationals',
    fullName: 'Washington Nationals',
    espnCode: 'wsh',
    league: 'NL',
    division: 'NL East',
    colors: { primary: '#AB0003', secondary: '#14225A', accent: '#FFFFFF', onDark: '#FF0D11' },
  },
};

export const getTeamLogoUrl = (teamAbbr: string): string => {
  const meta = MLB_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  if (meta?.teamId) {
    return `${BASE_PATH}/logos/${meta.teamId}.png`;
  }
  // Unknown/missing team abbreviation (e.g. a player with no team code).
  // Previously this built an ESPN URL from the raw abbreviation, which 404s
  // for anything that isn't a real team code (e.g. "mlb.png" doesn't exist).
  // Fall back to a bundled local asset instead of guessing a remote URL.
  return `${BASE_PATH}/sport-icons/mlb.png`;
};

export const getTeamColors = (teamAbbr: string) => {
  const meta = MLB_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  return (
    meta?.colors || { primary: '#6366f1', secondary: '#4f46e5', accent: '#1e1b4b', onDark: '#A5ADFB' }
  );
};
