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
  };
}

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
  if (WNBA_TEAMS_METADATA[normalized]) {
    return `/logos/${normalized}_logo.png`;
  }
  return `/logos/${normalized}_logo.png`;
};

export const getTeamColors = (teamAbbr: string) => {
  const meta = WNBA_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  return meta?.colors || { primary: '#6366f1', secondary: '#4f46e5', accent: '#1e1b4b' };
};
