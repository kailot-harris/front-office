'use client';

import React, { useState, useMemo } from 'react';
import { PlayerShotData, ShotsMetadata, ZoneMetric, ShotRecord } from '@/lib/shotTypes';
import {
  filterPriorNShots,
  computeZoneMetrics,
  computeOverallStats,
  generateHexbins,
  getThermalColor,
  getStatusBadge,
  getZoneDisplayName,
  toSvgX,
  toSvgY,
} from '@/lib/shotChartUtils';
import {
  Flame,
  Snowflake,
  Crosshair,
  Layers,
  CircleDot,
  Sliders,
} from 'lucide-react';

interface PlayerShotChartProps {
  playerData: PlayerShotData;
  metadata: ShotsMetadata;
  initialN?: number | 'all';
}

export const PlayerShotChart: React.FC<PlayerShotChartProps> = ({
  playerData,
  metadata,
  initialN = 100,
}) => {
  const [priorN, setPriorN] = useState<number | 'all'>(initialN);
  const [viewMode, setViewMode] = useState<'zones' | 'hex' | 'scatter'>('zones');
  const [hoveredShot, setHoveredShot] = useState<ShotRecord | null>(null);
  const [zoneFilter, setZoneFilter] = useState<'ALL' | 'HOT' | 'COLD' | 'NEUTRAL'>('ALL');

  // Filter shots by Prior N
  const activeShots = useMemo(() => {
    return filterPriorNShots(playerData.shots, priorN);
  }, [playerData.shots, priorN]);

  // Compute zone metrics over the active window
  const zoneMetrics = useMemo(() => {
    return computeZoneMetrics(activeShots, metadata.league_averages);
  }, [activeShots, metadata.league_averages]);

  // Filtered zone metrics for the breakdown panel
  const filteredZoneMetrics = useMemo(() => {
    if (zoneFilter === 'ALL') return zoneMetrics;
    return zoneMetrics.filter((zm) => zm.status === zoneFilter);
  }, [zoneMetrics, zoneFilter]);

  // Zone metrics map for fast lookup
  const zoneMetricsMap = useMemo(() => {
    const map = new Map<string, ZoneMetric>();
    for (const zm of zoneMetrics) {
      map.set(zm.zone, zm);
    }
    return map;
  }, [zoneMetrics]);

  // Overall shooting rollup
  const overall = useMemo(() => {
    return computeOverallStats(activeShots, zoneMetrics);
  }, [activeShots, zoneMetrics]);

  // Hexbins for hex view
  const hexbins = useMemo(() => {
    return generateHexbins(activeShots, 16);
  }, [activeShots]);

  // Preset window options
  const windowPresets = [
    { label: 'Last 25', value: 25 },
    { label: 'Last 50', value: 50 },
    { label: 'Last 100', value: 100 },
    { label: 'Last 250', value: 250 },
    { label: 'All Season', value: 'all' as const },
  ];

  return (
    <div className="space-y-6">
      {/* Top Controls Bar */}
      <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 flex flex-col md:flex-row items-center justify-between gap-4">
        {/* Prior N Window Controls */}
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-1.5 text-xs text-slate-400 font-semibold uppercase tracking-wider mr-1">
            <Sliders className="w-3.5 h-3.5 text-indigo-400" />
            <span>Prior Shots Window:</span>
          </div>
          <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
            {windowPresets.map((preset) => {
              const isSelected = priorN === preset.value;
              return (
                <button
                  key={preset.label}
                  onClick={() => setPriorN(preset.value)}
                  className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                    isSelected
                      ? 'bg-indigo-600 text-white shadow-md'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {preset.label}
                </button>
              );
            })}
          </div>
          <span className="text-xs text-slate-400 font-mono ml-1">
            ({activeShots.length} shots analyzed)
          </span>
        </div>

        {/* View Mode Switcher */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-slate-400 font-semibold uppercase tracking-wider">
            Display:
          </span>
          <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
            <button
              onClick={() => setViewMode('zones')}
              className={`flex items-center gap-1.5 px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                viewMode === 'zones'
                  ? 'bg-amber-600 text-white shadow-md'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              <Flame className="w-3.5 h-3.5" />
              <span>Hot / Cold Zones</span>
            </button>
            <button
              onClick={() => setViewMode('hex')}
              className={`flex items-center gap-1.5 px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                viewMode === 'hex'
                  ? 'bg-indigo-600 text-white shadow-md'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              <Layers className="w-3.5 h-3.5" />
              <span>Hex Density</span>
            </button>
            <button
              onClick={() => setViewMode('scatter')}
              className={`flex items-center gap-1.5 px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                viewMode === 'scatter'
                  ? 'bg-emerald-600 text-white shadow-md'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              <CircleDot className="w-3.5 h-3.5" />
              <span>Individual Scatter</span>
            </button>
          </div>
        </div>
      </div>

      {/* KPI Cards Overview */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-3">
          <div className="text-[10px] text-slate-400 uppercase font-semibold">Field Goal %</div>
          <div className="text-xl font-bold font-mono text-white">
            {(overall.fgPct * 100).toFixed(1)}%
          </div>
          <div className="text-[11px] text-slate-400">
            {overall.totalFgm} / {overall.totalFga} made
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-3">
          <div className="text-[10px] text-slate-400 uppercase font-semibold">Effective FG (eFG%)</div>
          <div className="text-xl font-bold font-mono text-indigo-400">
            {(overall.eFgPct * 100).toFixed(1)}%
          </div>
          <div className="text-[11px] text-slate-400">Weighted 3PT value</div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-3">
          <div className="text-[10px] text-slate-400 uppercase font-semibold">Rim Frequency</div>
          <div className="text-xl font-bold font-mono text-amber-400">
            {(overall.rimFreq * 100).toFixed(1)}%
          </div>
          <div className="text-[11px] text-slate-400">Restricted area</div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-3">
          <div className="text-[10px] text-slate-400 uppercase font-semibold">3-Point Frequency</div>
          <div className="text-xl font-bold font-mono text-cyan-400">
            {(overall.threeFreq * 100).toFixed(1)}%
          </div>
          <div className="text-[11px] text-slate-400">
            {overall.threeMade} / {overall.threeAtt} 3PM
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-3 flex items-center justify-between">
          <div>
            <div className="text-[10px] text-slate-400 uppercase font-semibold">Hot Zones</div>
            <div className="text-xl font-bold font-mono text-rose-400 flex items-center gap-1">
              <span>{overall.hotCount}</span>
              <Flame className="w-4 h-4 text-rose-500 animate-pulse" />
            </div>
            <div className="text-[11px] text-slate-400">|z| &ge; 1.3 or +5%</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-3 flex items-center justify-between">
          <div>
            <div className="text-[10px] text-slate-400 uppercase font-semibold">Cold Zones</div>
            <div className="text-xl font-bold font-mono text-cyan-400 flex items-center gap-1">
              <span>{overall.coldCount}</span>
              <Snowflake className="w-4 h-4 text-cyan-500" />
            </div>
            <div className="text-[11px] text-slate-400">|z| &le; -1.3 or -5%</div>
          </div>
        </div>
      </div>

      {/* Main Court Visualization Box */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <div className="lg:col-span-8 bg-slate-950/80 border border-slate-800 rounded-2xl p-4 shadow-2xl relative overflow-hidden flex flex-col items-center">
          <div className="w-full flex items-center justify-between mb-2 text-xs text-slate-400 px-2">
            <div className="flex items-center gap-2">
              <span className="font-semibold text-white">{playerData.player_name}</span>
              <span className="font-mono text-amber-400">({playerData.team})</span>
              <span>• Half-Court Telemetry</span>
            </div>
            <div className="flex items-center gap-3">
              <span className="flex items-center gap-1">
                <span className="w-2.5 h-2.5 rounded-full bg-rose-500"></span>
                <span>Hot (&gt;+5%)</span>
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2.5 h-2.5 rounded-full bg-slate-500"></span>
                <span>Neutral</span>
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2.5 h-2.5 rounded-full bg-cyan-500"></span>
                <span>Cold (&lt;-5%)</span>
              </span>
            </div>
          </div>

          {/* SVG Court Canvas */}
          <div className="w-full max-w-[540px] aspect-[500/470] relative">
            <svg
              viewBox="0 0 500 470"
              className="w-full h-full drop-shadow-lg select-none"
              style={{ background: '#0b0f17' }}
            >
              {/* Defs for gradients & patterns */}
              <defs>
                <radialGradient id="rimGlow" cx="50%" cy="50%" r="50%">
                  <stop offset="0%" stopColor="#f97316" stopOpacity="0.4" />
                  <stop offset="100%" stopColor="#f97316" stopOpacity="0" />
                </radialGradient>
              </defs>

              {/* ------------------------------------------------------------- */}
              {/* VIEW MODE 1: ZONE POLYGONS & PATHS (Thermal Shading) */}
              {/* ------------------------------------------------------------- */}
              {viewMode === 'zones' && (
                <g className="transition-opacity duration-300">
                  {/* 1. Deep / Logo 3 */}
                  {renderZonePolygon(
                    'Deep / Logo 3',
                    '0,0 500,0 500,140 0,140',
                    zoneMetricsMap.get('Deep / Logo 3')
                  )}

                  {/* 2. Left Corner 3 */}
                  {renderZonePolygon(
                    'Left Corner 3',
                    '0,328 30,328 30,470 0,470',
                    zoneMetricsMap.get('Left Corner 3')
                  )}

                  {/* 3. Right Corner 3 */}
                  {renderZonePolygon(
                    'Right Corner 3',
                    '470,328 500,328 500,470 470,470',
                    zoneMetricsMap.get('Right Corner 3')
                  )}

                  {/* 4. Left Wing 3 */}
                  {renderZonePath(
                    'Left Wing 3',
                    'M 0,140 L 180,140 L 180,190.5 A 237.5,237.5 0 0,0 30,328 L 0,328 Z',
                    zoneMetricsMap.get('Left Wing 3')
                  )}

                  {/* 5. Center 3 */}
                  {renderZonePath(
                    'Center 3',
                    'M 180,140 L 320,140 L 320,190.5 A 237.5,237.5 0 0,0 180,190.5 Z',
                    zoneMetricsMap.get('Center 3')
                  )}

                  {/* 6. Right Wing 3 */}
                  {renderZonePath(
                    'Right Wing 3',
                    'M 320,140 L 500,140 L 500,328 L 470,328 A 237.5,237.5 0 0,0 320,190.5 Z',
                    zoneMetricsMap.get('Right Wing 3')
                  )}

                  {/* 7. Left Baseline Mid */}
                  {renderZonePolygon(
                    'Left Baseline Mid',
                    '30,328 170,328 170,470 30,470',
                    zoneMetricsMap.get('Left Baseline Mid')
                  )}

                  {/* 8. Right Baseline Mid */}
                  {renderZonePolygon(
                    'Right Baseline Mid',
                    '330,328 470,328 470,470 330,470',
                    zoneMetricsMap.get('Right Baseline Mid')
                  )}

                  {/* 9. Left Wing Mid */}
                  {renderZonePath(
                    'Left Wing Mid',
                    'M 30,328 A 237.5,237.5 0 0,1 180,190.5 L 170,280 L 170,328 Z',
                    zoneMetricsMap.get('Left Wing Mid')
                  )}

                  {/* 10. Center Mid */}
                  {renderZonePath(
                    'Center Mid',
                    'M 170,280 L 180,190.5 A 237.5,237.5 0 0,1 320,190.5 L 330,280 Z',
                    zoneMetricsMap.get('Center Mid')
                  )}

                  {/* 11. Right Wing Mid */}
                  {renderZonePath(
                    'Right Wing Mid',
                    'M 470,328 L 330,328 L 330,280 L 320,190.5 A 237.5,237.5 0 0,1 470,328 Z',
                    zoneMetricsMap.get('Right Wing Mid')
                  )}

                  {/* 12. Paint (High / FT) */}
                  {renderZonePolygon(
                    'Paint (High / FT)',
                    '170,280 330,280 330,355 170,355',
                    zoneMetricsMap.get('Paint (High / FT)')
                  )}

                  {/* 13. Paint (Low / Floater) */}
                  {renderZonePolygon(
                    'Paint (Low / Floater)',
                    '170,355 330,355 330,470 170,470',
                    zoneMetricsMap.get('Paint (Low / Floater)')
                  )}

                  {/* 14. Restricted Area */}
                  {renderZoneCircle(
                    'Restricted Area',
                    250,
                    417.5,
                    42,
                    zoneMetricsMap.get('Restricted Area')
                  )}
                </g>
              )}

              {/* ------------------------------------------------------------- */}
              {/* VIEW MODE 2: HEXAGONAL DENSITY (Kirk Goldsberry Style) */}
              {/* ------------------------------------------------------------- */}
              {viewMode === 'hex' && (
                <g className="transition-opacity duration-300">
                  {hexbins.map((hex) => {
                    const color = getThermalColor(hex.deltaPct);
                    return (
                      <polygon
                        key={hex.id}
                        points={hex.points}
                        fill={color}
                        stroke="#1e293b"
                        strokeWidth="1"
                        className="hover:stroke-white transition-all cursor-pointer opacity-90"
                      >
                        <title>
                          {`Hex (${hex.fgm}/${hex.fga} made, ${(hex.fgPct * 100).toFixed(0)}%, vs Lg: ${(hex.deltaPct >= 0 ? '+' : '')}${(hex.deltaPct * 100).toFixed(1)}%)`}
                        </title>
                      </polygon>
                    );
                  })}
                </g>
              )}

              {/* ------------------------------------------------------------- */}
              {/* VIEW MODE 3: INDIVIDUAL SCATTER */}
              {/* ------------------------------------------------------------- */}
              {viewMode === 'scatter' && (
                <g className="transition-opacity duration-300">
                  {activeShots.map((shot, idx) => {
                    const sx = toSvgX(shot.x);
                    const sy = toSvgY(shot.y);
                    const isMade = shot.made;

                    return (
                      <g
                        key={idx}
                        className="cursor-pointer group"
                        onMouseEnter={() => setHoveredShot(shot)}
                        onMouseLeave={() => setHoveredShot(null)}
                      >
                        {isMade ? (
                          <circle
                            cx={sx}
                            cy={sy}
                            r="4.5"
                            fill="#10b981"
                            stroke="#047857"
                            strokeWidth="1.2"
                            className="transition-transform group-hover:scale-150 drop-shadow-[0_0_6px_rgba(16,185,129,0.8)]"
                          />
                        ) : (
                          <g className="transition-transform group-hover:scale-150">
                            <line
                              x1={sx - 3.5}
                              y1={sy - 3.5}
                              x2={sx + 3.5}
                              y2={sy + 3.5}
                              stroke="#ef4444"
                              strokeWidth="1.8"
                              strokeLinecap="round"
                            />
                            <line
                              x1={sx + 3.5}
                              y1={sy - 3.5}
                              x2={sx - 3.5}
                              y2={sy + 3.5}
                              stroke="#ef4444"
                              strokeWidth="1.8"
                              strokeLinecap="round"
                            />
                          </g>
                        )}
                      </g>
                    );
                  })}
                </g>
              )}

              {/* ------------------------------------------------------------- */}
              {/* NBA COURT LINES (Overlay) */}
              {/* ------------------------------------------------------------- */}
              <g stroke="#475569" strokeWidth="1.8" fill="none" opacity="0.85">
                {/* Court Perimeter */}
                <rect x="2" y="2" width="496" height="466" stroke="#334155" strokeWidth="2" />

                {/* Half Court Line & Center Circle */}
                <line x1="0" y1="2" x2="500" y2="2" strokeWidth="2.5" />
                <path d="M 190,2 A 60,60 0 0,0 310,2" />

                {/* Free Throw Key (16 ft wide x 19 ft long) */}
                <rect x="170" y="280" width="160" height="190" />

                {/* Free Throw Circle (Top solid, Bottom dashed) */}
                <path d="M 190,280 A 60,60 0 0,1 310,280" />
                <path d="M 190,280 A 60,60 0 0,0 310,280" strokeDasharray="5,5" />

                {/* Backboard & Rim */}
                <line x1="220" y1="430" x2="280" y2="430" stroke="#f8fafc" strokeWidth="2.5" />
                <line x1="250" y1="430" x2="250" y2="425" stroke="#f8fafc" strokeWidth="2" />
                <circle cx="250" cy="417.5" r="7.5" stroke="#f97316" strokeWidth="2.2" />

                {/* Restricted Area Arc (radius 40 around hoop) */}
                <path d="M 210,417.5 A 40,40 0 0,1 290,417.5" stroke="#94a3b8" />

                {/* 3-Point Lines: Corner flats + Top Arc extending behind Free Throw Circle */}
                <line x1="30" y1="470" x2="30" y2="328" />
                <line x1="470" y1="470" x2="470" y2="328" />
                <path d="M 30,328 A 237.5,237.5 0 0,1 470,328" strokeWidth="2" />
              </g>

              {/* ------------------------------------------------------------- */}
              {/* ZONE LABELS OVERLAY (When in Zone Mode) */}
              {/* ------------------------------------------------------------- */}
              {viewMode === 'zones' && (
                <g className="pointer-events-none select-none font-mono">
                  {renderZoneLabelBadge('Deep / Logo 3', 250, 60, zoneMetricsMap.get('Deep / Logo 3'))}
                  {renderZoneLabelBadge('Left Wing 3', 100, 160, zoneMetricsMap.get('Left Wing 3'))}
                  {renderZoneLabelBadge('Center 3', 250, 155, zoneMetricsMap.get('Center 3'))}
                  {renderZoneLabelBadge('Right Wing 3', 400, 160, zoneMetricsMap.get('Right Wing 3'))}
                  {renderZoneLabelBadge('Left Corner 3', 20, 410, zoneMetricsMap.get('Left Corner 3'))}
                  {renderZoneLabelBadge('Right Corner 3', 480, 410, zoneMetricsMap.get('Right Corner 3'))}
                  {renderZoneLabelBadge('Left Wing Mid', 105, 270, zoneMetricsMap.get('Left Wing Mid'))}
                  {renderZoneLabelBadge('Center Mid', 250, 240, zoneMetricsMap.get('Center Mid'))}
                  {renderZoneLabelBadge('Right Wing Mid', 395, 270, zoneMetricsMap.get('Right Wing Mid'))}
                  {renderZoneLabelBadge('Left Baseline Mid', 100, 400, zoneMetricsMap.get('Left Baseline Mid'))}
                  {renderZoneLabelBadge('Right Baseline Mid', 400, 400, zoneMetricsMap.get('Right Baseline Mid'))}
                  {renderZoneLabelBadge('Paint (High / FT)', 250, 315, zoneMetricsMap.get('Paint (High / FT)'))}
                  {renderZoneLabelBadge('Paint (Low / Floater)', 250, 380, zoneMetricsMap.get('Paint (Low / Floater)'))}
                  {renderZoneLabelBadge('Restricted Area', 250, 442, zoneMetricsMap.get('Restricted Area'))}
                </g>
              )}
            </svg>
          </div>

          {/* Hover Details Floating Banner */}
          {hoveredShot && (
            <div className="mt-3 text-xs bg-slate-900 border border-slate-700 px-3 py-1.5 rounded-lg flex items-center gap-3 text-slate-300">
              <span className="font-semibold text-white">{hoveredShot.type}</span>
              <span>•</span>
              <span className={hoveredShot.made ? 'text-emerald-400 font-bold' : 'text-rose-400 font-bold'}>
                {hoveredShot.made ? 'MADE' : 'MISSED'} ({hoveredShot.val}PT)
              </span>
              <span>•</span>
              <span>{hoveredShot.dist} ft</span>
              <span>•</span>
              <span className="font-mono text-slate-400">Q{hoveredShot.period} {hoveredShot.clock}</span>
            </div>
          )}
        </div>

        {/* Right Side: Detailed Zone Telemetry Table */}
        <div className="lg:col-span-4 space-y-4">
          <div className="bg-slate-900/80 border border-slate-800 rounded-2xl p-4 shadow-xl">
            <div className="flex flex-col gap-2 mb-3">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-bold text-white uppercase tracking-wider flex items-center gap-2">
                  <Crosshair className="w-4 h-4 text-indigo-400" />
                  <span>Zone Efficiency Breakdown</span>
                </h3>
                <span className="text-xs font-mono text-slate-400">
                  {filteredZoneMetrics.length} / {zoneMetrics.length}
                </span>
              </div>

              {/* Status Filter Tabs */}
              <div className="flex items-center gap-1 p-1 bg-slate-950/80 rounded-lg border border-slate-800 text-[11px]">
                <button
                  type="button"
                  onClick={() => setZoneFilter('ALL')}
                  className={`px-2.5 py-1 rounded font-semibold transition-all ${
                    zoneFilter === 'ALL'
                      ? 'bg-slate-800 text-white shadow-sm'
                      : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  All ({zoneMetrics.length})
                </button>
                <button
                  type="button"
                  onClick={() => setZoneFilter('HOT')}
                  className={`px-2 py-1 rounded font-semibold transition-all flex items-center gap-1 ${
                    zoneFilter === 'HOT'
                      ? 'bg-rose-500/20 text-rose-300 border border-rose-500/40 shadow-sm'
                      : 'text-rose-400 hover:text-rose-300'
                  }`}
                >
                  <Flame className="w-3 h-3 text-rose-500" />
                  <span>Hot ({overall.hotCount})</span>
                </button>
                <button
                  type="button"
                  onClick={() => setZoneFilter('COLD')}
                  className={`px-2 py-1 rounded font-semibold transition-all flex items-center gap-1 ${
                    zoneFilter === 'COLD'
                      ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 shadow-sm'
                      : 'text-cyan-400 hover:text-cyan-300'
                  }`}
                >
                  <Snowflake className="w-3 h-3 text-cyan-400" />
                  <span>Cold ({overall.coldCount})</span>
                </button>
                <button
                  type="button"
                  onClick={() => setZoneFilter('NEUTRAL')}
                  className={`px-2 py-1 rounded font-semibold transition-all ${
                    zoneFilter === 'NEUTRAL'
                      ? 'bg-slate-800 text-slate-200 border border-slate-700'
                      : 'text-slate-400 hover:text-slate-300'
                  }`}
                >
                  Neutral ({zoneMetrics.filter((z) => z.status === 'NEUTRAL').length})
                </button>
              </div>
            </div>

            <div className="space-y-2 max-h-[440px] overflow-y-auto pr-1">
              {filteredZoneMetrics.map((zm) => {
                const badge = getStatusBadge(zm.status);
                const isPositive = zm.deltaPct >= 0;
                const displayName = getZoneDisplayName(zm.zone);

                return (
                  <div
                    key={zm.zone}
                    className="p-2.5 rounded-lg bg-slate-950/70 border border-slate-800/80 hover:border-slate-700 transition-colors"
                  >
                    <div className="flex items-center justify-between text-xs mb-1">
                      <div className="flex flex-col">
                        <span className="font-semibold text-slate-200">{displayName.name}</span>
                        {displayName.subtitle && (
                          <span className="text-[10px] text-slate-400 font-normal">
                            {displayName.subtitle}
                          </span>
                        )}
                      </div>
                      <span
                        className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold border ${badge.bg}`}
                      >
                        <span className={`w-1.5 h-1.5 rounded-full ${badge.dot}`}></span>
                        <span>{badge.label}</span>
                      </span>
                    </div>

                    <div className="grid grid-cols-4 gap-1 text-[11px] font-mono text-slate-400 mt-1">
                      <div>
                        <div className="text-[9px] uppercase text-slate-500">Vol (FGA)</div>
                        <div className="text-slate-200 font-semibold">{zm.fgm}/{zm.fga}</div>
                      </div>
                      <div>
                        <div className="text-[9px] uppercase text-slate-500">Player %</div>
                        <div className="text-white font-bold">
                          {zm.fga > 0 ? `${(zm.fgPct * 100).toFixed(0)}%` : '0%'}
                        </div>
                      </div>
                      <div>
                        <div className="text-[9px] uppercase text-slate-500">Lg Avg</div>
                        <div>{(zm.lgPct * 100).toFixed(0)}%</div>
                      </div>
                      <div>
                        <div className="text-[9px] uppercase text-slate-500">Delta</div>
                        <div
                          className={`font-semibold ${
                            isPositive ? 'text-emerald-400' : 'text-rose-400'
                          }`}
                        >
                          {zm.fga > 0 ? `${isPositive ? '+' : ''}${(zm.deltaPct * 100).toFixed(1)}%` : '0.0%'}
                        </div>
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
  );
};

// Helper: Zone Polygon SVG Element
function renderZonePolygon(name: string, points: string, metric?: ZoneMetric) {
  const color = metric ? getThermalColor(metric.deltaPct, metric.status) : 'rgba(100, 116, 139, 0.15)';
  return (
    <polygon
      key={name}
      points={points}
      fill={color}
      stroke="#334155"
      strokeWidth="0.8"
      className="transition-colors duration-300"
    />
  );
}

// Helper: Zone Path SVG Element (Curved Geometries)
function renderZonePath(name: string, pathD: string, metric?: ZoneMetric) {
  const color = metric ? getThermalColor(metric.deltaPct, metric.status) : 'rgba(100, 116, 139, 0.15)';
  return (
    <path
      key={name}
      d={pathD}
      fill={color}
      stroke="#334155"
      strokeWidth="0.8"
      className="transition-colors duration-300"
    />
  );
}

// Helper: Zone Circle SVG Element
function renderZoneCircle(name: string, cx: number, cy: number, r: number, metric?: ZoneMetric) {
  const color = metric ? getThermalColor(metric.deltaPct, metric.status) : 'rgba(100, 116, 139, 0.15)';
  return (
    <circle
      key={name}
      cx={cx}
      cy={cy}
      r={r}
      fill={color}
      stroke="#334155"
      strokeWidth="0.8"
      className="transition-colors duration-300"
    />
  );
}

// Helper: Text Badge in SVG Zone
function renderZoneLabelBadge(name: string, x: number, y: number, metric?: ZoneMetric) {
  if (!metric || metric.fga === 0) return null;

  const pct = (metric.fgPct * 100).toFixed(0);

  return (
    <g key={name} transform={`translate(${x}, ${y})`}>
      <rect
        x="-32"
        y="-11"
        width="64"
        height="22"
        rx="4"
        fill="rgba(15, 23, 42, 0.85)"
        stroke={metric.status === 'HOT' ? '#f43f5e' : metric.status === 'COLD' ? '#06b6d4' : '#475569'}
        strokeWidth="1"
      />
      <text
        x="0"
        y="3.5"
        textAnchor="middle"
        fontSize="9.5"
        fontWeight="bold"
        fill={metric.status === 'HOT' ? '#fda4af' : metric.status === 'COLD' ? '#67e8f9' : '#e2e8f0'}
      >
        {metric.fgm}/{metric.fga} ({pct}%)
      </text>
    </g>
  );
}
