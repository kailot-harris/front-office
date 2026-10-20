'use client';

import React, { useState, useMemo } from 'react';
import {
  StatcastSpatialData,
  BattedBallPoint,
  ZoneCell,
} from '@/lib/types';
import {
  Compass,
  Layers,
  Crosshair,
  Shield,
  Activity,
  Info,
  TrendingUp,
  MapPin,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { getBallparkGeometry, generateBallparkSvgData } from '@/lib/ballparks';

interface SpatialAnalyticsClientProps {
  data: StatcastSpatialData;
}

type SpatialTab = 'spray' | 'zone' | 'movement' | 'defense';

export const SpatialAnalyticsClient: React.FC<SpatialAnalyticsClientProps> = ({
  data,
}) => {
  const [activeTab, setActiveTab] = useState<SpatialTab>('spray');

  // --- Tier 1 State ---
  const defaultPark = Object.keys(data.tier1_spray.park_dimensions)[0] || 'NYY';
  const [selectedPark, setSelectedPark] = useState<string>(defaultPark);
  const [sprayHandFilter, setSprayHandFilter] = useState<'ALL' | 'L' | 'R'>('ALL');
  const [sprayTypeFilter, setSprayTypeFilter] = useState<string>('ALL');
  const [hardHitOnly, setHardHitOnly] = useState<boolean>(false);
  const [selectedBall, setSelectedBall] = useState<BattedBallPoint | null>(null);

  // --- Tier 2 State ---
  const [zoneMetric, setZoneMetric] = useState<'pct' | 'swing' | 'whiff' | 'calledStrike'>('whiff');
  const [selectedZone, setSelectedZone] = useState<ZoneCell | null>(null);

  // --- Tier 3 State ---
  const [selectedPitcherId, setSelectedPitcherId] = useState<number>(
    data.tier3_movement.pitcher_arsenals[0]?.pitcher_id || 0
  );
  const [selectedPitchType, setSelectedPitchType] = useState<string | null>(null);

  // --- Calculations for Tier 1 Spray ---
  const filteredBalls = useMemo(() => {
    return data.tier1_spray.batted_balls.filter((b) => {
      if (sprayHandFilter !== 'ALL' && b.stand !== sprayHandFilter) return false;
      if (sprayTypeFilter !== 'ALL' && b.hit_type !== sprayTypeFilter) return false;
      if (hardHitOnly && b.exit_velocity < 95) return false;
      return true;
    });
  }, [data.tier1_spray.batted_balls, sprayHandFilter, sprayTypeFilter, hardHitOnly]);

  const activeParkDim = useMemo(() => {
    return (
      data.tier1_spray.park_dimensions[selectedPark] ||
      data.tier1_spray.park_dimensions[Object.keys(data.tier1_spray.park_dimensions)[0]] || {
        team: 'MLB',
        park: 'Average Park',
        lf: 330,
        lcf: 375,
        cf: 400,
        rcf: 375,
        rf: 330,
        wall_lf: 8,
        wall_cf: 8,
        wall_rf: 8,
      }
    );
  }, [data.tier1_spray.park_dimensions, selectedPark]);

  // Selected Pitcher Arsenal
  const activePitcher = useMemo(() => {
    return (
      data.tier3_movement.pitcher_arsenals.find(
        (p) => p.pitcher_id === selectedPitcherId
      ) || data.tier3_movement.pitcher_arsenals[0]
    );
  }, [data.tier3_movement.pitcher_arsenals, selectedPitcherId]);

  // Color helper for hit types
  const getHitColor = (type: string) => {
    switch (type) {
      case 'Home Run':
        return '#f43f5e'; // rose-500
      case 'Triple':
        return '#f59e0b'; // amber-500
      case 'Double':
        return '#10b981'; // emerald-500
      case 'Single':
        return '#38bdf8'; // sky-400
      default:
        return '#64748b'; // slate-500
    }
  };

  // Color helper for pitch types
  const getPitchColor = (code: string) => {
    switch (code) {
      case 'FF':
        return '#38bdf8'; // sky-400 (4-seam)
      case 'SI':
        return '#14b8a6'; // teal-500 (sinker)
      case 'SL':
        return '#f59e0b'; // amber-500 (slider)
      case 'ST':
        return '#fb923c'; // orange-400 (sweeper)
      case 'FC':
        return '#a855f7'; // purple-500 (cutter)
      case 'CH':
        return '#22c55e'; // emerald-500 (changeup)
      case 'CU':
        return '#ec4899'; // pink-500 (curveball)
      case 'FS':
        return '#06b6d4'; // cyan-500 (splitter)
      case 'SV':
        return '#8b5cf6'; // violet-500 (slurve)
      case 'KC':
        return '#e11d48'; // rose-600 (knuckle curve)
      default:
        return '#94a3b8'; // slate-400
    }
  };

  // SVG coordinate transform for spray chart
  // Home plate is at (250, 440). 1 foot = 0.9 pixels.
  // x: 250 + d_x * 0.9, y: 440 - d_y * 0.9
  const spraySvgWidth = 500;
  const spraySvgHeight = 480;
  const homeX = 250;
  const homeY = 440;
  const scale = 0.92;

  // Accurate Multi-Segment Ballpark Geometry
  const richPark = useMemo(() => getBallparkGeometry(selectedPark), [selectedPark]);
  const parkSvgData = useMemo(() => {
    return generateBallparkSvgData(richPark, homeX, homeY, scale);
  }, [richPark, homeX, homeY, scale]);


  return (
    <div className="space-y-6">
      {/* Top Header Card */}
      <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-96 h-96 bg-sky-500/5 rounded-full blur-3xl pointer-events-none" />
        <div className="flex flex-col lg:flex-row items-start lg:items-center justify-between gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-sky-500/10 text-sky-400 border border-sky-500/20">
                Statcast Spatial Engine
              </span>
              <span className="text-xs text-slate-400">
                High-Resolution Optical & Radar Tracking
              </span>
            </div>
            <h1 className="text-3xl font-extrabold text-white tracking-tight">
              Spatial Baseball Analytics
            </h1>
            <p className="text-slate-400 text-sm mt-1 max-w-2xl">
              Trajectory modeling across batted ball spray coordinates, 3D strike zone heatmaps,
              aerodynamic pitch movement (IVB vs. HB), and defensive shift alignment penalties.
            </p>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 w-full lg:w-auto">
            <div className="bg-slate-950/70 border border-slate-800/80 rounded-xl p-3 text-center">
              <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">
                Pitches Analyzed
              </div>
              <div className="text-xl font-black text-white font-mono mt-0.5">
                {data.sample_pitches_analyzed.toLocaleString()}
              </div>
            </div>
            <div className="bg-slate-950/70 border border-slate-800/80 rounded-xl p-3 text-center">
              <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">
                Batted Balls
              </div>
              <div className="text-xl font-black text-sky-400 font-mono mt-0.5">
                {data.sample_batted_balls.toLocaleString()}
              </div>
            </div>
            <div className="bg-slate-950/70 border border-slate-800/80 rounded-xl p-3 text-center">
              <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">
                Shadow Pitches
              </div>
              <div className="text-xl font-black text-indigo-400 font-mono mt-0.5">
                {data.tier2_zone.framing_summary.total_shadow_taken.toLocaleString()}
              </div>
            </div>
            <div className="bg-slate-950/70 border border-slate-800/80 rounded-xl p-3 text-center">
              <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">
                Shift BABIP Δ
              </div>
              <div className="text-xl font-black text-emerald-400 font-mono mt-0.5">
                {data.tier4_defense.shift_rule_impact.lefty_pull_babip_gain}
              </div>
            </div>
          </div>
        </div>

        {/* Tab Navigation Pill Bar */}
        <div className="flex flex-wrap items-center gap-2 mt-6 pt-4 border-t border-slate-800/80">
          <button
            onClick={() => setActiveTab('spray')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
              activeTab === 'spray'
                ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30 ring-1 ring-emerald-400/50'
                : 'bg-slate-950/60 text-slate-400 hover:text-white hover:bg-slate-800/60 border border-slate-800'
            }`}
          >
            <Compass className="w-4 h-4" />
            <span>Tier 1: Spray & 30-Park Overlay</span>
          </button>

          <button
            onClick={() => setActiveTab('zone')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
              activeTab === 'zone'
                ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30 ring-1 ring-emerald-400/50'
                : 'bg-slate-950/60 text-slate-400 hover:text-white hover:bg-slate-800/60 border border-slate-800'
            }`}
          >
            <Crosshair className="w-4 h-4" />
            <span>Tier 2: Strike Zone Heatmap & Framing</span>
          </button>

          <button
            onClick={() => setActiveTab('movement')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
              activeTab === 'movement'
                ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30 ring-1 ring-emerald-400/50'
                : 'bg-slate-950/60 text-slate-400 hover:text-white hover:bg-slate-800/60 border border-slate-800'
            }`}
          >
            <Activity className="w-4 h-4" />
            <span>Tier 3: Pitch Movement (IVB vs. HB)</span>
          </button>

          <button
            onClick={() => setActiveTab('defense')}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
              activeTab === 'defense'
                ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30 ring-1 ring-emerald-400/50'
                : 'bg-slate-950/60 text-slate-400 hover:text-white hover:bg-slate-800/60 border border-slate-800'
            }`}
          >
            <Shield className="w-4 h-4" />
            <span>Tier 4: Defensive Shift & Sector BABIP</span>
          </button>
        </div>
      </div>

      {/* ========================================================================= */}
      {/* TAB 1: SPRAY CHARTS & 30-PARK DIMENSIONS                                 */}
      {/* ========================================================================= */}
      {activeTab === 'spray' && (
        <div className="space-y-6">
          {/* Controls & Filter Bar */}
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
            <div className="flex flex-wrap items-center gap-3">
              {/* Ballpark Selector */}
              <div>
                <label className="block text-[11px] font-semibold uppercase tracking-wider text-slate-400 mb-1">
                  Ballpark Overlay
                </label>
                <select
                  value={selectedPark}
                  onChange={(e) => setSelectedPark(e.target.value)}
                  className="bg-slate-950 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:ring-1 focus:ring-sky-500"
                >
                  {Object.entries(data.tier1_spray.park_dimensions).map(([code, p]) => (
                    <option key={code} value={code}>
                      {p.team === 'MLB' ? 'League Average (30 Parks)' : `${p.team} - ${p.park}`}
                    </option>
                  ))}
                </select>
              </div>

              {/* Batter Hand Filter */}
              <div>
                <label className="block text-[11px] font-semibold uppercase tracking-wider text-slate-400 mb-1">
                  Batter Hand
                </label>
                <div className="flex rounded-lg bg-slate-950 border border-slate-800 p-0.5">
                  {(['ALL', 'L', 'R'] as const).map((hand) => (
                    <button
                      key={hand}
                      onClick={() => setSprayHandFilter(hand)}
                      className={`px-3 py-1 text-xs font-semibold rounded-md transition-colors ${
                        sprayHandFilter === hand
                          ? 'bg-emerald-600 text-white'
                          : 'text-slate-400 hover:text-white'
                      }`}
                    >
                      {hand === 'ALL' ? 'All' : hand === 'L' ? 'Left (LHH)' : 'Right (RHH)'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Hit Type Filter */}
              <div>
                <label className="block text-[11px] font-semibold uppercase tracking-wider text-slate-400 mb-1">
                  Hit Outcome
                </label>
                <select
                  value={sprayTypeFilter}
                  onChange={(e) => setSprayTypeFilter(e.target.value)}
                  className="bg-slate-950 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:ring-1 focus:ring-sky-500"
                >
                  <option value="ALL">All Outcomes ({filteredBalls.length})</option>
                  <option value="Home Run">Home Runs</option>
                  <option value="Single">Singles</option>
                  <option value="Double">Doubles</option>
                  <option value="Triple">Triples</option>
                  <option value="Out">Field Outs</option>
                </select>
              </div>

              {/* Hard-hit toggle */}
              <div className="flex items-center pt-5">
                <label className="flex items-center gap-2 cursor-pointer text-xs text-slate-300">
                  <input
                    type="checkbox"
                    checked={hardHitOnly}
                    onChange={(e) => setHardHitOnly(e.target.checked)}
                    className="w-4 h-4 rounded bg-slate-950 border-slate-800 text-sky-500 focus:ring-0 focus:ring-offset-0"
                  />
                  <span>Hard-Hit (95+ mph)</span>
                </label>
              </div>
            </div>

            {/* Park Dimension Badges & Architectural Profile */}
            <div className="flex flex-col gap-1.5 text-xs bg-slate-950/80 border border-slate-800 rounded-lg px-3.5 py-2.5">
              <div className="flex items-center gap-3 flex-wrap">
                <span className="text-slate-400 font-medium">Fence Distances:</span>
                <span className="font-mono text-slate-200">
                  LF: <strong className="text-sky-400">{richPark.lf}&apos;</strong> ({richPark.wallHeightLf}&apos; wall)
                </span>
                <span className="text-slate-600">•</span>
                <span className="font-mono text-slate-200">
                  LCF: <strong className="text-sky-400">{richPark.lcf}&apos;</strong>
                </span>
                <span className="text-slate-600">•</span>
                <span className="font-mono text-slate-200">
                  CF: <strong className="text-sky-400">{richPark.cf}&apos;</strong> ({richPark.wallHeightCf}&apos; wall)
                </span>
                <span className="text-slate-600">•</span>
                <span className="font-mono text-slate-200">
                  RCF: <strong className="text-sky-400">{richPark.rcf}&apos;</strong>
                </span>
                <span className="text-slate-600">•</span>
                <span className="font-mono text-slate-200">
                  RF: <strong className="text-sky-400">{richPark.rf}&apos;</strong> ({richPark.wallHeightRf}&apos; wall)
                </span>
              </div>
              <div className="flex items-center gap-2 text-[11px] text-slate-400 border-t border-slate-800/60 pt-1.5 flex-wrap">
                <span className="text-amber-400 font-semibold flex items-center gap-1">
                  <MapPin className="w-3 h-3 text-amber-400" />
                  {richPark.parkName} ({richPark.cityState})
                </span>
                <span className="text-slate-600">•</span>
                <span>{richPark.roofType}</span>
                <span className="text-slate-600">•</span>
                <span>{richPark.surface}</span>
                <span className="text-slate-600">•</span>
                <span className="text-slate-300">{richPark.iconicFeatures.join(' • ')}</span>
              </div>
            </div>
          </div>

          {/* Main Visualizer Grid */}
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* SVG Spray Field (8 cols) */}
            <div className="lg:col-span-8 bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl flex flex-col items-center relative">
              <div className="w-full flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-bold text-white">
                    Statcast Batted Ball Scatter Plot
                  </span>
                  <span className="text-xs text-slate-400 font-mono">
                    ({filteredBalls.length} balls displayed)
                  </span>
                </div>
                <div className="flex items-center gap-3 text-[11px]">
                  <span className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-rose-500" /> HR
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-amber-500" /> 3B
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-emerald-500" /> 2B
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-sky-400" /> 1B
                  </span>
                  <span className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-slate-500" /> Out
                  </span>
                </div>
              </div>

              {/* Baseball Diamond SVG */}
              <div className="w-full max-w-[540px] aspect-[500/480] relative">
                <svg
                  viewBox={`0 0 ${spraySvgWidth} ${spraySvgHeight}`}
                  className="w-full h-full select-none"
                >
                  <defs>
                    <radialGradient id="fieldGrad" cx="50%" cy="90%" r="90%">
                      <stop offset="0%" stopColor="#0f172a" />
                      <stop offset="100%" stopColor="#020617" />
                    </radialGradient>
                    <radialGradient id="ballparkGrassTier1" cx="50%" cy="90%" r="90%">
                      <stop offset="0%" stopColor="#064e3b" stopOpacity="0.45" />
                      <stop offset="65%" stopColor="#022c22" stopOpacity="0.75" />
                      <stop offset="100%" stopColor="#091422" stopOpacity="0.9" />
                    </radialGradient>
                    <radialGradient id="warningTrackTier1" cx="50%" cy="85%" r="85%">
                      <stop offset="0%" stopColor="#92400e" stopOpacity="0.6" />
                      <stop offset="100%" stopColor="#713f12" stopOpacity="0.85" />
                    </radialGradient>
                    <radialGradient id="ballparkDirtTier1" cx="50%" cy="75%" r="75%">
                      <stop offset="0%" stopColor="#78350f" stopOpacity="0.45" />
                      <stop offset="100%" stopColor="#451a03" stopOpacity="0.65" />
                    </radialGradient>
                    <filter id="wallGlowTier1" x="-20%" y="-20%" width="140%" height="140%">
                      <feDropShadow dx="0" dy="2" stdDeviation="3" floodColor="#38bdf8" floodOpacity="0.4" />
                    </filter>
                    <filter id="highWallGlowTier1" x="-20%" y="-20%" width="140%" height="140%">
                      <feDropShadow dx="0" dy="3" stdDeviation="4" floodColor="#f59e0b" floodOpacity="0.6" />
                    </filter>
                  </defs>

                  {/* Field Background Canvas */}
                  <rect
                    width={spraySvgWidth}
                    height={spraySvgHeight}
                    fill="url(#fieldGrad)"
                    rx="16"
                  />

                  {/* Foul Ground & Backstop Geometry */}
                  <path
                    d={parkSvgData.backstopPolygon}
                    fill="#0f172a"
                    stroke="#1e293b"
                    strokeWidth="1.2"
                  />

                  {/* Fair Territory Solid Grass Polygon (Exact shape of the outfield wall) */}
                  <path
                    d={parkSvgData.fairTerritoryPolygon}
                    fill="url(#ballparkGrassTier1)"
                    stroke="#1e293b"
                    strokeWidth="1"
                  />

                  {/* Warning Track Ribbon (15 ft buffer inward along the wall contour) */}
                  <path
                    d={parkSvgData.warningTrackPolygon}
                    fill="url(#warningTrackTier1)"
                    stroke="#b45309"
                    strokeWidth="0.8"
                    opacity="0.85"
                  />

                  {/* Foul lines */}
                  {parkSvgData.wallPoints.length > 0 && (
                    <>
                      <line
                        x1={homeX}
                        y1={homeY}
                        x2={parkSvgData.wallPoints[0].x}
                        y2={parkSvgData.wallPoints[0].y}
                        stroke="#e2e8f0"
                        strokeWidth="1.5"
                      />
                      <line
                        x1={homeX}
                        y1={homeY}
                        x2={parkSvgData.wallPoints[parkSvgData.wallPoints.length - 1].x}
                        y2={parkSvgData.wallPoints[parkSvgData.wallPoints.length - 1].y}
                        stroke="#e2e8f0"
                        strokeWidth="1.5"
                      />
                      {/* Yellow Foul Poles */}
                      <circle
                        cx={parkSvgData.wallPoints[0].x}
                        cy={parkSvgData.wallPoints[0].y}
                        r="4"
                        fill="#fbbf24"
                        stroke="#d97706"
                        strokeWidth="1.5"
                      />
                      <circle
                        cx={parkSvgData.wallPoints[parkSvgData.wallPoints.length - 1].x}
                        cy={parkSvgData.wallPoints[parkSvgData.wallPoints.length - 1].y}
                        r="4"
                        fill="#fbbf24"
                        stroke="#d97706"
                        strokeWidth="1.5"
                      />
                    </>
                  )}

                  {/* Distance Rings: 200ft, 300ft, 400ft */}
                  {[200, 300, 400].map((ft) => {
                    const r = ft * scale;
                    return (
                      <g key={ft}>
                        <path
                          d={`M ${homeX - r * Math.sin(Math.PI / 4)} ${homeY - r * Math.cos(Math.PI / 4)} A ${r} ${r} 0 0 1 ${homeX + r * Math.sin(Math.PI / 4)} ${homeY - r * Math.cos(Math.PI / 4)}`}
                          fill="none"
                          stroke="#1e293b"
                          strokeWidth="1"
                          strokeDasharray="2 4"
                        />
                        <text
                          x={homeX + 5}
                          y={homeY - r + 12}
                          fill="#475569"
                          fontSize="9"
                          fontFamily="monospace"
                        >
                          {ft} ft
                        </text>
                      </g>
                    );
                  })}

                  {/* Infield dirt arc */}
                  <path
                    d={`M ${homeX - 110} ${homeY - 110} A 155 155 0 0 1 ${homeX + 110} ${homeY - 110} L ${homeX} ${homeY} Z`}
                    fill="url(#ballparkDirtTier1)"
                    stroke="#334155"
                    strokeWidth="1"
                  />

                  {/* Historic Keyhole Dirt Strip (if park.hasKeyholeDirt e.g. ARI, DET) */}
                  {richPark.hasKeyholeDirt && (
                    <path
                      d={`M ${homeX - 4.5} ${homeY - 12} L ${homeX - 4.5} ${homeY - 55} L ${homeX + 4.5} ${homeY - 55} L ${homeX + 4.5} ${homeY - 12} Z`}
                      fill="#78350f"
                      stroke="#92400e"
                      strokeWidth="0.8"
                      opacity="0.9"
                    />
                  )}

                  {/* Infield Diamond (90-ft basepaths scaled: ~80 px) */}
                  <polygon
                    points={`${homeX},${homeY} ${homeX + 55},${homeY - 55} ${homeX},${homeY - 110} ${homeX - 55},${homeY - 55}`}
                    fill="#020617"
                    fillOpacity="0.6"
                    stroke="#64748b"
                    strokeWidth="1.2"
                  />

                  {/* Pitcher's Mound & Rubber */}
                  <circle
                    cx={homeX}
                    cy={homeY - 55.6}
                    r="5.5"
                    fill="#78350f"
                    stroke="#b45309"
                    strokeWidth="1"
                  />
                  <rect
                    x={homeX - 2.2}
                    y={homeY - 56.6}
                    width="4.4"
                    height="1.5"
                    fill="#f8fafc"
                  />

                  {/* Bases (1B, 2B, 3B diamonds) */}
                  <rect
                    x={homeX + 52.5}
                    y={homeY - 57.5}
                    width="5.5"
                    height="5.5"
                    fill="#f8fafc"
                    transform={`rotate(45 ${homeX + 55} ${homeY - 55})`}
                  />
                  <rect
                    x={homeX - 2.75}
                    y={homeY - 112.75}
                    width="5.5"
                    height="5.5"
                    fill="#f8fafc"
                    transform={`rotate(45 ${homeX} ${homeY - 110})`}
                  />
                  <rect
                    x={homeX - 57.5}
                    y={homeY - 57.5}
                    width="5.5"
                    height="5.5"
                    fill="#f8fafc"
                    transform={`rotate(45 ${homeX - 55} ${homeY - 55})`}
                  />

                  {/* Home Plate Icon */}
                  <polygon
                    points={`${homeX},${homeY} ${homeX - 5},${homeY + 4} ${homeX - 5},${homeY + 8} ${homeX + 5},${homeY + 8} ${homeX + 5},${homeY + 4}`}
                    fill="#f8fafc"
                  />

                  {/* Multi-Segment Outfield Wall Base Path */}
                  <path
                    d={parkSvgData.wallPath}
                    fill="none"
                    stroke="#0284c7"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    filter="url(#wallGlowTier1)"
                  />

                  {/* High Wall 3D Extrusion Segments (e.g. Green Monster, Clemente Wall, McCovey Cove) */}
                  {parkSvgData.highWallSegments.map((seg, idx) => (
                    <g key={idx}>
                      <line
                        x1={seg.x1}
                        y1={seg.y1}
                        x2={seg.x2}
                        y2={seg.y2}
                        stroke="#f59e0b"
                        strokeWidth="4.5"
                        strokeLinecap="square"
                        filter="url(#highWallGlowTier1)"
                      />
                      <line
                        x1={seg.x1}
                        y1={seg.y1}
                        x2={seg.x2}
                        y2={seg.y2}
                        stroke="#fef08a"
                        strokeWidth="2"
                        strokeLinecap="round"
                      />
                    </g>
                  ))}

                  {/* Ballpark Wall Distance & Landmark Labels */}
                  {parkSvgData.wallPoints
                    .filter((p) => p.isKeyMarker || p.label)
                    .map((p, idx) => {
                      const isHigh = p.wallHeight >= 14;
                      return (
                        <g key={idx}>
                          <circle
                            cx={p.x}
                            cy={p.y}
                            r={isHigh ? 4 : 3}
                            fill={isHigh ? '#f59e0b' : '#38bdf8'}
                            stroke="#ffffff"
                            strokeWidth="1.2"
                          />
                          {p.label && (
                            <text
                              x={p.x + (p.angle > 0 ? 6 : p.angle < 0 ? -6 : 0)}
                              y={p.y - 7}
                              textAnchor={p.angle > 10 ? 'start' : p.angle < -10 ? 'end' : 'middle'}
                              fill={isHigh ? '#fbbf24' : '#7dd3fc'}
                              fontSize="8.5"
                              fontFamily="monospace"
                              fontWeight="bold"
                            >
                              {p.label}
                            </text>
                          )}
                        </g>
                      );
                    })}


                  {/* Batted Ball Points */}
                  {filteredBalls.map((ball, idx) => {
                    // Coordinate transform
                    const cx = homeX + ball.d_x * scale;
                    const cy = homeY - ball.d_y * scale;
                    const isHR = ball.hit_type === 'Home Run';
                    const isSelected = selectedBall === ball;

                    return (
                      <g
                        key={idx}
                        className="cursor-pointer transition-transform hover:scale-125"
                        onClick={() => setSelectedBall(ball)}
                      >
                        {isHR && (
                          <circle
                            cx={cx}
                            cy={cy}
                            r={isSelected ? 9 : 6}
                            fill="none"
                            stroke="#f43f5e"
                            strokeWidth="1.5"
                            className="animate-pulse opacity-75"
                          />
                        )}
                        <circle
                          cx={cx}
                          cy={cy}
                          r={isSelected ? 6 : isHR ? 4.5 : 3.2}
                          fill={getHitColor(ball.hit_type)}
                          stroke={isSelected ? '#ffffff' : '#090d16'}
                          strokeWidth={isSelected ? 1.5 : 0.7}
                          opacity={isSelected ? 1 : 0.85}
                        />
                      </g>
                    );
                  })}
                </svg>
              </div>

              <div className="w-full flex items-center justify-between text-xs text-slate-400 mt-2 px-2">
                <span>Click any ball to inspect exit velocity, launch angle & 30-park HR check.</span>
                <span className="font-mono text-sky-400">
                  {selectedPark} Wall: LF {activeParkDim.lf}&apos; • CF {activeParkDim.cf}&apos; • RF {activeParkDim.rf}&apos;
                </span>
              </div>
            </div>

            {/* Inspector & HR in 30 Parks Panel (4 cols) */}
            <div className="lg:col-span-4 space-y-4">
              {/* Ball Inspector Card */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl">
                <div className="flex items-center justify-between mb-3 border-b border-slate-800 pb-2.5">
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <Crosshair className="w-4 h-4 text-sky-400" />
                    Batted Ball Telemetry
                  </h3>
                  {selectedBall && (
                    <span
                      className="px-2 py-0.5 rounded text-[11px] font-bold uppercase tracking-wider"
                      style={{
                        backgroundColor: `${getHitColor(selectedBall.hit_type)}20`,
                        color: getHitColor(selectedBall.hit_type),
                      }}
                    >
                      {selectedBall.hit_type}
                    </span>
                  )}
                </div>

                {selectedBall ? (
                  <div className="space-y-4">
                    <div>
                      <div className="text-lg font-black text-white">
                        {selectedBall.batter_name}
                      </div>
                      <div className="text-xs text-slate-400 flex items-center gap-2">
                        <span>{selectedBall.team}</span>
                        <span>•</span>
                        <span>{selectedBall.stand === 'L' ? 'Left-Handed Batter' : 'Right-Handed Batter'}</span>
                      </div>
                    </div>

                    {/* Stat Grid */}
                    <div className="grid grid-cols-2 gap-2 text-xs">
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Exit Velocity</div>
                        <div className="text-base font-bold text-white font-mono mt-0.5">
                          {selectedBall.exit_velocity.toFixed(1)} <span className="text-xs text-slate-400">mph</span>
                        </div>
                      </div>
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Launch Angle</div>
                        <div className="text-base font-bold text-white font-mono mt-0.5">
                          {selectedBall.launch_angle}°
                        </div>
                      </div>
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Est. Distance</div>
                        <div className="text-base font-bold text-sky-400 font-mono mt-0.5">
                          {selectedBall.dist.toFixed(0)} <span className="text-xs text-slate-400">ft</span>
                        </div>
                      </div>
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Spray Bearing</div>
                        <div className="text-base font-bold text-slate-200 font-mono mt-0.5">
                          {selectedBall.bearing > 0 ? `+${selectedBall.bearing.toFixed(1)}°` : `${selectedBall.bearing.toFixed(1)}°`}
                        </div>
                      </div>
                    </div>

                    {/* HR in X Parks Progress Bar */}
                    <div className="bg-slate-950 border border-slate-800 rounded-xl p-3">
                      <div className="flex items-center justify-between text-xs mb-1.5">
                        <span className="font-semibold text-slate-300">Home Run in 30 Parks</span>
                        <span className="font-mono font-bold text-rose-400">
                          {selectedBall.parks_hr_count} / 30 ({selectedBall.parks_hr_pct}%)
                        </span>
                      </div>
                      <div className="w-full bg-slate-800 h-2 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-gradient-to-r from-amber-500 to-rose-500 rounded-full transition-all duration-300"
                          style={{ width: `${selectedBall.parks_hr_pct}%` }}
                        />
                      </div>
                      <p className="text-[11px] text-slate-400 mt-2">
                        {selectedBall.parks_hr_count === 30
                          ? '🔥 No-doubter: Out of every single MLB ballpark.'
                          : selectedBall.parks_hr_count > 0
                          ? `Park Dependent: HR in ${selectedBall.parks_hr_count} parks, flyout or wall hit in ${30 - selectedBall.parks_hr_count}.`
                          : 'Not a home run in any MLB venue.'}
                      </p>
                    </div>
                  </div>
                ) : (
                  <div className="py-12 text-center text-slate-500 text-xs">
                    <Crosshair className="w-8 h-8 mx-auto mb-2 opacity-40 text-slate-400" />
                    Click any batted ball in the spray chart to inspect its trajectory and 30-park HR count.
                  </div>
                )}
              </div>

              {/* Top 30-Park Expected HR Leaders */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-xl">
                <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider mb-2.5 flex items-center justify-between">
                  <span>Sample HR Leaders</span>
                  <span className="text-[10px] text-slate-500">Actual vs 30-Pk Exp</span>
                </h4>
                <div className="space-y-2">
                  {data.tier1_spray.hr_hitters.slice(0, 5).map((hitter) => (
                    <div
                      key={hitter.batter_id}
                      className="bg-slate-950/70 border border-slate-800/80 rounded-lg p-2.5 flex items-center justify-between text-xs"
                    >
                      <div className="min-w-0 pr-2">
                        <div className="font-semibold text-white truncate">{hitter.batter_name}</div>
                        <div className="text-[11px] text-slate-400">
                          {hitter.team} • Max {hitter.max_dist} ft ({hitter.max_ev} mph)
                        </div>
                      </div>
                      <div className="text-right font-mono flex-shrink-0">
                        <div className="text-rose-400 font-bold">{hitter.actual_hrs} HR</div>
                        <div className="text-[10px] text-slate-500">
                          {hitter.expected_hrs_30_park_avg.toFixed(1)} xHR
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================================= */}
      {/* TAB 2: STRIKE ZONE HEATMAP & FRAMING                                     */}
      {/* ========================================================================= */}
      {activeTab === 'zone' && (
        <div className="space-y-6">
          {/* Controls Bar */}
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                Heatmap Metric:
              </span>
              <div className="flex rounded-lg bg-slate-950 border border-slate-800 p-0.5">
                {[
                  { id: 'whiff', label: 'Whiff Rate %' },
                  { id: 'swing', label: 'Swing Rate %' },
                  { id: 'calledStrike', label: 'Called Strike %' },
                  { id: 'pct', label: 'Pitch Frequency %' },
                ].map((m) => (
                  <button
                    key={m.id}
                    onClick={() => setZoneMetric(m.id as 'pct' | 'swing' | 'whiff' | 'calledStrike')}
                    className={`px-3 py-1 text-xs font-semibold rounded-md transition-colors ${
                      zoneMetric === m.id
                        ? 'bg-emerald-600 text-white'
                        : 'text-slate-400 hover:text-white'
                    }`}
                  >
                    {m.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="text-xs text-slate-400">
              Perspective: <strong className="text-slate-200">Catcher / Umpire View</strong> (Plate: ±0.85 ft, Height: 1.5 - 3.5 ft)
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* 3x3 Strike Zone SVG (7 cols) */}
            <div className="lg:col-span-7 bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-xl flex flex-col items-center">
              <div className="w-full flex items-center justify-between mb-4">
                <span className="text-sm font-bold text-white flex items-center gap-2">
                  <Crosshair className="w-4 h-4 text-sky-400" />
                  Statcast 3×3 Strike Zone Grid
                </span>
                <span className="text-xs text-slate-400">
                  Showing: <strong className="text-sky-400 capitalize">{zoneMetric}</strong>
                </span>
              </div>

              {/* SVG 3x3 Grid */}
              <div className="w-full max-w-[420px] aspect-square relative">
                <svg viewBox="0 0 400 400" className="w-full h-full select-none">
                  {/* Home Plate Indicator at Bottom */}
                  <polygon
                    points="200,380 180,365 180,355 220,355 220,365"
                    fill="#334155"
                    stroke="#475569"
                    strokeWidth="1"
                  />
                  <text
                    x="200"
                    y="395"
                    fill="#64748b"
                    fontSize="9"
                    textAnchor="middle"
                    fontFamily="monospace"
                  >
                    HOME PLATE (CATCHER VIEW)
                  </text>

                  {/* Outer Shadow Zone Ring */}
                  <rect
                    x="40"
                    y="40"
                    width="320"
                    height="300"
                    fill="#0f172a"
                    stroke="#334155"
                    strokeWidth="2"
                    strokeDasharray="4 4"
                    rx="8"
                  />
                  <text
                    x="200"
                    y="30"
                    fill="#64748b"
                    fontSize="10"
                    fontWeight="bold"
                    textAnchor="middle"
                  >
                    SHADOW ZONE (±2&quot; BORDER)
                  </text>

                  {/* 3x3 Zone Grid Cells */}
                  {data.tier2_zone.zone_grid.map((cell) => {
                    // Cell layout:
                    // row 1: y=60, row 2: y=150, row 3: y=240
                    // col 1: x=60, col 2: x=150, col 3: x=240
                    const cellW = 86;
                    const cellH = 86;
                    const gap = 4;
                    const startX = 66;
                    const startY = 66;
                    const x = startX + (cell.col - 1) * (cellW + gap);
                    const y = startY + (cell.row - 1) * (cellH + gap);

                    // Compute metric value
                    let val = 0;
                    let displayVal = '';
                    if (zoneMetric === 'whiff') {
                      val = cell.whiff_rate;
                      displayVal = `${val.toFixed(1)}%`;
                    } else if (zoneMetric === 'swing') {
                      val = cell.swing_rate;
                      displayVal = `${val.toFixed(1)}%`;
                    } else if (zoneMetric === 'calledStrike') {
                      val = cell.called_strike_rate;
                      displayVal = `${val.toFixed(1)}%`;
                    } else {
                      val = cell.pct_of_zone;
                      displayVal = `${val.toFixed(1)}%`;
                    }

                    // Dynamic heat color
                    let heatColor = '#1e293b';
                    if (zoneMetric === 'whiff') {
                      // High whiff = rose/purple
                      const alpha = Math.min(Math.max((val - 10) / 25, 0.15), 0.85);
                      heatColor = `rgba(244, 63, 94, ${alpha})`;
                    } else if (zoneMetric === 'swing') {
                      // High swing = sky/blue
                      const alpha = Math.min(Math.max((val - 50) / 30, 0.15), 0.85);
                      heatColor = `rgba(56, 189, 248, ${alpha})`;
                    } else if (zoneMetric === 'calledStrike') {
                      // High called strike = emerald
                      const alpha = Math.min(Math.max((val - 20) / 20, 0.15), 0.85);
                      heatColor = `rgba(16, 185, 129, ${alpha})`;
                    } else {
                      // Frequency
                      const alpha = Math.min(Math.max((val - 5) / 12, 0.15), 0.85);
                      heatColor = `rgba(99, 102, 241, ${alpha})`;
                    }

                    const isSelected = selectedZone?.zone_index === cell.zone_index;

                    return (
                      <g
                        key={cell.zone_index}
                        className="cursor-pointer transition-all duration-200"
                        onClick={() => setSelectedZone(cell)}
                      >
                        <rect
                          x={x}
                          y={y}
                          width={cellW}
                          height={cellH}
                          fill={heatColor}
                          stroke={isSelected ? '#38bdf8' : '#334155'}
                          strokeWidth={isSelected ? 2.5 : 1}
                          rx="6"
                        />
                        <text
                          x={x + cellW / 2}
                          y={y + 32}
                          fill="#ffffff"
                          fontSize="13"
                          fontWeight="bold"
                          textAnchor="middle"
                          fontFamily="monospace"
                        >
                          {displayVal}
                        </text>
                        <text
                          x={x + cellW / 2}
                          y={y + 50}
                          fill="#94a3b8"
                          fontSize="10"
                          textAnchor="middle"
                        >
                          {cell.label}
                        </text>
                        <text
                          x={x + cellW / 2}
                          y={y + 68}
                          fill="#64748b"
                          fontSize="9"
                          textAnchor="middle"
                          fontFamily="monospace"
                        >
                          {cell.pitch_count} pitches
                        </text>
                      </g>
                    );
                  })}
                </svg>
              </div>

              <div className="w-full flex items-center justify-between text-xs text-slate-400 mt-2 px-4">
                <span>Left Side = Inside to RHH / Outside to LHH</span>
                <span>Right Side = Outside to RHH / Inside to LHH</span>
              </div>
            </div>

            {/* Zone Telemetry & Catcher Framing Details (5 cols) */}
            <div className="lg:col-span-5 space-y-4">
              {/* Selected Zone Card */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl">
                <div className="flex items-center justify-between mb-3 border-b border-slate-800 pb-2">
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <Crosshair className="w-4 h-4 text-sky-400" />
                    Zone Cell Telemetry
                  </h3>
                  {selectedZone && (
                    <span className="px-2 py-0.5 rounded bg-sky-500/10 border border-sky-500/20 text-sky-400 font-mono text-xs font-bold">
                      {selectedZone.label}
                    </span>
                  )}
                </div>

                {selectedZone ? (
                  <div className="space-y-3">
                    <div className="grid grid-cols-2 gap-2 text-xs">
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Pitch Count</div>
                        <div className="text-base font-bold text-white font-mono mt-0.5">
                          {selectedZone.pitch_count}{' '}
                          <span className="text-xs text-slate-400">({selectedZone.pct_of_zone}%)</span>
                        </div>
                      </div>
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Whiff Rate</div>
                        <div className="text-base font-bold text-rose-400 font-mono mt-0.5">
                          {selectedZone.whiff_rate}%
                        </div>
                      </div>
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Swing Rate</div>
                        <div className="text-base font-bold text-sky-400 font-mono mt-0.5">
                          {selectedZone.swing_rate}%
                        </div>
                      </div>
                      <div className="bg-slate-950 p-2.5 rounded-lg border border-slate-800">
                        <div className="text-slate-400 text-[10px] uppercase font-semibold">Called Strike %</div>
                        <div className="text-base font-bold text-emerald-400 font-mono mt-0.5">
                          {selectedZone.called_strike_rate}%
                        </div>
                      </div>
                    </div>

                    <div className="text-[11px] text-slate-400 bg-slate-950 p-3 rounded-xl border border-slate-800 font-mono">
                      Coordinates: X [{selectedZone.x_min.toFixed(2)}, {selectedZone.x_max.toFixed(2)}] ft • Z [{selectedZone.z_min.toFixed(2)}, {selectedZone.z_max.toFixed(2)}] ft
                    </div>
                  </div>
                ) : (
                  <div className="py-6 text-center text-slate-500 text-xs">
                    Click any 3×3 zone cell above to view detailed swing and whiff breakdowns.
                  </div>
                )}
              </div>

              {/* Catcher Framing Deep-Dive Card */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl">
                <div className="flex items-center gap-2 mb-3 border-b border-slate-800 pb-2">
                  <Shield className="w-4 h-4 text-indigo-400" />
                  <h3 className="text-sm font-bold text-white">
                    Shadow Zone & Catcher Framing
                  </h3>
                </div>

                <p className="text-xs text-slate-400 mb-4 leading-relaxed">
                  The <strong className="text-slate-200">Shadow Zone</strong> is defined as a 2-inch borderline halo surrounding the rulebook strike zone. Over 90% of catcher framing run value is won or lost here on taken pitches.
                </p>

                <div className="grid grid-cols-2 gap-3 text-xs mb-4">
                  <div className="bg-slate-950 p-3 rounded-xl border border-slate-800">
                    <div className="text-slate-400 text-[10px] uppercase font-semibold">Taken Borderline Pitches</div>
                    <div className="text-lg font-black text-white font-mono mt-0.5">
                      {data.tier2_zone.framing_summary.total_shadow_taken.toLocaleString()}
                    </div>
                    <div className="text-[10px] text-slate-500 mt-0.5">Statcast sample</div>
                  </div>
                  <div className="bg-slate-950 p-3 rounded-xl border border-slate-800">
                    <div className="text-slate-400 text-[10px] uppercase font-semibold">Called Strike Rate</div>
                    <div className="text-lg font-black text-indigo-400 font-mono mt-0.5">
                      {data.tier2_zone.framing_summary.shadow_strike_rate}%
                    </div>
                    <div className="text-[10px] text-slate-500 mt-0.5">
                      Baseline: {data.tier2_zone.framing_summary.league_baseline_rate}%
                    </div>
                  </div>
                </div>

                <div className="bg-slate-950 p-3 rounded-xl border border-slate-800 space-y-2 text-xs">
                  <div className="flex items-center justify-between">
                    <span className="text-slate-400">Called Strikes Stolen:</span>
                    <span className="font-mono font-bold text-emerald-400">
                      {data.tier2_zone.framing_summary.called_strikes}
                    </span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-slate-400">Called Balls:</span>
                    <span className="font-mono font-bold text-slate-400">
                      {data.tier2_zone.framing_summary.called_balls}
                    </span>
                  </div>
                  <div className="flex items-center justify-between pt-1 border-t border-slate-800/80">
                    <span className="text-slate-400">Run Value Conversion:</span>
                    <span className="font-mono font-bold text-sky-400">+0.125 runs / strike</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================================= */}
      {/* TAB 3: PITCH MOVEMENT (IVB vs. HB)                                        */}
      {/* ========================================================================= */}
      {activeTab === 'movement' && (
        <div className="space-y-6">
          {/* Controls Bar */}
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <label className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                Drill Down Pitcher Arsenal:
              </label>
              <select
                value={selectedPitcherId}
                onChange={(e) => setSelectedPitcherId(Number(e.target.value))}
                className="bg-slate-950 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:ring-1 focus:ring-sky-500"
              >
                {data.tier3_movement.pitcher_arsenals.map((pitcher) => (
                  <option key={pitcher.pitcher_id} value={pitcher.pitcher_id}>
                    {pitcher.pitcher_name} ({pitcher.team} - {pitcher.hand}HP) - {pitcher.total_pitches} pitches
                  </option>
                ))}
              </select>
            </div>

            <div className="text-xs text-slate-400">
              Crosshair at <strong className="text-slate-200">(0, 0)</strong> represents zero-spin gravity path
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* IVB vs HB 2D Scatter Chart (7 cols) */}
            <div className="lg:col-span-7 bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-xl flex flex-col items-center">
              <div className="w-full flex items-center justify-between mb-2">
                <span className="text-sm font-bold text-white flex items-center gap-2">
                  <Activity className="w-4 h-4 text-sky-400" />
                  Movement Profile (Induced Vertical vs. Horizontal Break)
                </span>
                <span className="text-xs text-slate-400 font-mono">Inches (&quot;)</span>
              </div>

              {/* Movement SVG Chart */}
              <div className="w-full max-w-[460px] aspect-square relative">
                <svg viewBox="0 0 440 440" className="w-full h-full select-none">
                  {/* Background */}
                  <rect width="440" height="440" fill="#090d16" rx="12" />

                  {/* Grid Lines (-20 to +20 inches) */}
                  {/* Center is at (220, 220). Scale: 1 inch = 9 pixels */}
                  {/* X-axis: -20" to +20". Y-axis: -20" to +20" */}
                  {[-15, -10, -5, 5, 10, 15].map((val) => {
                    const x = 220 + val * 9;
                    const y = 220 - val * 9;
                    return (
                      <g key={val}>
                        <line x1={x} y1="20" x2={x} y2="420" stroke="#1e293b" strokeWidth="0.8" />
                        <line x1="20" y1={y} x2="420" y2={y} stroke="#1e293b" strokeWidth="0.8" />
                        <text x={x} y="432" fill="#475569" fontSize="8" textAnchor="middle" fontFamily="monospace">
                          {val}&quot;
                        </text>
                        <text x="12" y={y + 3} fill="#475569" fontSize="8" textAnchor="middle" fontFamily="monospace">
                          {val}&quot;
                        </text>
                      </g>
                    );
                  })}

                  {/* Zero Axes (Gravity Baseline) */}
                  <line x1="20" y1="220" x2="420" y2="220" stroke="#475569" strokeWidth="1.5" />
                  <line x1="220" y1="20" x2="220" y2="420" stroke="#475569" strokeWidth="1.5" />

                  {/* Axis Quadrant Labels */}
                  <text x="410" y="215" fill="#64748b" fontSize="9" textAnchor="end">
                    +Glove Break →
                  </text>
                  <text x="30" y="215" fill="#64748b" fontSize="9">
                    ← +Arm Run
                  </text>
                  <text x="225" y="32" fill="#64748b" fontSize="9">
                    ↑ Hop / Rising (IVB)
                  </text>
                  <text x="225" y="415" fill="#64748b" fontSize="9">
                    ↓ Heavy Drop (Sink/Curve)
                  </text>

                  {/* League Pitch Type Averages */}
                  {data.tier3_movement.league_pitch_types.map((p) => {
                    const cx = 220 + p.hb * 9;
                    const cy = 220 - p.ivb * 9;
                    const color = getPitchColor(p.pitch_type);
                    const isSelected = selectedPitchType === p.pitch_type;

                    return (
                      <g
                        key={p.pitch_type}
                        className="cursor-pointer"
                        onClick={() => setSelectedPitchType(p.pitch_type)}
                      >
                        {/* SD Circle */}
                        <circle
                          cx={cx}
                          cy={cy}
                          r={p.hb_sd * 5}
                          fill={color}
                          opacity={isSelected ? 0.35 : 0.15}
                        />
                        {/* Main Dot */}
                        <circle
                          cx={cx}
                          cy={cy}
                          r={isSelected ? 8 : 6}
                          fill={color}
                          stroke="#090d16"
                          strokeWidth="1.5"
                        />
                        <text
                          x={cx}
                          y={cy - 10}
                          fill="#ffffff"
                          fontSize="10"
                          fontWeight="bold"
                          textAnchor="middle"
                          fontFamily="monospace"
                        >
                          {p.pitch_type}
                        </text>
                      </g>
                    );
                  })}
                </svg>
              </div>

              {/* Pitch Type Legend Pills */}
              <div className="w-full flex flex-wrap items-center justify-center gap-2 mt-4">
                {data.tier3_movement.league_pitch_types.map((p) => {
                  const color = getPitchColor(p.pitch_type);
                  const isSelected = selectedPitchType === p.pitch_type;
                  return (
                    <button
                      key={p.pitch_type}
                      onClick={() =>
                        setSelectedPitchType(
                          isSelected ? null : p.pitch_type
                        )
                      }
                      className={`flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold border transition-all ${
                        isSelected
                          ? 'bg-slate-800 border-white text-white'
                          : 'bg-slate-950 border-slate-800 text-slate-400 hover:text-white'
                      }`}
                    >
                      <span
                        className="w-2.5 h-2.5 rounded-full"
                        style={{ backgroundColor: color }}
                      />
                      <span>{p.pitch_type} ({p.name})</span>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Pitcher Arsenal Drill-Down & Table (5 cols) */}
            <div className="lg:col-span-5 space-y-4">
              {/* Pitcher 3D Release Footprint */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl">
                <div className="flex items-center justify-between mb-3 border-b border-slate-800 pb-2.5">
                  <div className="flex items-center gap-3">
                    <TeamLogo team={activePitcher.team} className="w-7 h-7" />
                    <div>
                      <h3 className="text-base font-bold text-white leading-none">
                        {activePitcher.pitcher_name}
                      </h3>
                      <p className="text-xs text-slate-400 mt-1">
                        {activePitcher.team} • {activePitcher.hand}HP • {activePitcher.total_pitches} Pitches Tracked
                      </p>
                    </div>
                  </div>
                  <span className="px-2.5 py-1 rounded bg-sky-500/10 text-sky-400 border border-sky-500/20 text-xs font-bold font-mono">
                    {activePitcher.pitches.length} Pitches
                  </span>
                </div>

                <div className="grid grid-cols-2 gap-2 text-xs mb-4">
                  <div className="bg-slate-950 p-2.5 rounded-xl border border-slate-800">
                    <div className="text-slate-400 text-[10px] uppercase font-semibold">Horiz Release (X)</div>
                    <div className="text-base font-bold text-white font-mono mt-0.5">
                      {activePitcher.avg_release_x > 0 ? `+${activePitcher.avg_release_x}` : activePitcher.avg_release_x} ft
                    </div>
                  </div>
                  <div className="bg-slate-950 p-2.5 rounded-xl border border-slate-800">
                    <div className="text-slate-400 text-[10px] uppercase font-semibold">Vertical Release (Z)</div>
                    <div className="text-base font-bold text-white font-mono mt-0.5">
                      {activePitcher.avg_release_z} ft
                    </div>
                  </div>
                </div>

                {/* Arsenal Breakdown Table */}
                <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider mb-2">
                  Pitch Mix & Shape
                </h4>
                <div className="space-y-2">
                  {activePitcher.pitches.map((p) => {
                    const color = getPitchColor(p.pitch_type);
                    const usagePct = ((p.count / activePitcher.total_pitches) * 100).toFixed(0);

                    return (
                      <div
                        key={p.pitch_type}
                        className="bg-slate-950/80 border border-slate-800/80 rounded-xl p-3 text-xs"
                      >
                        <div className="flex items-center justify-between mb-1.5">
                          <div className="flex items-center gap-2">
                            <span
                              className="w-3 h-3 rounded-full flex-shrink-0"
                              style={{ backgroundColor: color }}
                            />
                            <span className="font-bold text-white">{p.name}</span>
                            <span className="text-[11px] text-slate-400 font-mono">({usagePct}%)</span>
                          </div>
                          <span className="font-mono font-bold text-sky-400">
                            {p.velo.toFixed(1)} mph
                          </span>
                        </div>

                        <div className="grid grid-cols-3 gap-2 text-[11px] pt-1.5 border-t border-slate-900 font-mono">
                          <div>
                            <span className="text-slate-500">IVB: </span>
                            <span className="text-slate-200">{p.ivb > 0 ? `+${p.ivb}"` : `${p.ivb}"`}</span>
                          </div>
                          <div>
                            <span className="text-slate-500">HB: </span>
                            <span className="text-slate-200">{p.hb > 0 ? `+${p.hb}"` : `${p.hb}"`}</span>
                          </div>
                          <div className="text-right">
                            <span className="text-slate-500">Whiff: </span>
                            <span className="text-rose-400 font-bold">{p.whiff_rate}%</span>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ========================================================================= */}
      {/* TAB 4: DEFENSIVE POSITIONING & SHIFT BABIP PENALTY                         */}
      {/* ========================================================================= */}
      {activeTab === 'defense' && (
        <div className="space-y-6">
          {/* Header Banner */}
          <div className="bg-gradient-to-r from-sky-950/40 via-slate-900 to-indigo-950/40 border border-sky-500/20 rounded-2xl p-6 shadow-xl">
            <div className="flex items-start gap-3">
              <Shield className="w-6 h-6 text-sky-400 flex-shrink-0 mt-0.5" />
              <div>
                <h2 className="text-lg font-bold text-white">
                  2023+ MLB Shift Restrictions & Infield Geometry
                </h2>
                <p className="text-slate-300 text-sm mt-1 max-w-3xl leading-relaxed">
                  MLB Rule 6.02(c) mandates that defensive teams must have at least four infielders completely within the outer boundary of the infield dirt, with exactly two infielders entirely on either side of second base.
                </p>
                <div className="flex flex-wrap items-center gap-4 mt-3 text-xs font-mono">
                  <span className="px-3 py-1 rounded bg-sky-500/10 text-sky-400 border border-sky-500/20 font-bold">
                    Left-Handed Pull BABIP Delta: {data.tier4_defense.shift_rule_impact.lefty_pull_babip_gain}
                  </span>
                  <span className="px-3 py-1 rounded bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 font-bold">
                    Deep Outfield Shade Rate: {data.tier4_defense.shift_rule_impact.deep_outfield_shade_pct}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* Infield Sector Distribution (5 cols) */}
            <div className="lg:col-span-5 bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-xl">
              <h3 className="text-sm font-bold text-white mb-2 flex items-center gap-2">
                <Layers className="w-4 h-4 text-sky-400" />
                Infield Ground Ball Sector Frequency
              </h3>
              <p className="text-xs text-slate-400 mb-4">
                Distribution of balls hit into each defensive sector between [-45°, +45°].
              </p>

              <div className="space-y-3">
                {data.tier4_defense.infield_sectors.map((sec, idx) => {
                  const maxBalls = Math.max(...data.tier4_defense.infield_sectors.map((s) => s.balls));
                  const pct = ((sec.balls / maxBalls) * 100).toFixed(0);

                  return (
                    <div
                      key={idx}
                      className="bg-slate-950 p-3.5 rounded-xl border border-slate-800"
                    >
                      <div className="flex items-center justify-between text-xs mb-1.5">
                        <span className="font-bold text-white">{sec.sector}</span>
                        <span className="font-mono text-slate-400 text-[11px]">{sec.angle_range}</span>
                      </div>
                      <div className="w-full bg-slate-800 h-2 rounded-full overflow-hidden mb-2">
                        <div
                          className="h-full bg-gradient-to-r from-sky-500 to-indigo-500 rounded-full"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                      <div className="flex items-center justify-between text-[11px] text-slate-400 font-mono">
                        <span>Ground Balls: <strong className="text-white">{sec.balls}</strong></span>
                        <span className="text-sky-400">
                          {((sec.balls / 524) * 100).toFixed(1)}% of Infield Dirt
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Directional BABIP Grid (7 cols) */}
            <div className="lg:col-span-7 bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-xl">
              <h3 className="text-sm font-bold text-white mb-2 flex items-center gap-2">
                <TrendingUp className="w-4 h-4 text-emerald-400" />
                Directional BABIP & Spray Efficiency
              </h3>
              <p className="text-xs text-slate-400 mb-4">
                Empirical batting average on balls in play categorized by batter handedness and spray direction.
              </p>

              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs border-collapse">
                  <thead>
                    <tr className="border-b border-slate-800 text-[10px] uppercase font-bold text-slate-400">
                      <th className="py-2.5 px-3">Batter</th>
                      <th className="py-2.5 px-3">Direction</th>
                      <th className="py-2.5 px-3 text-right">Batted Balls</th>
                      <th className="py-2.5 px-3 text-right">Hits</th>
                      <th className="py-2.5 px-3 text-right">BABIP</th>
                      <th className="py-2.5 px-3 text-right">Avg EV</th>
                      <th className="py-2.5 px-3 text-right">Avg Dist</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60 font-mono">
                    {data.tier4_defense.directional_babip.map((row, idx) => {
                      const isHighBabip = row.babip >= 0.300;
                      return (
                        <tr key={idx} className="hover:bg-slate-800/30 transition-colors">
                          <td className="py-2.5 px-3 font-sans">
                            <span
                              className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                                row.stand === 'L'
                                  ? 'bg-sky-500/10 text-sky-400 border border-sky-500/20'
                                  : 'bg-indigo-500/10 text-indigo-400 border border-indigo-500/20'
                              }`}
                            >
                              {row.stand === 'L' ? 'LHH' : 'RHH'}
                            </span>
                          </td>
                          <td className="py-2.5 px-3 font-sans font-semibold text-white">
                            {row.spray_dir}
                          </td>
                          <td className="py-2.5 px-3 text-right text-slate-300">
                            {row.batted_balls}
                          </td>
                          <td className="py-2.5 px-3 text-right text-slate-300">
                            {row.hits}
                          </td>
                          <td className="py-2.5 px-3 text-right font-bold">
                            <span
                              className={`px-2 py-0.5 rounded text-[11px] ${
                                isHighBabip
                                  ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                                  : 'bg-slate-800 text-slate-300'
                              }`}
                            >
                              .{Math.round(row.babip * 1000).toString().padStart(3, '0')}
                            </span>
                          </td>
                          <td className="py-2.5 px-3 text-right text-slate-400">
                            {row.avg_ev.toFixed(1)} mph
                          </td>
                          <td className="py-2.5 px-3 text-right text-slate-400">
                            {row.avg_dist.toFixed(0)} ft
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              {/* Explanatory Callout */}
              <div className="mt-5 p-3.5 bg-slate-950 rounded-xl border border-slate-800 text-xs text-slate-400 space-y-1.5">
                <div className="font-semibold text-slate-200 flex items-center gap-1.5">
                  <Info className="w-3.5 h-3.5 text-sky-400" />
                  Tactical Shift Adaptation Note:
                </div>
                <p>
                  Since infielders can no longer shade onto the shallow right-field grass against pull-heavy LHH, front offices have repositioned right fielders 20–30 feet shallower to cut off line drives, resulting in the observed 71.4% outfield shade rate.
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
