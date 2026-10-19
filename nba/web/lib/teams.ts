export interface TeamMetadata {
  abbr: string;
  name: string;
  fullName: string;
  espnCode: string;
  colors: {
    primary: string;
    secondary: string;
    accent: string;
  };
}

export const NBA_TEAMS_METADATA: Record<string, TeamMetadata> = {
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

export const getTeamLogoUrl = (teamAbbr: string): string => {
  const meta = NBA_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  const code = meta?.espnCode || teamAbbr?.toLowerCase();
  return `https://a.espncdn.com/i/teamlogos/nba/500/${code}.png`;
};

export const getTeamColors = (teamAbbr: string) => {
  const meta = NBA_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  return meta?.colors || { primary: '#6366f1', secondary: '#4f46e5', accent: '#1e1b4b' };
};
