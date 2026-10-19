export interface TeamMetadata {
  abbr: string;
  name: string;
  fullName: string;
  city: string;
  conference: 'AFC' | 'NFC';
  division: string;
  espnCode: string;
  colors: {
    primary: string;
    secondary: string;
    accent: string;
  };
}

export const NFL_TEAMS_METADATA: Record<string, TeamMetadata> = {
  // AFC East
  BUF: {
    abbr: 'BUF',
    name: 'Bills',
    fullName: 'Buffalo Bills',
    city: 'Buffalo',
    conference: 'AFC',
    division: 'AFC East',
    espnCode: 'buf',
    colors: { primary: '#00338D', secondary: '#C60C30', accent: '#FFFFFF' },
  },
  MIA: {
    abbr: 'MIA',
    name: 'Dolphins',
    fullName: 'Miami Dolphins',
    city: 'Miami',
    conference: 'AFC',
    division: 'AFC East',
    espnCode: 'mia',
    colors: { primary: '#008E97', secondary: '#FC4C02', accent: '#005778' },
  },
  NE: {
    abbr: 'NE',
    name: 'Patriots',
    fullName: 'New England Patriots',
    city: 'New England',
    conference: 'AFC',
    division: 'AFC East',
    espnCode: 'ne',
    colors: { primary: '#002244', secondary: '#C60C30', accent: '#B0B7BC' },
  },
  NYJ: {
    abbr: 'NYJ',
    name: 'Jets',
    fullName: 'New York Jets',
    city: 'New York',
    conference: 'AFC',
    division: 'AFC East',
    espnCode: 'nyj',
    colors: { primary: '#125740', secondary: '#000000', accent: '#FFFFFF' },
  },

  // AFC North
  BAL: {
    abbr: 'BAL',
    name: 'Ravens',
    fullName: 'Baltimore Ravens',
    city: 'Baltimore',
    conference: 'AFC',
    division: 'AFC North',
    espnCode: 'bal',
    colors: { primary: '#241773', secondary: '#000000', accent: '#9E7C0C' },
  },
  CIN: {
    abbr: 'CIN',
    name: 'Bengals',
    fullName: 'Cincinnati Bengals',
    city: 'Cincinnati',
    conference: 'AFC',
    division: 'AFC North',
    espnCode: 'cin',
    colors: { primary: '#FB4F14', secondary: '#000000', accent: '#FFFFFF' },
  },
  CLE: {
    abbr: 'CLE',
    name: 'Browns',
    fullName: 'Cleveland Browns',
    city: 'Cleveland',
    conference: 'AFC',
    division: 'AFC North',
    espnCode: 'cle',
    colors: { primary: '#311D00', secondary: '#FF3C00', accent: '#FFFFFF' },
  },
  PIT: {
    abbr: 'PIT',
    name: 'Steelers',
    fullName: 'Pittsburgh Steelers',
    city: 'Pittsburgh',
    conference: 'AFC',
    division: 'AFC North',
    espnCode: 'pit',
    colors: { primary: '#FFB612', secondary: '#101820', accent: '#00539B' },
  },

  // AFC South
  HOU: {
    abbr: 'HOU',
    name: 'Texans',
    fullName: 'Houston Texans',
    city: 'Houston',
    conference: 'AFC',
    division: 'AFC South',
    espnCode: 'hou',
    colors: { primary: '#03202F', secondary: '#A71930', accent: '#FFFFFF' },
  },
  IND: {
    abbr: 'IND',
    name: 'Colts',
    fullName: 'Indianapolis Colts',
    city: 'Indianapolis',
    conference: 'AFC',
    division: 'AFC South',
    espnCode: 'ind',
    colors: { primary: '#002C5F', secondary: '#A2AAAD', accent: '#FFFFFF' },
  },
  JAX: {
    abbr: 'JAX',
    name: 'Jaguars',
    fullName: 'Jacksonville Jaguars',
    city: 'Jacksonville',
    conference: 'AFC',
    division: 'AFC South',
    espnCode: 'jax',
    colors: { primary: '#006778', secondary: '#D7A22A', accent: '#101820' },
  },
  TEN: {
    abbr: 'TEN',
    name: 'Titans',
    fullName: 'Tennessee Titans',
    city: 'Tennessee',
    conference: 'AFC',
    division: 'AFC South',
    espnCode: 'ten',
    colors: { primary: '#0C2340', secondary: '#4B92DB', accent: '#C8102E' },
  },

  // AFC West
  DEN: {
    abbr: 'DEN',
    name: 'Broncos',
    fullName: 'Denver Broncos',
    city: 'Denver',
    conference: 'AFC',
    division: 'AFC West',
    espnCode: 'den',
    colors: { primary: '#FB4F14', secondary: '#002244', accent: '#FFFFFF' },
  },
  KC: {
    abbr: 'KC',
    name: 'Chiefs',
    fullName: 'Kansas City Chiefs',
    city: 'Kansas City',
    conference: 'AFC',
    division: 'AFC West',
    espnCode: 'kc',
    colors: { primary: '#E31837', secondary: '#FFB81C', accent: '#FFFFFF' },
  },
  LV: {
    abbr: 'LV',
    name: 'Raiders',
    fullName: 'Las Vegas Raiders',
    city: 'Las Vegas',
    conference: 'AFC',
    division: 'AFC West',
    espnCode: 'lv',
    colors: { primary: '#000000', secondary: '#A5ACAF', accent: '#FFFFFF' },
  },
  LAC: {
    abbr: 'LAC',
    name: 'Chargers',
    fullName: 'Los Angeles Chargers',
    city: 'Los Angeles',
    conference: 'AFC',
    division: 'AFC West',
    espnCode: 'lac',
    colors: { primary: '#0080C6', secondary: '#FFC20E', accent: '#FFFFFF' },
  },

  // NFC East
  DAL: {
    abbr: 'DAL',
    name: 'Cowboys',
    fullName: 'Dallas Cowboys',
    city: 'Dallas',
    conference: 'NFC',
    division: 'NFC East',
    espnCode: 'dal',
    colors: { primary: '#003594', secondary: '#041E42', accent: '#869397' },
  },
  PHI: {
    abbr: 'PHI',
    name: 'Eagles',
    fullName: 'Philadelphia Eagles',
    city: 'Philadelphia',
    conference: 'NFC',
    division: 'NFC East',
    espnCode: 'phi',
    colors: { primary: '#004C54', secondary: '#A5ACAF', accent: '#ACC0C6' },
  },
  WAS: {
    abbr: 'WAS',
    name: 'Commanders',
    fullName: 'Washington Commanders',
    city: 'Washington',
    conference: 'NFC',
    division: 'NFC East',
    espnCode: 'wsh',
    colors: { primary: '#5A1414', secondary: '#FFB612', accent: '#FFFFFF' },
  },
  NYG: {
    abbr: 'NYG',
    name: 'Giants',
    fullName: 'New York Giants',
    city: 'New York',
    conference: 'NFC',
    division: 'NFC East',
    espnCode: 'nyg',
    colors: { primary: '#0B2265', secondary: '#A71930', accent: '#A5ACAF' },
  },

  // NFC North
  CHI: {
    abbr: 'CHI',
    name: 'Bears',
    fullName: 'Chicago Bears',
    city: 'Chicago',
    conference: 'NFC',
    division: 'NFC North',
    espnCode: 'chi',
    colors: { primary: '#0B162A', secondary: '#C83803', accent: '#FFFFFF' },
  },
  DET: {
    abbr: 'DET',
    name: 'Lions',
    fullName: 'Detroit Lions',
    city: 'Detroit',
    conference: 'NFC',
    division: 'NFC North',
    espnCode: 'det',
    colors: { primary: '#0076B6', secondary: '#B0B7BC', accent: '#000000' },
  },
  GB: {
    abbr: 'GB',
    name: 'Packers',
    fullName: 'Green Bay Packers',
    city: 'Green Bay',
    conference: 'NFC',
    division: 'NFC North',
    espnCode: 'gb',
    colors: { primary: '#203731', secondary: '#FFB612', accent: '#FFFFFF' },
  },
  MIN: {
    abbr: 'MIN',
    name: 'Vikings',
    fullName: 'Minnesota Vikings',
    city: 'Minnesota',
    conference: 'NFC',
    division: 'NFC North',
    espnCode: 'min',
    colors: { primary: '#4F2683', secondary: '#FFC62F', accent: '#FFFFFF' },
  },

  // NFC South
  ATL: {
    abbr: 'ATL',
    name: 'Falcons',
    fullName: 'Atlanta Falcons',
    city: 'Atlanta',
    conference: 'NFC',
    division: 'NFC South',
    espnCode: 'atl',
    colors: { primary: '#A71930', secondary: '#000000', accent: '#A5ACAF' },
  },
  CAR: {
    abbr: 'CAR',
    name: 'Panthers',
    fullName: 'Carolina Panthers',
    city: 'Carolina',
    conference: 'NFC',
    division: 'NFC South',
    espnCode: 'car',
    colors: { primary: '#0085CA', secondary: '#101820', accent: '#BFC0BF' },
  },
  NO: {
    abbr: 'NO',
    name: 'Saints',
    fullName: 'New Orleans Saints',
    city: 'New Orleans',
    conference: 'NFC',
    division: 'NFC South',
    espnCode: 'no',
    colors: { primary: '#D3BC8D', secondary: '#101820', accent: '#FFFFFF' },
  },
  TB: {
    abbr: 'TB',
    name: 'Buccaneers',
    fullName: 'Tampa Bay Buccaneers',
    city: 'Tampa Bay',
    conference: 'NFC',
    division: 'NFC South',
    espnCode: 'tb',
    colors: { primary: '#D50A0A', secondary: '#0A0A08', accent: '#FF7900' },
  },

  // NFC West
  ARI: {
    abbr: 'ARI',
    name: 'Cardinals',
    fullName: 'Arizona Cardinals',
    city: 'Arizona',
    conference: 'NFC',
    division: 'NFC West',
    espnCode: 'ari',
    colors: { primary: '#97233F', secondary: '#000000', accent: '#FFB612' },
  },
  LA: {
    abbr: 'LA',
    name: 'Rams',
    fullName: 'Los Angeles Rams',
    city: 'Los Angeles',
    conference: 'NFC',
    division: 'NFC West',
    espnCode: 'lar',
    colors: { primary: '#003594', secondary: '#FFA300', accent: '#FFD100' },
  },
  SF: {
    abbr: 'SF',
    name: '49ers',
    fullName: 'San Francisco 49ers',
    city: 'San Francisco',
    conference: 'NFC',
    division: 'NFC West',
    espnCode: 'sf',
    colors: { primary: '#AA0000', secondary: '#B3995D', accent: '#000000' },
  },
  SEA: {
    abbr: 'SEA',
    name: 'Seahawks',
    fullName: 'Seattle Seahawks',
    city: 'Seattle',
    conference: 'NFC',
    division: 'NFC West',
    espnCode: 'sea',
    colors: { primary: '#002244', secondary: '#69BE28', accent: '#A5ACAF' },
  },
};

export const getTeamLogoUrl = (teamAbbr: string): string => {
  const meta = NFL_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  const code = meta?.espnCode || teamAbbr?.toLowerCase();
  return `https://a.espncdn.com/i/teamlogos/nfl/500/${code}.png`;
};

export const getTeamColors = (teamAbbr: string) => {
  const meta = NFL_TEAMS_METADATA[teamAbbr?.toUpperCase()];
  return meta?.colors || { primary: '#10b981', secondary: '#059669', accent: '#022c22' };
};

export const getAllTeams = (): TeamMetadata[] => {
  return Object.values(NFL_TEAMS_METADATA);
};

export const getConferenceTeams = (conf: 'AFC' | 'NFC'): TeamMetadata[] => {
  return Object.values(NFL_TEAMS_METADATA).filter((t) => t.conference === conf);
};

export const getDivisionTeams = (div: string): TeamMetadata[] => {
  return Object.values(NFL_TEAMS_METADATA).filter((t) => t.division === div);
};
