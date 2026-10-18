/**
 * web/lib/ballparks.ts — Accurate Multi-Segment MLB Ballpark Geometries & Field Structures
 *
 * Provides high-resolution polygonal vertices, wall heights, outfield contours,
 * warning track ribbons, and field structures (infield dirt, keyhole strips, backstops)
 * for all 30 MLB ballparks.
 */

export interface WallVertex {
  angle: number; // degrees from home plate: -45° (LF foul pole) to +45° (RF foul pole)
  dist: number; // distance in feet from home plate
  wallHeight: number; // wall height in feet
  label?: string; // e.g. "Green Monster 37.2'", "The Triangle 420'", "Pesky's Pole 302'"
  isKeyMarker?: boolean;
}

export interface BallparkGeometry {
  team: string;
  parkName: string;
  cityState: string;
  roofType: 'Open' | 'Retractable' | 'Fixed Dome';
  surface: 'Natural Grass' | 'Artificial Turf';
  foulTerritory: 'Compact' | 'Standard' | 'Expansive';
  hasKeyholeDirt: boolean; // ARI, DET have historic dirt strip between home and mound
  backstopDistanceFt: number;
  lf: number;
  lcf: number;
  cf: number;
  rcf: number;
  rf: number;
  wallHeightLf: number;
  wallHeightCf: number;
  wallHeightRf: number;
  iconicFeatures: string[];
  wallVertices: WallVertex[];
}

export const MLB_BALLPARKS: Record<string, BallparkGeometry> = {
  BOS: {
    team: 'BOS',
    parkName: 'Fenway Park',
    cityState: 'Boston, MA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Compact',
    hasKeyholeDirt: false,
    backstopDistanceFt: 45,
    lf: 310,
    lcf: 379,
    cf: 390,
    rcf: 380,
    rf: 302,
    wallHeightLf: 37.2,
    wallHeightCf: 17.0,
    wallHeightRf: 3.0,
    iconicFeatures: [
      "Green Monster in LF (310', 37.2' wall)",
      "The Triangle in CF (420' deep alcove)",
      "Pesky's Pole in RF (302', 3' wall)",
    ],
    wallVertices: [
      { angle: -45.0, dist: 310, wallHeight: 37.2, label: "Green Monster 310'", isKeyMarker: true },
      { angle: -37.0, dist: 315, wallHeight: 37.2 },
      { angle: -28.0, dist: 345, wallHeight: 37.2, label: "Monster End 345'", isKeyMarker: true },
      { angle: -22.5, dist: 379, wallHeight: 17.0, label: "379'" },
      { angle: -12.0, dist: 388, wallHeight: 17.0 },
      { angle: -4.0, dist: 390, wallHeight: 17.0, label: "390'" },
      { angle: 2.0, dist: 420, wallHeight: 17.0, label: "Triangle 420'", isKeyMarker: true },
      { angle: 8.0, dist: 405, wallHeight: 10.0 },
      { angle: 18.0, dist: 380, wallHeight: 5.5, label: "380'" },
      { angle: 28.0, dist: 375, wallHeight: 5.5 },
      { angle: 36.0, dist: 350, wallHeight: 5.0 },
      { angle: 41.0, dist: 320, wallHeight: 3.5 },
      { angle: 45.0, dist: 302, wallHeight: 3.0, label: "Pesky's Pole 302'", isKeyMarker: true },
    ],
  },

  NYY: {
    team: 'NYY',
    parkName: 'Yankee Stadium',
    cityState: 'Bronx, NY',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Compact',
    hasKeyholeDirt: false,
    backstopDistanceFt: 52,
    lf: 318,
    lcf: 399,
    cf: 408,
    rcf: 385,
    rf: 314,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      "Short Porch in Right Field (314')",
      "Deep Left-Center Alley (399')",
      'Monument Park Center Field (408\')',
    ],
    wallVertices: [
      { angle: -45.0, dist: 318, wallHeight: 8.0, label: "LF 318'", isKeyMarker: true },
      { angle: -32.0, dist: 355, wallHeight: 8.0 },
      { angle: -22.5, dist: 399, wallHeight: 8.0, label: "LCF 399'", isKeyMarker: true },
      { angle: -10.0, dist: 405, wallHeight: 8.0 },
      { angle: 0.0, dist: 408, wallHeight: 8.0, label: "CF 408'", isKeyMarker: true },
      { angle: 12.0, dist: 400, wallHeight: 8.0 },
      { angle: 22.5, dist: 385, wallHeight: 8.0, label: "RCF 385'", isKeyMarker: true },
      { angle: 32.0, dist: 350, wallHeight: 8.0 },
      { angle: 40.0, dist: 325, wallHeight: 8.0 },
      { angle: 45.0, dist: 314, wallHeight: 8.0, label: "Short Porch 314'", isKeyMarker: true },
    ],
  },

  SF: {
    team: 'SF',
    parkName: 'Oracle Park',
    cityState: 'San Francisco, CA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 48,
    lf: 339,
    lcf: 382,
    cf: 391,
    rcf: 415,
    rf: 309,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 24.0,
    iconicFeatures: [
      "McCovey Cove 24' Brick Wall in RF (309')",
      "Triple's Alley in RCF (415')",
      'Portwalk Overlook & Fog Horn',
    ],
    wallVertices: [
      { angle: -45.0, dist: 339, wallHeight: 8.0, label: "LF 339'", isKeyMarker: true },
      { angle: -30.0, dist: 364, wallHeight: 8.0 },
      { angle: -22.5, dist: 382, wallHeight: 8.0, label: "LCF 382'", isKeyMarker: true },
      { angle: -10.0, dist: 399, wallHeight: 8.0 },
      { angle: 0.0, dist: 391, wallHeight: 8.0, label: "CF 391'", isKeyMarker: true },
      { angle: 12.0, dist: 404, wallHeight: 8.0 },
      { angle: 22.5, dist: 415, wallHeight: 8.0, label: "Triples Alley 415'", isKeyMarker: true },
      { angle: 30.0, dist: 400, wallHeight: 8.0 },
      { angle: 36.0, dist: 365, wallHeight: 24.0, label: "Brick Wall 24'" },
      { angle: 42.0, dist: 330, wallHeight: 24.0 },
      { angle: 45.0, dist: 309, wallHeight: 24.0, label: "McCovey Cove 309'", isKeyMarker: true },
    ],
  },

  BAL: {
    team: 'BAL',
    parkName: 'Oriole Park at Camden Yards',
    cityState: 'Baltimore, MD',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 54,
    lf: 384,
    lcf: 398,
    cf: 400,
    rcf: 373,
    rf: 318,
    wallHeightLf: 13.0,
    wallHeightCf: 7.0,
    wallHeightRf: 21.0,
    iconicFeatures: [
      "Pushed-Back LF Wall (384', 13' height)",
      "B&O Warehouse & Eutaw Street in RF (318', 21' scoreboard wall)",
      'Retro-Classic Ballpark Originator',
    ],
    wallVertices: [
      { angle: -45.0, dist: 384, wallHeight: 13.0, label: "LF Wall 384'", isKeyMarker: true },
      { angle: -32.0, dist: 395, wallHeight: 13.0 },
      { angle: -22.5, dist: 398, wallHeight: 13.0, label: "LCF 398'", isKeyMarker: true },
      { angle: -12.0, dist: 405, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 7.0, label: "CF 400'", isKeyMarker: true },
      { angle: 15.0, dist: 388, wallHeight: 7.0 },
      { angle: 22.5, dist: 373, wallHeight: 7.0, label: "RCF 373'", isKeyMarker: true },
      { angle: 34.0, dist: 350, wallHeight: 21.0, label: "21' Scoreboard" },
      { angle: 42.0, dist: 330, wallHeight: 21.0 },
      { angle: 45.0, dist: 318, wallHeight: 21.0, label: "Eutaw St 318'", isKeyMarker: true },
    ],
  },

  HOU: {
    team: 'HOU',
    parkName: 'Daikin Park (Minute Maid)',
    cityState: 'Houston, TX',
    roofType: 'Retractable',
    surface: 'Natural Grass',
    foulTerritory: 'Compact',
    hasKeyholeDirt: false,
    backstopDistanceFt: 49,
    lf: 315,
    lcf: 362,
    cf: 409,
    rcf: 373,
    rf: 326,
    wallHeightLf: 19.0,
    wallHeightCf: 8.0,
    wallHeightRf: 7.0,
    iconicFeatures: [
      "Crawford Boxes in LF (315', 19' wall)",
      "Deep Center Field Notch (409')",
      'Union Station Train Tracks Overlook',
    ],
    wallVertices: [
      { angle: -45.0, dist: 315, wallHeight: 19.0, label: "Crawford Boxes 315'", isKeyMarker: true },
      { angle: -32.0, dist: 335, wallHeight: 19.0 },
      { angle: -25.0, dist: 362, wallHeight: 19.0, label: "LCF 362'", isKeyMarker: true },
      { angle: -15.0, dist: 390, wallHeight: 10.0 },
      { angle: 0.0, dist: 409, wallHeight: 8.0, label: "CF 409'", isKeyMarker: true },
      { angle: 12.0, dist: 395, wallHeight: 8.0 },
      { angle: 22.5, dist: 373, wallHeight: 7.0, label: "RCF 373'", isKeyMarker: true },
      { angle: 35.0, dist: 345, wallHeight: 7.0 },
      { angle: 45.0, dist: 326, wallHeight: 7.0, label: "RF 326'", isKeyMarker: true },
    ],
  },

  LAD: {
    team: 'LAD',
    parkName: 'Dodger Stadium',
    cityState: 'Los Angeles, CA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Expansive',
    hasKeyholeDirt: false,
    backstopDistanceFt: 62,
    lf: 330,
    lcf: 367,
    cf: 395,
    rcf: 367,
    rf: 330,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      '1962 Classic Hexagonal Symmetrical Outfield Pavilions',
      "330' Foul Lines with 395' Dead Center",
      'Chavez Ravine Palm Trees & San Gabriel Mountains View',
    ],
    wallVertices: [
      { angle: -45.0, dist: 330, wallHeight: 8.0, label: "LF 330'", isKeyMarker: true },
      { angle: -30.0, dist: 350, wallHeight: 8.0 },
      { angle: -22.5, dist: 367, wallHeight: 8.0, label: "LCF 367'", isKeyMarker: true },
      { angle: -10.0, dist: 385, wallHeight: 8.0 },
      { angle: 0.0, dist: 395, wallHeight: 8.0, label: "CF 395'", isKeyMarker: true },
      { angle: 10.0, dist: 385, wallHeight: 8.0 },
      { angle: 22.5, dist: 367, wallHeight: 8.0, label: "RCF 367'", isKeyMarker: true },
      { angle: 30.0, dist: 350, wallHeight: 8.0 },
      { angle: 45.0, dist: 330, wallHeight: 8.0, label: "RF 330'", isKeyMarker: true },
    ],
  },

  COL: {
    team: 'COL',
    parkName: 'Coors Field',
    cityState: 'Denver, CO',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Expansive',
    hasKeyholeDirt: false,
    backstopDistanceFt: 58,
    lf: 347,
    lcf: 390,
    cf: 415,
    rcf: 375,
    rf: 350,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 16.5,
    iconicFeatures: [
      "Mile-High Altitude & Humidor, Massive 415' CF",
      "16.5' Out-of-Town Scoreboard Wall in RF (350')",
      'The Rooftop Deck & Rocky Mountain Sunset',
    ],
    wallVertices: [
      { angle: -45.0, dist: 347, wallHeight: 8.0, label: "LF 347'", isKeyMarker: true },
      { angle: -32.0, dist: 375, wallHeight: 8.0 },
      { angle: -22.5, dist: 390, wallHeight: 8.0, label: "LCF 390'", isKeyMarker: true },
      { angle: -10.0, dist: 405, wallHeight: 8.0 },
      { angle: 0.0, dist: 415, wallHeight: 8.0, label: "CF 415'", isKeyMarker: true },
      { angle: 12.0, dist: 400, wallHeight: 8.0 },
      { angle: 22.5, dist: 375, wallHeight: 8.0, label: "RCF 375'", isKeyMarker: true },
      { angle: 32.0, dist: 360, wallHeight: 16.5, label: "16.5' Scoreboard" },
      { angle: 45.0, dist: 350, wallHeight: 16.5, label: "RF 350'", isKeyMarker: true },
    ],
  },

  TOR: {
    team: 'TOR',
    parkName: 'Rogers Centre',
    cityState: 'Toronto, ON',
    roofType: 'Retractable',
    surface: 'Artificial Turf',
    foulTerritory: 'Compact',
    hasKeyholeDirt: false,
    backstopDistanceFt: 51,
    lf: 328,
    lcf: 368,
    cf: 400,
    rcf: 359,
    rf: 327,
    wallHeightLf: 14.3,
    wallHeightCf: 8.0,
    wallHeightRf: 12.6,
    iconicFeatures: [
      "2023-24 Renovated Asymmetrical Raised Bullpens (14.3' LF / 12.6' RF)",
      "Shortened RCF Cutout (359')",
      'CN Tower View & Fully Retractable Dome',
    ],
    wallVertices: [
      { angle: -45.0, dist: 328, wallHeight: 14.3, label: "LF 328'", isKeyMarker: true },
      { angle: -32.0, dist: 355, wallHeight: 14.3 },
      { angle: -22.5, dist: 368, wallHeight: 14.3, label: "Raised Bullpen 368'", isKeyMarker: true },
      { angle: -10.0, dist: 390, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "CF 400'", isKeyMarker: true },
      { angle: 10.0, dist: 385, wallHeight: 8.0 },
      { angle: 22.5, dist: 359, wallHeight: 12.6, label: "Cutout 359'", isKeyMarker: true },
      { angle: 34.0, dist: 345, wallHeight: 12.6 },
      { angle: 45.0, dist: 327, wallHeight: 12.6, label: "RF 327'", isKeyMarker: true },
    ],
  },

  PIT: {
    team: 'PIT',
    parkName: 'PNC Park',
    cityState: 'Pittsburgh, PA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 51,
    lf: 325,
    lcf: 383,
    cf: 399,
    rcf: 375,
    rf: 320,
    wallHeightLf: 6.0,
    wallHeightCf: 10.0,
    wallHeightRf: 21.0,
    iconicFeatures: [
      "Roberto Clemente 21' Wall in Right Field (320')",
      'Allegheny River & Roberto Clemente Bridge Skyline View',
      "Deep Notch in Left-Center (383' - 410')",
    ],
    wallVertices: [
      { angle: -45.0, dist: 325, wallHeight: 6.0, label: "LF 325'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 6.0 },
      { angle: -22.5, dist: 383, wallHeight: 10.0, label: "LCF 383'", isKeyMarker: true },
      { angle: -12.0, dist: 410, wallHeight: 10.0, label: "Deep Notch 410'" },
      { angle: 0.0, dist: 399, wallHeight: 10.0, label: "CF 399'", isKeyMarker: true },
      { angle: 15.0, dist: 388, wallHeight: 10.0 },
      { angle: 22.5, dist: 375, wallHeight: 10.0, label: "RCF 375'", isKeyMarker: true },
      { angle: 32.0, dist: 350, wallHeight: 21.0 },
      { angle: 40.0, dist: 330, wallHeight: 21.0, label: "Clemente Wall 21'" },
      { angle: 45.0, dist: 320, wallHeight: 21.0, label: "RF 320'", isKeyMarker: true },
    ],
  },

  CHC: {
    team: 'CHC',
    parkName: 'Wrigley Field',
    cityState: 'Chicago, IL',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Compact',
    hasKeyholeDirt: false,
    backstopDistanceFt: 55,
    lf: 355,
    lcf: 368,
    cf: 400,
    rcf: 368,
    rf: 353,
    wallHeightLf: 11.5,
    wallHeightCf: 11.5,
    wallHeightRf: 11.5,
    iconicFeatures: [
      "Historic Ivy-Covered Brick Walls with Outfield Basket (11.5')",
      "Gentle Asymmetric Power Alleys (368')",
      'Hand-Operated Scoreboard & Rooftop Bleachers',
    ],
    wallVertices: [
      { angle: -45.0, dist: 355, wallHeight: 11.5, label: "LF 355'", isKeyMarker: true },
      { angle: -30.0, dist: 362, wallHeight: 11.5 },
      { angle: -22.5, dist: 368, wallHeight: 11.5, label: "LCF 368'", isKeyMarker: true },
      { angle: -10.0, dist: 388, wallHeight: 11.5 },
      { angle: 0.0, dist: 400, wallHeight: 11.5, label: "CF 400'", isKeyMarker: true },
      { angle: 10.0, dist: 388, wallHeight: 11.5 },
      { angle: 22.5, dist: 368, wallHeight: 11.5, label: "RCF 368'", isKeyMarker: true },
      { angle: 30.0, dist: 362, wallHeight: 11.5 },
      { angle: 45.0, dist: 353, wallHeight: 11.5, label: "RF 353'", isKeyMarker: true },
    ],
  },

  SD: {
    team: 'SD',
    parkName: 'Petco Park',
    cityState: 'San Diego, CA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 45,
    lf: 336,
    lcf: 390,
    cf: 396,
    rcf: 391,
    rf: 322,
    wallHeightLf: 7.5,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      "Western Metal Supply Co. Historic Brick Corner in LF (336')",
      "The Beach at Gallagher Square in CF (396')",
      'Deep Right-Center Gap (391\')',
    ],
    wallVertices: [
      { angle: -45.0, dist: 336, wallHeight: 7.5, label: "Western Metal 336'", isKeyMarker: true },
      { angle: -36.0, dist: 355, wallHeight: 7.5 },
      { angle: -22.5, dist: 390, wallHeight: 7.5, label: "LCF 390'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 396, wallHeight: 8.0, label: "CF 396'", isKeyMarker: true },
      { angle: 12.0, dist: 398, wallHeight: 8.0 },
      { angle: 22.5, dist: 391, wallHeight: 8.0, label: "RCF 391'", isKeyMarker: true },
      { angle: 33.0, dist: 355, wallHeight: 8.0 },
      { angle: 45.0, dist: 322, wallHeight: 8.0, label: "RF 322'", isKeyMarker: true },
    ],
  },

  ARI: {
    team: 'ARI',
    parkName: 'Chase Field',
    cityState: 'Phoenix, AZ',
    roofType: 'Retractable',
    surface: 'Artificial Turf',
    foulTerritory: 'Standard',
    hasKeyholeDirt: true,
    backstopDistanceFt: 48,
    lf: 330,
    lcf: 374,
    cf: 407,
    rcf: 374,
    rf: 334,
    wallHeightLf: 7.5,
    wallHeightCf: 25.0,
    wallHeightRf: 7.5,
    iconicFeatures: [
      'Historic Keyhole Dirt Strip connecting Home Plate to Pitcher Mound',
      "25' Center Field Batter's Eye Wall (407')",
      'Swimming Pool Suite in Right-Center Field (374\')',
    ],
    wallVertices: [
      { angle: -45.0, dist: 330, wallHeight: 7.5, label: "LF 330'", isKeyMarker: true },
      { angle: -30.0, dist: 355, wallHeight: 7.5 },
      { angle: -22.5, dist: 374, wallHeight: 7.5, label: "LCF 374'", isKeyMarker: true },
      { angle: -8.0, dist: 400, wallHeight: 25.0, label: "25' Center Wall" },
      { angle: 0.0, dist: 407, wallHeight: 25.0, label: "CF 407'", isKeyMarker: true },
      { angle: 8.0, dist: 400, wallHeight: 25.0 },
      { angle: 22.5, dist: 374, wallHeight: 7.5, label: "Pool 374'", isKeyMarker: true },
      { angle: 32.0, dist: 355, wallHeight: 7.5 },
      { angle: 45.0, dist: 334, wallHeight: 7.5, label: "RF 334'", isKeyMarker: true },
    ],
  },

  DET: {
    team: 'DET',
    parkName: 'Comerica Park',
    cityState: 'Detroit, MI',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: true,
    backstopDistanceFt: 54,
    lf: 342,
    lcf: 370,
    cf: 412,
    rcf: 365,
    rf: 330,
    wallHeightLf: 8.5,
    wallHeightCf: 8.5,
    wallHeightRf: 8.5,
    iconicFeatures: [
      'Historic Keyhole Dirt Strip between Home and Mound',
      "Deepest Center Field in the American League (412')",
      'Tiger Statues & Liquid Fireworks Water Displays',
    ],
    wallVertices: [
      { angle: -45.0, dist: 342, wallHeight: 8.5, label: "LF 342'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 8.5 },
      { angle: -22.5, dist: 370, wallHeight: 8.5, label: "LCF 370'", isKeyMarker: true },
      { angle: -8.0, dist: 405, wallHeight: 8.5 },
      { angle: 0.0, dist: 412, wallHeight: 8.5, label: "CF 412'", isKeyMarker: true },
      { angle: 10.0, dist: 395, wallHeight: 8.5 },
      { angle: 22.5, dist: 365, wallHeight: 8.5, label: "RCF 365'", isKeyMarker: true },
      { angle: 33.0, dist: 348, wallHeight: 8.5 },
      { angle: 45.0, dist: 330, wallHeight: 8.5, label: "RF 330'", isKeyMarker: true },
    ],
  },

  CLE: {
    team: 'CLE',
    parkName: 'Progressive Field',
    cityState: 'Cleveland, OH',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 60,
    lf: 325,
    lcf: 370,
    cf: 400,
    rcf: 375,
    rf: 325,
    wallHeightLf: 19.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      "19' Mini-Monster Wall in Left Field (325')",
      'Toothpick Light Towers & Heritage Park',
      "325' Symmetrical Corner Lines with 400' CF",
    ],
    wallVertices: [
      { angle: -45.0, dist: 325, wallHeight: 19.0, label: "19' Wall 325'", isKeyMarker: true },
      { angle: -32.0, dist: 350, wallHeight: 19.0 },
      { angle: -22.5, dist: 370, wallHeight: 8.0, label: "LCF 370'", isKeyMarker: true },
      { angle: -10.0, dist: 390, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "CF 400'", isKeyMarker: true },
      { angle: 12.0, dist: 390, wallHeight: 8.0 },
      { angle: 22.5, dist: 375, wallHeight: 8.0, label: "RCF 375'", isKeyMarker: true },
      { angle: 34.0, dist: 350, wallHeight: 8.0 },
      { angle: 45.0, dist: 325, wallHeight: 8.0, label: "RF 325'", isKeyMarker: true },
    ],
  },

  MIN: {
    team: 'MIN',
    parkName: 'Target Field',
    cityState: 'Minneapolis, MN',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 53,
    lf: 339,
    lcf: 377,
    cf: 403,
    rcf: 367,
    rf: 328,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 23.0,
    iconicFeatures: [
      "23' Kasota Limestone Wall & Overhang in RF (328')",
      'Minnie and Paul Celebration Sign in CF (403\')',
      "Open-Air Urban Downtown Minneapolis Vistas",
    ],
    wallVertices: [
      { angle: -45.0, dist: 339, wallHeight: 8.0, label: "LF 339'", isKeyMarker: true },
      { angle: -30.0, dist: 362, wallHeight: 8.0 },
      { angle: -22.5, dist: 377, wallHeight: 8.0, label: "LCF 377'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 403, wallHeight: 8.0, label: "CF 403'", isKeyMarker: true },
      { angle: 12.0, dist: 388, wallHeight: 8.0 },
      { angle: 22.5, dist: 367, wallHeight: 8.0, label: "RCF 367'", isKeyMarker: true },
      { angle: 32.0, dist: 350, wallHeight: 23.0, label: "Limestone 23'" },
      { angle: 45.0, dist: 328, wallHeight: 23.0, label: "RF 328'", isKeyMarker: true },
    ],
  },

  KC: {
    team: 'KC',
    parkName: 'Kauffman Stadium',
    cityState: 'Kansas City, MO',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 60,
    lf: 330,
    lcf: 387,
    cf: 410,
    rcf: 387,
    rf: 330,
    wallHeightLf: 8.5,
    wallHeightCf: 8.5,
    wallHeightRf: 8.5,
    iconicFeatures: [
      "Water Spectacular 322' Fountains and Waterfalls",
      "Expansive 410' Center Field with Crown Vision Scoreboard",
      'Wide Outfield Gaps (387\')',
    ],
    wallVertices: [
      { angle: -45.0, dist: 330, wallHeight: 8.5, label: "LF 330'", isKeyMarker: true },
      { angle: -32.0, dist: 365, wallHeight: 8.5 },
      { angle: -22.5, dist: 387, wallHeight: 8.5, label: "LCF 387'", isKeyMarker: true },
      { angle: -10.0, dist: 402, wallHeight: 8.5 },
      { angle: 0.0, dist: 410, wallHeight: 8.5, label: "CF 410'", isKeyMarker: true },
      { angle: 10.0, dist: 402, wallHeight: 8.5 },
      { angle: 22.5, dist: 387, wallHeight: 8.5, label: "RCF 387'", isKeyMarker: true },
      { angle: 32.0, dist: 365, wallHeight: 8.5 },
      { angle: 45.0, dist: 330, wallHeight: 8.5, label: "RF 330'", isKeyMarker: true },
    ],
  },

  ATL: {
    team: 'ATL',
    parkName: 'Truist Park',
    cityState: 'Atlanta, GA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 53,
    lf: 335,
    lcf: 385,
    cf: 400,
    rcf: 375,
    rf: 325,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 16.0,
    iconicFeatures: [
      "16' High Brick Wall in Right Field (325')",
      'The Battery Atlanta Entertainment Complex Surrounding',
      "Chop House Multi-Level Terrace",
    ],
    wallVertices: [
      { angle: -45.0, dist: 335, wallHeight: 8.0, label: "LF 335'", isKeyMarker: true },
      { angle: -30.0, dist: 365, wallHeight: 8.0 },
      { angle: -22.5, dist: 385, wallHeight: 8.0, label: "LCF 385'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "CF 400'", isKeyMarker: true },
      { angle: 12.0, dist: 390, wallHeight: 8.0 },
      { angle: 22.5, dist: 375, wallHeight: 8.0, label: "RCF 375'", isKeyMarker: true },
      { angle: 34.0, dist: 350, wallHeight: 16.0, label: "16' Wall" },
      { angle: 45.0, dist: 325, wallHeight: 16.0, label: "Chop House 325'", isKeyMarker: true },
    ],
  },

  PHI: {
    team: 'PHI',
    parkName: 'Citizens Bank Park',
    cityState: 'Philadelphia, PA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 49,
    lf: 329,
    lcf: 374,
    cf: 401,
    rcf: 369,
    rf: 330,
    wallHeightLf: 10.5,
    wallHeightCf: 8.0,
    wallHeightRf: 13.0,
    iconicFeatures: [
      "Ashburn Alley in Center Field with 13' Wall in Right-Center",
      'Interactive Giant Neon Liberty Bell in Right Field',
      "Left Field Angle Jog (10.5' wall)",
    ],
    wallVertices: [
      { angle: -45.0, dist: 329, wallHeight: 10.5, label: "LF 329'", isKeyMarker: true },
      { angle: -32.0, dist: 355, wallHeight: 10.5 },
      { angle: -22.5, dist: 374, wallHeight: 8.0, label: "LCF 374'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 401, wallHeight: 8.0, label: "CF 401'", isKeyMarker: true },
      { angle: 15.0, dist: 388, wallHeight: 13.0, label: "Ashburn Alley" },
      { angle: 22.5, dist: 369, wallHeight: 13.0, label: "RCF 369'", isKeyMarker: true },
      { angle: 34.0, dist: 348, wallHeight: 13.0 },
      { angle: 45.0, dist: 330, wallHeight: 13.0, label: "RF 330'", isKeyMarker: true },
    ],
  },

  SEA: {
    team: 'SEA',
    parkName: 'T-Mobile Park',
    cityState: 'Seattle, WA',
    roofType: 'Retractable',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 47,
    lf: 331,
    lcf: 378,
    cf: 401,
    rcf: 381,
    rf: 326,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Retractable Rolling Umbrella Roof & Puget Sound Breeze',
      "Hand-Operated Scoreboard in Left-Center Field",
      "Pitcher-Friendly Symmetric Dimensions (401' CF)",
    ],
    wallVertices: [
      { angle: -45.0, dist: 331, wallHeight: 8.0, label: "LF 331'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 8.0 },
      { angle: -22.5, dist: 378, wallHeight: 8.0, label: "LCF 378'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 401, wallHeight: 8.0, label: "CF 401'", isKeyMarker: true },
      { angle: 10.0, dist: 395, wallHeight: 8.0 },
      { angle: 22.5, dist: 381, wallHeight: 8.0, label: "RCF 381'", isKeyMarker: true },
      { angle: 32.0, dist: 355, wallHeight: 8.0 },
      { angle: 45.0, dist: 326, wallHeight: 8.0, label: "RF 326'", isKeyMarker: true },
    ],
  },

  STL: {
    team: 'STL',
    parkName: 'Busch Stadium',
    cityState: 'St. Louis, MO',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 53,
    lf: 336,
    lcf: 375,
    cf: 400,
    rcf: 375,
    rf: 335,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Framed Sightlines of Gateway Arch Over Center Field',
      "Classic Red-Seat Symmetrical Double Deck",
      "Deep Power Alleys (375')",
    ],
    wallVertices: [
      { angle: -45.0, dist: 336, wallHeight: 8.0, label: "LF 336'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 8.0 },
      { angle: -22.5, dist: 375, wallHeight: 8.0, label: "LCF 375'", isKeyMarker: true },
      { angle: -10.0, dist: 392, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "Arch View 400'", isKeyMarker: true },
      { angle: 10.0, dist: 392, wallHeight: 8.0 },
      { angle: 22.5, dist: 375, wallHeight: 8.0, label: "RCF 375'", isKeyMarker: true },
      { angle: 30.0, dist: 360, wallHeight: 8.0 },
      { angle: 45.0, dist: 335, wallHeight: 8.0, label: "RF 335'", isKeyMarker: true },
    ],
  },

  TEX: {
    team: 'TEX',
    parkName: 'Globe Life Field',
    cityState: 'Arlington, TX',
    roofType: 'Retractable',
    surface: 'Artificial Turf',
    foulTerritory: 'Compact',
    hasKeyholeDirt: false,
    backstopDistanceFt: 46,
    lf: 329,
    lcf: 372,
    cf: 407,
    rcf: 374,
    rf: 326,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Single-Panel Retractable Roof & Climate-Controlled Atmosphere',
      "Transparent Glass Outfield Curtain Wall",
      "407' Dead Center with 372' Power Alleys",
    ],
    wallVertices: [
      { angle: -45.0, dist: 329, wallHeight: 8.0, label: "LF 329'", isKeyMarker: true },
      { angle: -30.0, dist: 355, wallHeight: 8.0 },
      { angle: -22.5, dist: 372, wallHeight: 8.0, label: "LCF 372'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 407, wallHeight: 8.0, label: "CF 407'", isKeyMarker: true },
      { angle: 10.0, dist: 395, wallHeight: 8.0 },
      { angle: 22.5, dist: 374, wallHeight: 8.0, label: "RCF 374'", isKeyMarker: true },
      { angle: 32.0, dist: 350, wallHeight: 8.0 },
      { angle: 45.0, dist: 326, wallHeight: 8.0, label: "RF 326'", isKeyMarker: true },
    ],
  },

  MIL: {
    team: 'MIL',
    parkName: 'American Family Field',
    cityState: 'Milwaukee, WI',
    roofType: 'Retractable',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 56,
    lf: 344,
    lcf: 371,
    cf: 400,
    rcf: 374,
    rf: 345,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      "Bernie Brewer's Slide & Dugout Landing in LCF",
      'Fan-Shaped Retractable Roof with Giant Glass Panels',
      "344' LF / 345' RF Symmetrical Lines",
    ],
    wallVertices: [
      { angle: -45.0, dist: 344, wallHeight: 8.0, label: "LF 344'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 8.0 },
      { angle: -22.5, dist: 371, wallHeight: 8.0, label: "Bernie's Slide 371'", isKeyMarker: true },
      { angle: -10.0, dist: 390, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "CF 400'", isKeyMarker: true },
      { angle: 10.0, dist: 390, wallHeight: 8.0 },
      { angle: 22.5, dist: 374, wallHeight: 8.0, label: "RCF 374'", isKeyMarker: true },
      { angle: 32.0, dist: 360, wallHeight: 8.0 },
      { angle: 45.0, dist: 345, wallHeight: 8.0, label: "RF 345'", isKeyMarker: true },
    ],
  },

  NYM: {
    team: 'NYM',
    parkName: 'Citi Field',
    cityState: 'Queens, NY',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 53,
    lf: 335,
    lcf: 370,
    cf: 408,
    rcf: 380,
    rf: 330,
    wallHeightLf: 8.5,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Home Run Apple Rising in Center Field (408\')',
      "Jackie Robinson Rotunda & Ebbets Field Facade",
      "Mo's Zone in Right Field (380')",
    ],
    wallVertices: [
      { angle: -45.0, dist: 335, wallHeight: 8.5, label: "LF 335'", isKeyMarker: true },
      { angle: -30.0, dist: 355, wallHeight: 8.5 },
      { angle: -22.5, dist: 370, wallHeight: 8.5, label: "LCF 370'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 408, wallHeight: 8.0, label: "Apple CF 408'", isKeyMarker: true },
      { angle: 12.0, dist: 395, wallHeight: 8.0 },
      { angle: 22.5, dist: 380, wallHeight: 8.0, label: "Mo's Zone 380'", isKeyMarker: true },
      { angle: 32.0, dist: 355, wallHeight: 8.0 },
      { angle: 45.0, dist: 330, wallHeight: 8.0, label: "RF 330'", isKeyMarker: true },
    ],
  },

  CHW: {
    team: 'CHW',
    parkName: 'Guaranteed Rate Field',
    cityState: 'Chicago, IL',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 60,
    lf: 330,
    lcf: 375,
    cf: 400,
    rcf: 375,
    rf: 335,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Exploding Pinwheel Scoreboard in Center Field',
      "330' LF / 335' RF Classic Power Hitter Friendly Layout",
      "400' Straightaway Center",
    ],
    wallVertices: [
      { angle: -45.0, dist: 330, wallHeight: 8.0, label: "LF 330'", isKeyMarker: true },
      { angle: -30.0, dist: 355, wallHeight: 8.0 },
      { angle: -22.5, dist: 375, wallHeight: 8.0, label: "LCF 375'", isKeyMarker: true },
      { angle: -10.0, dist: 392, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "CF 400'", isKeyMarker: true },
      { angle: 10.0, dist: 392, wallHeight: 8.0 },
      { angle: 22.5, dist: 375, wallHeight: 8.0, label: "RCF 375'", isKeyMarker: true },
      { angle: 30.0, dist: 355, wallHeight: 8.0 },
      { angle: 45.0, dist: 335, wallHeight: 8.0, label: "RF 335'", isKeyMarker: true },
    ],
  },

  CIN: {
    team: 'CIN',
    parkName: 'Great American Ball Park',
    cityState: 'Cincinnati, OH',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Compact',
    hasKeyholeDirt: false,
    backstopDistanceFt: 45,
    lf: 328,
    lcf: 379,
    cf: 404,
    rcf: 370,
    rf: 325,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Twin Riverboat Smokestacks Blasting Fire After Home Runs',
      'The Gap Architecture Opening to the Ohio River in RCF',
      "Offensive Friendly 328' LF / 325' RF Corners",
    ],
    wallVertices: [
      { angle: -45.0, dist: 328, wallHeight: 8.0, label: "LF 328'", isKeyMarker: true },
      { angle: -30.0, dist: 355, wallHeight: 8.0 },
      { angle: -22.5, dist: 379, wallHeight: 8.0, label: "LCF 379'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 404, wallHeight: 8.0, label: "CF 404'", isKeyMarker: true },
      { angle: 12.0, dist: 388, wallHeight: 8.0 },
      { angle: 22.5, dist: 370, wallHeight: 8.0, label: "River Gap 370'", isKeyMarker: true },
      { angle: 32.0, dist: 345, wallHeight: 8.0 },
      { angle: 45.0, dist: 325, wallHeight: 8.0, label: "RF 325'", isKeyMarker: true },
    ],
  },

  LAA: {
    team: 'LAA',
    parkName: 'Angel Stadium',
    cityState: 'Anaheim, CA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 60,
    lf: 330,
    lcf: 387,
    cf: 400,
    rcf: 370,
    rf: 330,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 18.0,
    iconicFeatures: [
      'Outfield California Rock Pile & Geyser Waterfall in LCF',
      "18' Right Field Out-of-Town Scoreboard Wall",
      "Big 'A' Halo Sign Tower in Parking Plaza",
    ],
    wallVertices: [
      { angle: -45.0, dist: 330, wallHeight: 8.0, label: "LF 330'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 8.0 },
      { angle: -22.5, dist: 387, wallHeight: 8.0, label: "Geyser 387'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "CF 400'", isKeyMarker: true },
      { angle: 12.0, dist: 390, wallHeight: 8.0 },
      { angle: 22.5, dist: 370, wallHeight: 8.0, label: "RCF 370'", isKeyMarker: true },
      { angle: 34.0, dist: 350, wallHeight: 18.0, label: "18' Wall" },
      { angle: 45.0, dist: 330, wallHeight: 18.0, label: "RF 330'", isKeyMarker: true },
    ],
  },

  MIA: {
    team: 'MIA',
    parkName: 'loanDepot park',
    cityState: 'Miami, FL',
    roofType: 'Retractable',
    surface: 'Artificial Turf',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 47,
    lf: 344,
    lcf: 386,
    cf: 400,
    rcf: 387,
    rf: 335,
    wallHeightLf: 8.5,
    wallHeightCf: 8.5,
    wallHeightRf: 8.5,
    iconicFeatures: [
      'Three-Panel Retractable Roof & Operable Glass Wall Over Downtown',
      "344' LF / 335' RF Crisp Angle Turns",
      "400' Straight Center Field",
    ],
    wallVertices: [
      { angle: -45.0, dist: 344, wallHeight: 8.5, label: "LF 344'", isKeyMarker: true },
      { angle: -30.0, dist: 365, wallHeight: 8.5 },
      { angle: -22.5, dist: 386, wallHeight: 8.5, label: "LCF 386'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.5 },
      { angle: 0.0, dist: 400, wallHeight: 8.5, label: "CF 400'", isKeyMarker: true },
      { angle: 10.0, dist: 395, wallHeight: 8.5 },
      { angle: 22.5, dist: 387, wallHeight: 8.5, label: "RCF 387'", isKeyMarker: true },
      { angle: 32.0, dist: 360, wallHeight: 8.5 },
      { angle: 45.0, dist: 335, wallHeight: 8.5, label: "RF 335'", isKeyMarker: true },
    ],
  },

  ATH: {
    team: 'ATH',
    parkName: 'Oakland Coliseum',
    cityState: 'Oakland, CA',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Expansive',
    hasKeyholeDirt: false,
    backstopDistanceFt: 75,
    lf: 330,
    lcf: 388,
    cf: 400,
    rcf: 388,
    rf: 330,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Massive Historic Multi-Purpose Foul Territory',
      "Mount Davis Concrete Seating Wall Towering in CF (400')",
      "330' Symmetric Foul Lines",
    ],
    wallVertices: [
      { angle: -45.0, dist: 330, wallHeight: 8.0, label: "LF 330'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 8.0 },
      { angle: -22.5, dist: 388, wallHeight: 8.0, label: "LCF 388'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 400, wallHeight: 8.0, label: "Mount Davis 400'", isKeyMarker: true },
      { angle: 10.0, dist: 395, wallHeight: 8.0 },
      { angle: 22.5, dist: 388, wallHeight: 8.0, label: "RCF 388'", isKeyMarker: true },
      { angle: 30.0, dist: 360, wallHeight: 8.0 },
      { angle: 45.0, dist: 330, wallHeight: 8.0, label: "RF 330'", isKeyMarker: true },
    ],
  },

  TB: {
    team: 'TB',
    parkName: 'Tropicana Field',
    cityState: 'St. Petersburg, FL',
    roofType: 'Fixed Dome',
    surface: 'Artificial Turf',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 50,
    lf: 315,
    lcf: 370,
    cf: 404,
    rcf: 370,
    rf: 322,
    wallHeightLf: 9.5,
    wallHeightCf: 10.0,
    wallHeightRf: 9.0,
    iconicFeatures: [
      'Slanted Non-Symmetrical Roof Catwalk Rings A-B-C-D',
      "Touch Tank with Live Cownose Rays in Right-Center",
      "Short 315' LF / 322' RF Corner Cuts",
    ],
    wallVertices: [
      { angle: -45.0, dist: 315, wallHeight: 9.5, label: "LF 315'", isKeyMarker: true },
      { angle: -30.0, dist: 345, wallHeight: 9.5 },
      { angle: -22.5, dist: 370, wallHeight: 9.5, label: "LCF 370'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 10.0 },
      { angle: 0.0, dist: 404, wallHeight: 10.0, label: "CF 404'", isKeyMarker: true },
      { angle: 12.0, dist: 390, wallHeight: 10.0 },
      { angle: 22.5, dist: 370, wallHeight: 9.0, label: "Ray Tank 370'", isKeyMarker: true },
      { angle: 32.0, dist: 345, wallHeight: 9.0 },
      { angle: 45.0, dist: 322, wallHeight: 9.0, label: "RF 322'", isKeyMarker: true },
    ],
  },

  WSH: {
    team: 'WSH',
    parkName: 'Nationals Park',
    cityState: 'Washington, DC',
    roofType: 'Open',
    surface: 'Natural Grass',
    foulTerritory: 'Standard',
    hasKeyholeDirt: false,
    backstopDistanceFt: 54,
    lf: 337,
    lcf: 377,
    cf: 402,
    rcf: 370,
    rf: 335,
    wallHeightLf: 8.0,
    wallHeightCf: 8.0,
    wallHeightRf: 8.0,
    iconicFeatures: [
      'Cherry Blossom Trees in Plaza & Anacostia Riverfront',
      "Right Field Scoreboard Notch (370' RCF)",
      "402' Deep Center Field with Cherry Blossoms",
    ],
    wallVertices: [
      { angle: -45.0, dist: 337, wallHeight: 8.0, label: "LF 337'", isKeyMarker: true },
      { angle: -30.0, dist: 360, wallHeight: 8.0 },
      { angle: -22.5, dist: 377, wallHeight: 8.0, label: "LCF 377'", isKeyMarker: true },
      { angle: -10.0, dist: 395, wallHeight: 8.0 },
      { angle: 0.0, dist: 402, wallHeight: 8.0, label: "CF 402'", isKeyMarker: true },
      { angle: 12.0, dist: 390, wallHeight: 8.0 },
      { angle: 22.5, dist: 370, wallHeight: 8.0, label: "RCF 370'", isKeyMarker: true },
      { angle: 32.0, dist: 350, wallHeight: 8.0 },
      { angle: 45.0, dist: 335, wallHeight: 8.0, label: "RF 335'", isKeyMarker: true },
    ],
  },
};

/**
 * Returns canonical ballpark geometry for any MLB team abbreviation.
 * Falls back to Dodger Stadium standard geometry if team abbreviation is not found.
 */
export function getBallparkGeometry(teamAbbr?: string): BallparkGeometry {
  if (!teamAbbr) return MLB_BALLPARKS['LAD'];
  const upper = teamAbbr.toUpperCase();
  return MLB_BALLPARKS[upper] || MLB_BALLPARKS['LAD'];
}

/**
 * Returns all 30 ballpark geometries sorted alphabetically by team name.
 */
export function getAllBallparks(): BallparkGeometry[] {
  return Object.values(MLB_BALLPARKS).sort((a, b) => a.parkName.localeCompare(b.parkName));
}

/**
 * Converts polar ballpark wall vertices (angleDeg, distanceFt) into SVG Cartesian coordinates.
 * Home plate is located at (homeX, homeY).
 * scale is pixels per foot (typically 0.85 - 0.95).
 */
export function generateBallparkSvgData(
  park: BallparkGeometry,
  homeX: number,
  homeY: number,
  scale: number
) {
  const rad = (deg: number) => (deg * Math.PI) / 180;

  // 1. Convert wall vertices to SVG coordinates
  const wallPoints = park.wallVertices.map((v) => {
    const r = v.dist * scale;
    const x = homeX + r * Math.sin(rad(v.angle));
    const y = homeY - r * Math.cos(rad(v.angle));
    return {
      x,
      y,
      angle: v.angle,
      dist: v.dist,
      wallHeight: v.wallHeight,
      label: v.label,
      isKeyMarker: v.isKeyMarker,
    };
  });

  // 2. Generate smooth or multi-segment SVG path for the Outfield Wall
  const wallPath =
    `M ${wallPoints[0].x} ${wallPoints[0].y} ` +
    wallPoints
      .slice(1)
      .map((p) => `L ${p.x} ${p.y}`)
      .join(' ');

  // 3. Generate Warning Track Ribbon (15 ft buffer inward along the wall contour)
  const trackPoints = park.wallVertices.map((v) => {
    const rTrack = Math.max(v.dist - 15, 100) * scale;
    const x = homeX + rTrack * Math.sin(rad(v.angle));
    const y = homeY - rTrack * Math.cos(rad(v.angle));
    return { x, y };
  });

  // Warning track polygon: outer wall forward, then track inner boundary backward
  const warningTrackPolygon =
    `M ${wallPoints[0].x} ${wallPoints[0].y} ` +
    wallPoints
      .slice(1)
      .map((p) => `L ${p.x} ${p.y}`)
      .join(' ') +
    ` L ${trackPoints[trackPoints.length - 1].x} ${trackPoints[trackPoints.length - 1].y} ` +
    trackPoints
      .slice(0, -1)
      .reverse()
      .map((p) => `L ${p.x} ${p.y}`)
      .join(' ') +
    ' Z';

  // 4. Fair Territory Solid Polygon (Home -> LF Pole -> Along Wall -> RF Pole -> Home)
  const fairTerritoryPolygon =
    `M ${homeX} ${homeY} ` +
    wallPoints.map((p) => `L ${p.x} ${p.y}`).join(' ') +
    ` Z`;

  // 5. High Wall Segments (for 3D visual extrusion when wallHeight >= 14 ft)
  const highWallSegments: Array<{ x1: number; y1: number; x2: number; y2: number; height: number; label?: string }> = [];
  for (let i = 0; i < wallPoints.length - 1; i++) {
    const p1 = wallPoints[i];
    const p2 = wallPoints[i + 1];
    const avgHeight = (p1.wallHeight + p2.wallHeight) / 2;
    if (avgHeight >= 14.0) {
      highWallSegments.push({
        x1: p1.x,
        y1: p1.y,
        x2: p2.x,
        y2: p2.y,
        height: avgHeight,
        label: p1.label || p2.label,
      });
    }
  }

  // 6. Backstop and Dugout sideline geometry based on backstopDistanceFt
  const bsDist = park.backstopDistanceFt * scale;
  const backstopPolygon =
    `M ${homeX - 55} ${homeY} ` +
    `L ${homeX - 45} ${homeY + bsDist} ` +
    `L ${homeX + 45} ${homeY + bsDist} ` +
    `L ${homeX + 55} ${homeY} Z`;

  return {
    wallPoints,
    wallPath,
    warningTrackPolygon,
    fairTerritoryPolygon,
    highWallSegments,
    backstopPolygon,
  };
}
