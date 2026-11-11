'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { PassingCatalogEntry, PassingChartData, PassingMetadata, PassingZoneMetric, PassRecord } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { BASE_PATH } from '@/lib/basePath';
import {
  Target,
  Search,
  Layers,
  CircleDot,
  Flame,
  ShieldAlert,
  Loader2,
  CheckCircle2,
  XCircle,
} from 'lucide-react';

interface PassingExplorerClientProps {
  catalog: PassingCatalogEntry[];
  metadata: PassingMetadata;
  initialPlayerId?: string;
}

// 12 Canonical Throw Zones
const CANONICAL_ZONES = [
  'Deep Left',
  'Deep Middle',
  'Deep Right',
  'Intermediate Left',
  'Intermediate Middle',
  'Intermediate Right',
  'Short Left',
  'Short Middle',
  'Short Right',
  'Behind LOS Left',
  'Behind LOS Middle',
  'Behind LOS Right',
] as const;

// Geometric bounds for 12 zones on a 600 x 680 SVG canvas
// Width: 600 (Left: 20-200, Middle: 200-400, Right: 400-580)
// Depth: LOS at y = 480
// - Deep (20+ yds): y in [60, 240]
// - Intermediate (10-20 yds): y in [240, 360]
// - Short (0-10 yds): y in [360, 480]
// - Behind LOS (< 0 yds): y in [480, 580]
const ZONE_RECTS: Record<string, { x: number; y: number; width: number; height: number; depthLabel: string; sector: string }> = {
  'Deep Left': { x: 20, y: 60, width: 180, height: 180, depthLabel: 'Deep (20+ yds)', sector: 'Left' },
  'Deep Middle': { x: 200, y: 60, width: 200, height: 180, depthLabel: 'Deep (20+ yds)', sector: 'Middle' },
  'Deep Right': { x: 400, y: 60, width: 180, height: 180, depthLabel: 'Deep (20+ yds)', sector: 'Right' },

  'Intermediate Left': { x: 20, y: 240, width: 180, height: 120, depthLabel: 'Intermediate (10-20 yds)', sector: 'Left' },
  'Intermediate Middle': { x: 200, y: 240, width: 200, height: 120, depthLabel: 'Intermediate (10-20 yds)', sector: 'Middle' },
  'Intermediate Right': { x: 400, y: 240, width: 180, height: 120, depthLabel: 'Intermediate (10-20 yds)', sector: 'Right' },

  'Short Left': { x: 20, y: 360, width: 180, height: 120, depthLabel: 'Short (0-10 yds)', sector: 'Left' },
  'Short Middle': { x: 200, y: 360, width: 200, height: 120, depthLabel: 'Short (0-10 yds)', sector: 'Middle' },
  'Short Right': { x: 400, y: 360, width: 180, height: 120, depthLabel: 'Short (0-10 yds)', sector: 'Right' },

  'Behind LOS Left': { x: 20, y: 480, width: 180, height: 100, depthLabel: 'Behind LOS (< 0 yds)', sector: 'Left' },
  'Behind LOS Middle': { x: 200, y: 480, width: 200, height: 100, depthLabel: 'Behind LOS (< 0 yds)', sector: 'Middle' },
  'Behind LOS Right': { x: 400, y: 480, width: 180, height: 100, depthLabel: 'Behind LOS (< 0 yds)', sector: 'Right' },
};

function getZoneHeatColor(cpoe: number, attempts: number): { fill: string; stroke: string; label: string } {
  if (attempts === 0) {
    return { fill: 'rgba(30, 41, 59, 0.3)', stroke: '#334155', label: 'NO SAMPLE' };
  }
  if (cpoe >= 4.0) {
    return { fill: 'rgba(16, 185, 129, 0.35)', stroke: '#10b981', label: 'HOT' };
  }
  if (cpoe >= 1.0) {
    return { fill: 'rgba(20, 184, 166, 0.28)', stroke: '#14b8a6', label: 'ABOVE AVG' };
  }
  if (cpoe >= -2.5) {
    return { fill: 'rgba(59, 130, 246, 0.20)', stroke: '#3b82f6', label: 'AVERAGE' };
  }
  if (cpoe >= -6.0) {
    return { fill: 'rgba(245, 158, 11, 0.28)', stroke: '#f59e0b', label: 'BELOW AVG' };
  }
  return { fill: 'rgba(244, 63, 94, 0.35)', stroke: '#f43f5e', label: 'COLD' };
}

// Pseudo-random deterministic jitter based on game_id and index
function getDeterministicX(pass: PassRecord, index: number): number {
  const rect = ZONE_RECTS[pass.zone];
  if (!rect) return 300;
  // hash string
  let hash = index * 17;
  for (let i = 0; i < pass.game_id.length; i++) {
    hash = (hash << 5) - hash + pass.game_id.charCodeAt(i);
    hash |= 0;
  }
  const factor = Math.abs(hash % 1000) / 1000;
  const padding = 16;
  return rect.x + padding + factor * (rect.width - padding * 2);
}

function getAirYardsY(airYards: number): number {
  // LOS is at y = 480 (0 yards)
  // 10 yards = 120 pixels -> 12 px per yard
  // Clamped between y = 70 (approx 34 yards downfield) and y = 570 (-7.5 yards)
  const rawY = 480 - airYards * 12;
  return Math.max(68, Math.min(572, rawY));
}

export const PassingExplorerClient: React.FC<PassingExplorerClientProps> = ({
  catalog,
  metadata,
  initialPlayerId,
}) => {
  // Default to Patrick Mahomes, Lamar Jackson, or first QB in catalog
  const defaultQb = useMemo(() => {
    if (initialPlayerId) {
      const match = catalog.find((c) => c.player_id === initialPlayerId);
      if (match) return match;
    }
    const mahomes = catalog.find((c) => c.player_name.includes('Mahomes'));
    if (mahomes) return mahomes;
    const lamar = catalog.find((c) => c.player_name.includes('Jackson'));
    if (lamar) return lamar;
    return catalog[0];
  }, [catalog, initialPlayerId]);

  const [selectedQb, setSelectedQb] = useState<PassingCatalogEntry | null>(defaultQb || null);
  const [searchTerm, setSearchTerm] = useState<string>('');
  const [selectedTeam, setSelectedTeam] = useState<string>('All');
  const [viewMode, setViewMode] = useState<'zones' | 'scatter' | 'combined'>('combined');
  const [selectedZone, setSelectedZone] = useState<string | null>(null);
  const [hoveredZone, setHoveredZone] = useState<string | null>(null);
  const [hoveredPass, setHoveredPass] = useState<PassRecord | null>(null);
  const [chartData, setChartData] = useState<PassingChartData | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Teams list for dropdown
  const teams = useMemo(() => {
    const set = new Set(catalog.map((c) => c.team));
    return ['All', ...Array.from(set).sort()];
  }, [catalog]);

  // Featured marquee QBs for quick-select pills
  const featuredQbs = useMemo(() => {
    const starNames = ['Mahomes', 'Jackson', 'Allen', 'Daniels', 'Burrow', 'Purdy', 'Goff', 'Love'];
    return catalog.filter((c) => starNames.some((star) => c.player_name.includes(star)));
  }, [catalog]);

  // Filtered catalog for search
  const filteredCatalog = useMemo(() => {
    return catalog.filter((p) => {
      if (selectedTeam !== 'All' && p.team !== selectedTeam) return false;
      if (searchTerm.trim() !== '') {
        const term = searchTerm.toLowerCase();
        return p.player_name.toLowerCase().includes(term) || p.team.toLowerCase().includes(term);
      }
      return true;
    });
  }, [catalog, selectedTeam, searchTerm]);

  // Fetch chunked per-QB JSON when selectedQb changes
  useEffect(() => {
    if (!selectedQb) return;

    let isMounted = true;
    setLoading(true);
    setError(null);
    setSelectedZone(null);

    fetch(`${BASE_PATH}/data/passing/${selectedQb.player_id}.json`)
      .then((res) => {
        if (!res.ok) throw new Error(`Could not load passing chart for ${selectedQb.player_name}`);
        return res.json();
      })
      .then((data: PassingChartData) => {
        if (isMounted) {
          setChartData(data);
          setLoading(false);
        }
      })
      .catch((err) => {
        if (isMounted) {
          setError(err.message);
          setLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [selectedQb]);

  // Lookup map for QB zone metrics
  const zoneMetricsMap = useMemo(() => {
    const map = new Map<string, PassingZoneMetric>();
    if (chartData?.zones) {
      for (const z of chartData.zones) {
        map.set(z.zone, z);
      }
    }
    return map;
  }, [chartData]);

  // Filter passes based on selected zone
  const activePasses = useMemo(() => {
    if (!chartData?.passes) return [];
    if (!selectedZone) return chartData.passes;
    return chartData.passes.filter((p) => p.zone === selectedZone);
  }, [chartData, selectedZone]);

  // Active zone metric for header or detail
  const activeZoneMetric = useMemo(() => {
    if (!selectedZone) return null;
    return zoneMetricsMap.get(selectedZone) || null;
  }, [selectedZone, zoneMetricsMap]);

  return (
    <div className="space-y-6">
      {/* 1. Top Controls Bar: Search, Team Filter, Quick Select Pills */}
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 space-y-4">
        <div className="flex flex-col md:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-3 w-full md:w-auto">
            <div className="relative flex-1 md:w-64">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                placeholder="Search quarterback or team..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700/80 rounded-lg pl-9 pr-3 py-1.5 text-sm text-slate-100 placeholder-slate-500 focus:outline-none focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500"
              />
            </div>
            <select
              value={selectedTeam}
              onChange={(e) => setSelectedTeam(e.target.value)}
              className="bg-slate-900 border border-slate-700/80 rounded-lg px-3 py-1.5 text-sm text-slate-200 focus:outline-none focus:border-emerald-500"
            >
              {teams.map((t) => (
                <option key={t} value={t}>
                  {t === 'All' ? 'All Teams' : t}
                </option>
              ))}
            </select>
            <select
              value={selectedQb?.player_id || ''}
              onChange={(e) => {
                const qb = catalog.find((c) => c.player_id === e.target.value);
                if (qb) setSelectedQb(qb);
              }}
              className="bg-slate-900 border border-slate-700/80 rounded-lg px-3 py-1.5 text-sm text-slate-200 focus:outline-none focus:border-emerald-500 max-w-[200px]"
            >
              {filteredCatalog.map((qb) => (
                <option key={qb.player_id} value={qb.player_id}>
                  {qb.team} - {qb.player_name} ({qb.total_passes})
                </option>
              ))}
            </select>
          </div>

          {/* View Mode Toggle */}
          <div className="flex items-center gap-1.5 bg-slate-900/90 p-1 rounded-lg border border-slate-800 w-full md:w-auto justify-center">
            <button
              onClick={() => setViewMode('zones')}
              className={`px-3 py-1 text-xs font-semibold rounded-md transition-all flex items-center gap-1.5 ${
                viewMode === 'zones'
                  ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <Layers className="w-3.5 h-3.5" />
              Zone Heatmap
            </button>
            <button
              onClick={() => setViewMode('scatter')}
              className={`px-3 py-1 text-xs font-semibold rounded-md transition-all flex items-center gap-1.5 ${
                viewMode === 'scatter'
                  ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <CircleDot className="w-3.5 h-3.5" />
              Throw Points
            </button>
            <button
              onClick={() => setViewMode('combined')}
              className={`px-3 py-1 text-xs font-semibold rounded-md transition-all flex items-center gap-1.5 ${
                viewMode === 'combined'
                  ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <Target className="w-3.5 h-3.5" />
              Combined Map
            </button>
          </div>
        </div>

        {/* Quick select pills */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-thin">
          <span className="text-xs font-bold text-slate-500 uppercase tracking-wider flex-shrink-0">
            Featured QBs:
          </span>
          {featuredQbs.map((qb) => {
            const isSelected = selectedQb?.player_id === qb.player_id;
            return (
              <button
                key={qb.player_id}
                onClick={() => setSelectedQb(qb)}
                className={`px-2.5 py-1 rounded-full text-xs font-medium whitespace-nowrap transition-all flex items-center gap-1.5 border ${
                  isSelected
                    ? 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40 shadow-sm shadow-emerald-500/10'
                    : 'bg-slate-900/60 text-slate-400 border-slate-800 hover:text-slate-200 hover:border-slate-700'
                }`}
              >
                <TeamLogo team={qb.team} size="xs" />
                <span>{qb.player_name}</span>
                <span className="text-[11px] sm:text-[10px] text-slate-500 font-mono">({qb.total_passes})</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* 2. Quarterback Overview Header */}
      {selectedQb && (
        <div className="bg-gradient-to-r from-slate-900 via-slate-900/90 to-surface-raised border border-slate-800 rounded-xl p-5 shadow-xl">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div className="flex items-center gap-4">
              <div className="relative w-16 h-16 rounded-xl overflow-hidden bg-slate-800 border-2 border-slate-700 flex-shrink-0 flex items-center justify-center">
                {selectedQb.headshot_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={selectedQb.headshot_url}
                    alt={selectedQb.player_name}
                    className="w-full h-full object-cover"
                  />
                ) : (
                  <TeamLogo team={selectedQb.team} size="lg" />
                )}
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <TeamLogo team={selectedQb.team} size="sm" />
                  <span className="text-xs font-bold text-emerald-400 tracking-wider uppercase">
                    {selectedQb.team} Quarterback
                  </span>
                  {selectedQb.jersey_number !== null && (
                    <span className="text-xs font-mono text-slate-400">#{selectedQb.jersey_number}</span>
                  )}
                </div>
                <h2 className="text-2xl font-black text-white tracking-tight flex items-center gap-2">
                  {selectedQb.player_name}
                </h2>
                <p className="text-xs text-slate-400 mt-0.5">
                  Empirical NextGenStats pass tracking grounded in official PBP records.
                </p>
              </div>
            </div>

            {/* Core QB Metrics */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="bg-slate-950/70 border border-slate-800/80 rounded-lg p-2.5 text-center">
                <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">Passes</div>
                <div className="text-lg font-bold font-mono text-white mt-0.5">
                  {selectedQb.completions} <span className="text-xs font-normal text-slate-400">/ {selectedQb.total_passes}</span>
                </div>
              </div>
              <div className="bg-slate-950/70 border border-slate-800/80 rounded-lg p-2.5 text-center">
                <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">Comp %</div>
                <div className="text-lg font-bold font-mono text-emerald-400 mt-0.5">
                  {(selectedQb.comp_pct * 100).toFixed(1)}%
                </div>
              </div>
              <div className="bg-slate-950/70 border border-slate-800/80 rounded-lg p-2.5 text-center">
                <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">CPOE</div>
                <div
                  className={`text-lg font-bold font-mono mt-0.5 ${
                    selectedQb.avg_cpoe >= 0 ? 'text-emerald-400' : 'text-rose-400'
                  }`}
                >
                  {selectedQb.avg_cpoe >= 0 ? '+' : ''}
                  {selectedQb.avg_cpoe.toFixed(1)}%
                </div>
              </div>
              <div className="bg-slate-950/70 border border-slate-800/80 rounded-lg p-2.5 text-center">
                <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">EPA / Pass</div>
                <div
                  className={`text-lg font-bold font-mono mt-0.5 ${
                    selectedQb.avg_epa >= 0 ? 'text-emerald-400' : 'text-rose-400'
                  }`}
                >
                  {selectedQb.avg_epa >= 0 ? '+' : ''}
                  {selectedQb.avg_epa.toFixed(2)}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* 3. Main Interactive Football Field Canvas & Live Zone Panel */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Field Canvas (Col 7 on LG) */}
        <div className="lg:col-span-7 bg-surface-raised border border-slate-800 rounded-xl p-5 shadow-xl flex flex-col items-center">
          <div className="w-full flex items-center justify-between pb-3 mb-2 border-b border-slate-800/80 text-xs">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-emerald-400" />
              <span className="font-bold text-white uppercase tracking-wider">NextGenStats Throw Canvas</span>
            </div>
            <div className="flex items-center gap-3 text-slate-400">
              <span className="flex items-center gap-1">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 inline-block" /> Complete
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2.5 h-2.5 rounded-full bg-rose-500 inline-block" /> Incomplete
              </span>
            </div>
          </div>

          {loading ? (
            <div className="h-[520px] w-full flex flex-col items-center justify-center gap-3 text-slate-400">
              <Loader2 className="w-8 h-8 animate-spin text-emerald-400" />
              <span className="text-sm">Loading empirical pass locations...</span>
            </div>
          ) : error ? (
            <div className="h-[520px] w-full flex flex-col items-center justify-center gap-2 text-rose-400">
              <ShieldAlert className="w-8 h-8" />
              <span className="text-sm">{error}</span>
            </div>
          ) : (
            <div className="relative w-full max-w-[560px] aspect-[600/680] select-none">
              <svg
                viewBox="0 0 600 680"
                className="w-full h-full rounded-lg overflow-hidden border border-slate-800/90 shadow-inner bg-slate-950"
              >
                <defs>
                  {/* Subtle turf stripe pattern */}
                  <pattern id="turfPattern" width="600" height="120" patternUnits="userSpaceOnUse">
                    <rect width="600" height="60" fill="#091410" />
                    <rect y="60" width="600" height="60" fill="#060e0b" />
                  </pattern>
                  {/* Glow filter */}
                  <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
                    <feGaussianBlur stdDeviation="3" result="blur" />
                    <feComposite in="SourceGraphic" in2="blur" operator="over" />
                  </filter>
                </defs>

                {/* Field Background */}
                <rect width="600" height="680" fill="url(#turfPattern)" />

                {/* Endline & Boundary Markings */}
                <rect x="20" y="40" width="560" height="580" fill="none" stroke="#1e293b" strokeWidth="2" />

                {/* Yard Lines */}
                {/* 40 Yard line */}
                <line x1="20" y1="60" x2="580" y2="60" stroke="#334155" strokeWidth="1.5" />
                <text x="35" y="65" fill="#475569" fontSize="12" fontWeight="bold" fontFamily="monospace">40</text>
                <text x="545" y="65" fill="#475569" fontSize="12" fontWeight="bold" fontFamily="monospace">40</text>

                {/* 30 Yard line */}
                <line x1="20" y1="140" x2="580" y2="140" stroke="#334155" strokeWidth="1.5" strokeDasharray="6,4" />
                <text x="35" y="145" fill="#475569" fontSize="12" fontWeight="bold" fontFamily="monospace">30</text>
                <text x="545" y="145" fill="#475569" fontSize="12" fontWeight="bold" fontFamily="monospace">30</text>

                {/* 20 Yard line */}
                <line x1="20" y1="240" x2="580" y2="240" stroke="#475569" strokeWidth="2" />
                <text x="35" y="245" fill="#64748b" fontSize="13" fontWeight="bold" fontFamily="monospace">20</text>
                <text x="545" y="245" fill="#64748b" fontSize="13" fontWeight="bold" fontFamily="monospace">20</text>

                {/* 10 Yard line */}
                <line x1="20" y1="360" x2="580" y2="360" stroke="#475569" strokeWidth="2" />
                <text x="35" y="365" fill="#64748b" fontSize="13" fontWeight="bold" fontFamily="monospace">10</text>
                <text x="545" y="365" fill="#64748b" fontSize="13" fontWeight="bold" fontFamily="monospace">10</text>

                {/* Line of Scrimmage (LOS) prominent gold/blue line */}
                <line x1="20" y1="480" x2="580" y2="480" stroke="#38bdf8" strokeWidth="3" filter="url(#glow)" />
                <rect x="250" y="471" width="100" height="18" rx="4" fill="#0369a1" />
                <text x="300" y="484" fill="#ffffff" fontSize="10" fontWeight="bold" textAnchor="middle" letterSpacing="1">
                  LINE OF SCRIMMAGE
                </text>

                {/* Behind LOS label */}
                <text x="300" y="550" fill="#334155" fontSize="11" fontWeight="bold" textAnchor="middle" letterSpacing="1">
                  BEHIND LINE OF SCRIMMAGE (&lt; 0 YDS)
                </text>

                {/* Pro Hash Marks at x = 240 and x = 360 */}
                {[100, 180, 300, 420].map((yVal) => (
                  <g key={yVal}>
                    <line x1="235" y1={yVal} x2="245" y2={yVal} stroke="#475569" strokeWidth="1.5" />
                    <line x1="355" y1={yVal} x2="365" y2={yVal} stroke="#475569" strokeWidth="1.5" />
                  </g>
                ))}

                {/* Sector Dividers (Left | Middle | Right) */}
                <line x1="200" y1="40" x2="200" y2="580" stroke="#1e293b" strokeWidth="1.5" strokeDasharray="4,6" />
                <line x1="400" y1="40" x2="400" y2="580" stroke="#1e293b" strokeWidth="1.5" strokeDasharray="4,6" />

                {/* Sector Header labels at top */}
                <text x="110" y="30" fill="#64748b" fontSize="11" fontWeight="bold" textAnchor="middle" letterSpacing="1">
                  LEFT THIRD
                </text>
                <text x="300" y="30" fill="#64748b" fontSize="11" fontWeight="bold" textAnchor="middle" letterSpacing="1">
                  BETWEEN HASHES (MIDDLE)
                </text>
                <text x="490" y="30" fill="#64748b" fontSize="11" fontWeight="bold" textAnchor="middle" letterSpacing="1">
                  RIGHT THIRD
                </text>

                {/* 12 Interactive Zone Rectangles (Heatmap & Combined) */}
                {(viewMode === 'zones' || viewMode === 'combined') && (
                  <g>
                    {CANONICAL_ZONES.map((zoneName) => {
                      const rect = ZONE_RECTS[zoneName];
                      const zm = zoneMetricsMap.get(zoneName);
                      const att = zm?.attempts || 0;
                      const cmp = zm?.completions || 0;
                      const cpoe = zm?.avg_cpoe || 0;
                      const epa = zm?.avg_epa || 0;
                      const heat = getZoneHeatColor(cpoe, att);

                      const isSelected = selectedZone === zoneName;
                      const isHovered = hoveredZone === zoneName;

                      return (
                        <g
                          key={zoneName}
                          onClick={() => setSelectedZone(isSelected ? null : zoneName)}
                          onMouseEnter={() => setHoveredZone(zoneName)}
                          onMouseLeave={() => setHoveredZone(null)}
                          className="cursor-pointer transition-all duration-200"
                        >
                          <rect
                            x={rect.x + 2}
                            y={rect.y + 2}
                            width={rect.width - 4}
                            height={rect.height - 4}
                            rx={6}
                            fill={isSelected ? 'rgba(56, 189, 248, 0.35)' : heat.fill}
                            stroke={isSelected ? '#38bdf8' : isHovered ? '#ffffff' : heat.stroke}
                            strokeWidth={isSelected ? 3 : isHovered ? 2 : 1}
                            strokeDasharray={isSelected ? 'none' : 'none'}
                          />
                          {/* Zone Stat Overlay */}
                          <text
                            x={rect.x + rect.width / 2}
                            y={rect.y + rect.height / 2 - 12}
                            fill="#ffffff"
                            fontSize="13"
                            fontWeight="bold"
                            textAnchor="middle"
                            fontFamily="monospace"
                          >
                            {cmp}/{att}
                          </text>
                          <text
                            x={rect.x + rect.width / 2}
                            y={rect.y + rect.height / 2 + 5}
                            fill={att > 0 && cpoe >= 0 ? '#34d399' : '#f87171'}
                            fontSize="11"
                            fontWeight="bold"
                            textAnchor="middle"
                          >
                            {att > 0 ? `${(zm!.comp_pct * 100).toFixed(0)}% (${cpoe >= 0 ? '+' : ''}${cpoe.toFixed(1)}%)` : '—'}
                          </text>
                          <text
                            x={rect.x + rect.width / 2}
                            y={rect.y + rect.height / 2 + 20}
                            fill="#94a3b8"
                            fontSize="10"
                            textAnchor="middle"
                            fontFamily="monospace"
                          >
                            {att > 0 ? `${epa >= 0 ? '+' : ''}${epa.toFixed(2)} EPA` : '0 Att'}
                          </text>
                        </g>
                      );
                    })}
                  </g>
                )}

                {/* Individual Throw Scatter Points (Scatter & Combined) */}
                {(viewMode === 'scatter' || viewMode === 'combined') && (
                  <g>
                    {activePasses.map((p, idx) => {
                      const cx = getDeterministicX(p, idx);
                      const cy = getAirYardsY(p.air_yards);
                      const isComplete = p.complete_pass === 1;

                      return (
                        <circle
                          key={`${p.game_id}-${idx}`}
                          cx={cx}
                          cy={cy}
                          r={viewMode === 'scatter' ? 5 : 4}
                          fill={isComplete ? '#10b981' : '#f43f5e'}
                          fillOpacity={viewMode === 'scatter' ? 0.9 : 0.75}
                          stroke={isComplete ? '#064e3b' : '#881337'}
                          strokeWidth={1.5}
                          className="cursor-pointer hover:scale-150 transition-transform duration-150"
                          onMouseEnter={() => setHoveredPass(p)}
                          onMouseLeave={() => setHoveredPass(null)}
                        />
                      );
                    })}
                  </g>
                )}
              </svg>

              {/* Hover Tooltip for Individual Pass Point */}
              {hoveredPass && (
                <div className="absolute top-4 right-4 bg-slate-900/95 border border-slate-700/80 rounded-lg p-3 text-xs shadow-2xl backdrop-blur-md pointer-events-none z-20 space-y-1">
                  <div className="flex items-center gap-1.5 font-bold">
                    {hoveredPass.complete_pass === 1 ? (
                      <span className="text-emerald-400 flex items-center gap-1">
                        <CheckCircle2 className="w-3.5 h-3.5" /> Complete
                      </span>
                    ) : (
                      <span className="text-rose-400 flex items-center gap-1">
                        <XCircle className="w-3.5 h-3.5" /> Incomplete
                      </span>
                    )}
                    <span className="text-slate-400">· {hoveredPass.zone}</span>
                  </div>
                  <div className="text-slate-300">
                    <span className="font-mono">{hoveredPass.air_yards}</span> Air Yards
                    {hoveredPass.defteam ? ` vs ${hoveredPass.defteam}` : ''} (Week {hoveredPass.week})
                  </div>
                  <div className="flex items-center gap-3 font-mono text-[11px] pt-1 border-t border-slate-800">
                    <span className={hoveredPass.epa >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                      EPA: {hoveredPass.epa >= 0 ? '+' : ''}{hoveredPass.epa.toFixed(2)}
                    </span>
                    {hoveredPass.cpoe !== null && hoveredPass.cpoe !== undefined && (
                      <span className={hoveredPass.cpoe >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                        CPOE: {hoveredPass.cpoe >= 0 ? '+' : ''}{hoveredPass.cpoe.toFixed(1)}%
                      </span>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Canvas Footer explanation */}
          <div className="w-full text-center text-xs text-slate-500 pt-3">
            Click any zone rectangle to isolate throws and filter the metrics table below.
          </div>
        </div>

        {/* Selected Zone Deep Dive / Metric Cards (Col 5 on LG) */}
        <div className="lg:col-span-5 space-y-4">
          <div className="bg-surface-raised border border-slate-800 rounded-xl p-5 shadow-xl space-y-4">
            <div className="flex items-center justify-between pb-3 border-b border-slate-800">
              <div className="flex items-center gap-2">
                <Target className="w-4 h-4 text-emerald-400" />
                <h3 className="text-sm font-bold text-white uppercase tracking-wider">
                  {selectedZone ? selectedZone : 'Full Field Zone Summary'}
                </h3>
              </div>
              {selectedZone && (
                <button
                  onClick={() => setSelectedZone(null)}
                  className="text-xs text-slate-400 hover:text-white underline"
                >
                  Clear Filter
                </button>
              )}
            </div>

            {/* Quick overview of selected zone or full summary */}
            {selectedZone && activeZoneMetric ? (
              <div className="space-y-4">
                <div className="bg-slate-950/80 border border-slate-800 rounded-lg p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-slate-400">Throw Sector & Depth</span>
                    <span className="text-xs font-semibold text-emerald-400">
                      {ZONE_RECTS[selectedZone]?.depthLabel} · {ZONE_RECTS[selectedZone]?.sector}
                    </span>
                  </div>

                  <div className="grid grid-cols-2 gap-3 pt-2">
                    <div className="bg-slate-900/90 rounded p-2.5 text-center">
                      <div className="text-[11px] sm:text-[10px] text-slate-500 uppercase font-semibold">Attempts (Share)</div>
                      <div className="text-base font-bold font-mono text-white mt-0.5">
                        {activeZoneMetric.attempts} ({((activeZoneMetric.pct_of_passes || 0) * 100).toFixed(1)}%)
                      </div>
                    </div>
                    <div className="bg-slate-900/90 rounded p-2.5 text-center">
                      <div className="text-[11px] sm:text-[10px] text-slate-500 uppercase font-semibold">Completion %</div>
                      <div className="text-base font-bold font-mono text-emerald-400 mt-0.5">
                        {(activeZoneMetric.comp_pct * 100).toFixed(1)}%
                      </div>
                    </div>
                    <div className="bg-slate-900/90 rounded p-2.5 text-center">
                      <div className="text-[11px] sm:text-[10px] text-slate-500 uppercase font-semibold">CPOE vs Baseline</div>
                      <div
                        className={`text-base font-bold font-mono mt-0.5 ${
                          activeZoneMetric.avg_cpoe >= 0 ? 'text-emerald-400' : 'text-rose-400'
                        }`}
                      >
                        {activeZoneMetric.avg_cpoe >= 0 ? '+' : ''}
                        {activeZoneMetric.avg_cpoe.toFixed(1)}%
                      </div>
                    </div>
                    <div className="bg-slate-900/90 rounded p-2.5 text-center">
                      <div className="text-[11px] sm:text-[10px] text-slate-500 uppercase font-semibold">EPA / Pass</div>
                      <div
                        className={`text-base font-bold font-mono mt-0.5 ${
                          activeZoneMetric.avg_epa >= 0 ? 'text-emerald-400' : 'text-rose-400'
                        }`}
                      >
                        {activeZoneMetric.avg_epa >= 0 ? '+' : ''}
                        {activeZoneMetric.avg_epa.toFixed(2)}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Filtered passes mini-list */}
                <div className="space-y-2">
                  <div className="text-xs font-bold text-slate-400 uppercase tracking-wider">
                    Recent Targeted Throws in Zone ({activePasses.length})
                  </div>
                  <div className="max-h-56 overflow-y-auto space-y-1.5 pr-1 scrollbar-thin">
                    {activePasses.map((p, idx) => (
                      <div
                        key={idx}
                        className="bg-slate-950/60 border border-slate-800/80 rounded px-3 py-1.5 flex items-center justify-between text-xs"
                      >
                        <div className="flex items-center gap-2">
                          {p.complete_pass === 1 ? (
                            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                          ) : (
                            <XCircle className="w-3.5 h-3.5 text-rose-400" />
                          )}
                          <span className="text-slate-300 font-mono">{p.air_yards} air yds</span>
                          {p.defteam && <span className="text-slate-500">vs {p.defteam}</span>}
                        </div>
                        <div className="flex items-center gap-2 font-mono text-[11px]">
                          <span className={p.epa >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                            {p.epa >= 0 ? '+' : ''}{p.epa.toFixed(2)} EPA
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            ) : (
              <div className="space-y-3">
                <p className="text-xs text-slate-400 leading-relaxed">
                  Select any zone on the canvas to inspect granular throw accuracy, CPOE delta vs league baselines,
                  and individual play-by-play pass records.
                </p>
                {/* League averages reference */}
                <div className="text-xs font-bold text-slate-500 uppercase tracking-wider pt-2">
                  League Baselines (Season Sample: {metadata.total_passes_sampled} passes)
                </div>
                <div className="grid grid-cols-2 gap-2 text-xs">
                  <div className="bg-slate-950/60 p-2.5 rounded border border-slate-800">
                    <span className="text-slate-400">Deep (20+) Comp %:</span>
                    <span className="font-mono font-bold text-white ml-1.5">36.7%</span>
                  </div>
                  <div className="bg-slate-950/60 p-2.5 rounded border border-slate-800">
                    <span className="text-slate-400">Intermediate Comp %:</span>
                    <span className="font-mono font-bold text-white ml-1.5">55.8%</span>
                  </div>
                  <div className="bg-slate-950/60 p-2.5 rounded border border-slate-800">
                    <span className="text-slate-400">Short (0-10) Comp %:</span>
                    <span className="font-mono font-bold text-white ml-1.5">71.2%</span>
                  </div>
                  <div className="bg-slate-950/60 p-2.5 rounded border border-slate-800">
                    <span className="text-slate-400">Behind LOS Comp %:</span>
                    <span className="font-mono font-bold text-white ml-1.5">75.1%</span>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* 4. Complete 12-Zone Grid Cards */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Flame className="w-4 h-4 text-emerald-400" />
            <h3 className="text-base font-bold text-white tracking-tight">
              12 Discrete Throw Zone Performance Cards
            </h3>
          </div>
          <span className="text-xs text-slate-400">
            {chartData ? `${chartData.player_name} (${chartData.team})` : 'Quarterback Zones'}
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          {CANONICAL_ZONES.map((zoneName) => {
            const zm = zoneMetricsMap.get(zoneName);
            const att = zm?.attempts || 0;
            const cmp = zm?.completions || 0;
            const pct = zm ? (zm.comp_pct * 100).toFixed(1) : '0.0';
            const cpoe = zm?.avg_cpoe || 0;
            const epa = zm?.avg_epa || 0;
            const share = zm ? ((zm.pct_of_passes || 0) * 100).toFixed(1) : '0.0';
            const heat = getZoneHeatColor(cpoe, att);
            const isSelected = selectedZone === zoneName;

            return (
              <div
                key={zoneName}
                onClick={() => setSelectedZone(isSelected ? null : zoneName)}
                className={`bg-surface-raised border rounded-xl p-3.5 cursor-pointer transition-all ${
                  isSelected
                    ? 'border-sky-500 bg-sky-950/20 shadow-md shadow-sky-500/10'
                    : 'border-slate-800 hover:border-slate-700 hover:bg-slate-900/60'
                }`}
              >
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-white truncate">{zoneName}</span>
                  <span
                    className="text-[11px] sm:text-[10px] font-bold px-1.5 py-0.5 rounded uppercase tracking-wider"
                    style={{ backgroundColor: heat.fill, color: heat.stroke, border: `1px solid ${heat.stroke}` }}
                  >
                    {heat.label}
                  </span>
                </div>

                <div className="mt-2.5 grid grid-cols-2 gap-2 text-xs">
                  <div>
                    <span className="text-[11px] sm:text-[10px] text-slate-500 block">Volume</span>
                    <span className="font-mono font-bold text-slate-200">
                      {cmp}/{att} <span className="text-[11px] sm:text-[10px] text-slate-400 font-normal">({share}%)</span>
                    </span>
                  </div>
                  <div>
                    <span className="text-[11px] sm:text-[10px] text-slate-500 block">Comp %</span>
                    <span className="font-mono font-bold text-emerald-400">{pct}%</span>
                  </div>
                  <div>
                    <span className="text-[11px] sm:text-[10px] text-slate-500 block">CPOE</span>
                    <span
                      className={`font-mono font-bold ${
                        cpoe >= 0 ? 'text-emerald-400' : 'text-rose-400'
                      }`}
                    >
                      {cpoe >= 0 ? '+' : ''}{cpoe.toFixed(1)}%
                    </span>
                  </div>
                  <div>
                    <span className="text-[11px] sm:text-[10px] text-slate-500 block">EPA / Pass</span>
                    <span
                      className={`font-mono font-bold ${
                        epa >= 0 ? 'text-emerald-400' : 'text-rose-400'
                      }`}
                    >
                      {epa >= 0 ? '+' : ''}{epa.toFixed(2)}
                    </span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

export default PassingExplorerClient;
