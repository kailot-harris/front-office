'use client';

import React, { useState, useMemo, useEffect } from 'react';
import { PlayerDnaProfile } from '@/lib/types';
import { TeamLogo } from './TeamLogo';
import { BASE_PATH } from '@/lib/basePath';
import {
  Search,
  Dna,
  ArrowRightLeft,
  X,
  Sparkles,
  Crosshair,
} from 'lucide-react';

interface PlayerDnaClientProps {
  initialProfiles: PlayerDnaProfile[];
  /** Total number of profiles in the full dataset, if more than `initialProfiles` were shipped. */
  totalCount?: number;
}

/**
 * SVG Radar Chart Component
 * Renders multi-dimensional skill polygons for 1 or 2 players simultaneously.
 */
interface RadarChartProps {
  playerA: PlayerDnaProfile;
  playerB?: PlayerDnaProfile | null;
  size?: number;
}

const RadarChart: React.FC<RadarChartProps> = ({ playerA, playerB, size = 320 }) => {
  const center = size / 2;
  const radius = size * 0.36;
  const axes = playerA.radarAxes;
  const numAxes = axes.length;

  // Calculate coordinates on the radar grid
  const getCoords = (val: number, index: number, total: number, rMax: number) => {
    const angle = -Math.PI / 2 + (index * 2 * Math.PI) / total;
    const r = (Math.max(0, Math.min(100, val)) / 100) * rMax;
    return {
      x: center + r * Math.cos(angle),
      y: center + r * Math.sin(angle),
    };
  };

  // Label coordinates slightly outside the outer ring
  const getLabelCoords = (index: number, total: number) => {
    const angle = -Math.PI / 2 + (index * 2 * Math.PI) / total;
    const r = radius + 24;
    return {
      x: center + r * Math.cos(angle),
      y: center + r * Math.sin(angle),
      cos: Math.cos(angle),
    };
  };

  // Polygon points string for player A
  const pointsA = axes
    .map((axis, i) => {
      const { x, y } = getCoords(axis.value, i, numAxes, radius);
      return `${x},${y}`;
    })
    .join(' ');

  // Polygon points string for player B (if comparing)
  const pointsB = playerB
    ? axes
        .map((axisA, i) => {
          // Match by axis key if possible, else index
          const matchAxis = playerB.radarAxes.find((ax) => ax.axis === axisA.axis);
          const val = matchAxis ? matchAxis.value : playerB.radarAxes[i]?.value ?? 50;
          const { x, y } = getCoords(val, i, numAxes, radius);
          return `${x},${y}`;
        })
        .join(' ')
    : '';

  return (
    <div className="relative flex flex-col items-center justify-center p-4 bg-slate-950/80 rounded-2xl border border-slate-800/80 shadow-inner">
      <svg
        width={size}
        height={size}
        className="overflow-visible select-none max-w-full"
        viewBox={`0 0 ${size} ${size}`}
      >
        {/* Concentric grid polygons (25%, 50%, 75%, 100%) */}
        {[0.25, 0.5, 0.75, 1.0].map((level) => {
          const ringPoints = Array.from({ length: numAxes })
            .map((_, i) => {
              const { x, y } = getCoords(level * 100, i, numAxes, radius);
              return `${x},${y}`;
            })
            .join(' ');
          return (
            <polygon
              key={level}
              points={ringPoints}
              fill="none"
              stroke="#1e293b"
              strokeWidth={level === 1.0 ? '1.5' : '1'}
              strokeDasharray={level === 1.0 ? 'none' : '3,3'}
            />
          );
        })}

        {/* Radial Axis Spokes */}
        {axes.map((_, i) => {
          const { x, y } = getCoords(100, i, numAxes, radius);
          return (
            <line
              key={i}
              x1={center}
              y1={center}
              x2={x}
              y2={y}
              stroke="#334155"
              strokeWidth="1"
              strokeDasharray="2,2"
            />
          );
        })}

        {/* Player B Comparison Polygon (Cyan) */}
        {playerB && (
          <g className="transition-all duration-300">
            <polygon
              points={pointsB}
              fill="rgba(6, 182, 212, 0.22)"
              stroke="#06b6d4"
              strokeWidth="2.5"
              className="drop-shadow-[0_0_8px_rgba(6,182,212,0.4)]"
            />
            {axes.map((axisA, i) => {
              const matchAxis = playerB.radarAxes.find((ax) => ax.axis === axisA.axis);
              const val = matchAxis ? matchAxis.value : playerB.radarAxes[i]?.value ?? 50;
              const { x, y } = getCoords(val, i, numAxes, radius);
              return (
                <circle
                  key={`b-${i}`}
                  cx={x}
                  cy={y}
                  r="4"
                  fill="#06b6d4"
                  stroke="#083344"
                  strokeWidth="1.5"
                />
              );
            })}
          </g>
        )}

        {/* Player A Primary Polygon (Emerald) */}
        <polygon
          points={pointsA}
          fill="rgba(16, 185, 129, 0.28)"
          stroke="#10b981"
          strokeWidth="2.5"
          className="drop-shadow-[0_0_12px_rgba(16,185,129,0.4)]"
        />
        {axes.map((axis, i) => {
          const { x, y } = getCoords(axis.value, i, numAxes, radius);
          return (
            <circle
              key={`a-${i}`}
              cx={x}
              cy={y}
              r="4.5"
              fill="#10b981"
              stroke="#064e3b"
              strokeWidth="2"
            />
          );
        })}

        {/* Axis Labels */}
        {axes.map((axis, i) => {
          const { x, y, cos } = getLabelCoords(i, numAxes);
          const anchor = cos > 0.25 ? 'start' : cos < -0.25 ? 'end' : 'middle';
          return (
            <text
              key={`label-${i}`}
              x={x}
              y={y + 4}
              textAnchor={anchor}
              className="text-[10.5px] font-mono font-medium fill-slate-300 pointer-events-none"
            >
              {axis.label} ({axis.value.toFixed(0)})
            </text>
          );
        })}
      </svg>

      {/* Legend */}
      <div className="flex items-center gap-5 mt-3 text-xs font-mono">
        <div className="flex items-center gap-1.5">
          <span className="w-3 h-3 rounded-full bg-emerald-500 shadow-[0_0_6px_#10b981]" />
          <span className="text-emerald-300 font-semibold">{playerA.playerName}</span>
        </div>
        {playerB && (
          <div className="flex items-center gap-1.5">
            <span className="w-3 h-3 rounded-full bg-cyan-400 shadow-[0_0_6px_#06b6d4]" />
            <span className="text-cyan-300 font-semibold">{playerB.playerName}</span>
          </div>
        )}
      </div>
    </div>
  );
};

export default function PlayerDnaClient({ initialProfiles, totalCount }: PlayerDnaClientProps) {
  // #134: the server only sends the first screen of rows (see app/dna/page.tsx). If more exist,
  // fetch the rest from the same JSON file the server read, client-side, so search/filter/compare
  // still work across the full roster without inlining ~900 KB of HTML on every page load.
  const [profiles, setProfiles] = useState<PlayerDnaProfile[]>(initialProfiles);
  const [isLoadingRest, setIsLoadingRest] = useState(
    typeof totalCount === 'number' && totalCount > initialProfiles.length
  );

  useEffect(() => {
    if (!isLoadingRest) return;
    let cancelled = false;
    fetch(`${BASE_PATH}/data/player_dna_profiles.json`)
      .then((res) => {
        if (!res.ok) throw new Error(`Failed to load player DNA dataset: ${res.status}`);
        return res.json() as Promise<PlayerDnaProfile[]>;
      })
      .then((full) => {
        if (!cancelled) setProfiles(full);
      })
      .catch(() => {
        // Keep the initial (partial) set rendered rather than blanking the page.
      })
      .finally(() => {
        if (!cancelled) setIsLoadingRest(false);
      });
    return () => {
      cancelled = true;
    };
    // Only ever needs to run once on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [searchQuery, setSearchQuery] = useState('');
  const [selectedPos, setSelectedPos] = useState<string>('ALL');
  const [selectedTeam, setSelectedTeam] = useState<string>('ALL');
  const [selectedPlayerId, setSelectedPlayerId] = useState<string>(
    initialProfiles.find((p) => p.playerName === 'P.Mahomes')?.playerId || initialProfiles[0]?.playerId
  );
  const [comparePlayerId, setComparePlayerId] = useState<string | null>(null);
  const [isCompareMode, setIsCompareMode] = useState(false);

  // Unique sorted teams list
  const teams = useMemo(() => {
    return Array.from(new Set(profiles.map((p) => p.team))).sort();
  }, [profiles]);

  // Filtered players
  const filteredPlayers = useMemo(() => {
    return profiles.filter((p) => {
      const q = searchQuery.toLowerCase();
      const matchesSearch =
        p.playerName.toLowerCase().includes(q) ||
        p.team.toLowerCase().includes(q) ||
        p.archetype.toLowerCase().includes(q);
      const matchesPos = selectedPos === 'ALL' || p.position === selectedPos;
      const matchesTeam = selectedTeam === 'ALL' || p.team === selectedTeam;
      return matchesSearch && matchesPos && matchesTeam;
    });
  }, [profiles, searchQuery, selectedPos, selectedTeam]);

  // Selected player objects
  const selectedPlayer = useMemo(() => {
    return profiles.find((p) => p.playerId === selectedPlayerId) || filteredPlayers[0] || profiles[0];
  }, [profiles, selectedPlayerId, filteredPlayers]);

  const comparePlayer = useMemo(() => {
    if (!comparePlayerId) return null;
    return profiles.find((p) => p.playerId === comparePlayerId) || null;
  }, [profiles, comparePlayerId]);

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="relative overflow-hidden p-6 rounded-2xl bg-gradient-to-r from-surface via-surface-raised to-surface border border-emerald-500/30 shadow-xl">
        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex flex-wrap items-center gap-2 mb-2">
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center gap-1 font-mono">
                <Dna className="w-3.5 h-3.5" /> High-Dimensional Player DNA
              </span>
              <span className="text-xs text-slate-400 font-mono">
                {profiles.length} Empirical Skill Profiles{isLoadingRest ? ' (loading full roster…)' : ''}
              </span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white font-space">
              Player DNA & Nearest Historical Comparables
            </h1>
            <p className="text-sm text-slate-300 max-w-3xl mt-1.5 leading-relaxed">
              Empirical skill vectors quantifying deep accuracy, pressure resilience, quick game execution, and YAC over expected.
              Profiles are mapped with cosine-similarity matching against iconic NFL historical peaks (1995–2024).
            </p>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => {
                setIsCompareMode(!isCompareMode);
                if (isCompareMode) setComparePlayerId(null);
              }}
              className={`px-3.5 py-2 rounded-xl text-xs font-semibold flex items-center gap-1.5 transition-all shadow-sm ${
                isCompareMode
                  ? 'bg-cyan-500 text-slate-950 shadow-cyan-500/30 font-bold'
                  : 'bg-slate-800 text-slate-200 hover:bg-slate-700 border border-slate-700'
              }`}
            >
              <ArrowRightLeft className="w-4 h-4" />
              {isCompareMode ? 'Exit Compare Mode' : 'Compare 2 Players'}
            </button>
          </div>
        </div>
      </div>

      {/* Main Filter & Search Control Bar */}
      <div className="p-4 rounded-xl bg-surface-raised/80 border border-slate-800/80 shadow-sm flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3">
        {/* Search Input */}
        <div className="relative flex-1 max-w-md">
          <Search className="w-4 h-4 absolute left-3 top-3 text-slate-400" />
          <input
            type="text"
            placeholder="Search player name, team, or archetype..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-4 py-2 text-sm bg-slate-950 border border-slate-800 rounded-lg text-slate-100 placeholder-slate-500 focus:outline-none focus:border-emerald-500 transition-colors"
          />
        </div>

        {/* Position Filter Pills */}
        <div className="flex items-center gap-1 bg-slate-950 p-1 rounded-lg border border-slate-800/80">
          {['ALL', 'QB', 'WR', 'RB', 'TE'].map((pos) => (
            <button
              key={pos}
              onClick={() => setSelectedPos(pos)}
              className={`px-3 py-1 rounded text-xs font-semibold font-mono transition-colors ${
                selectedPos === pos
                  ? 'bg-accent-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {pos}
            </button>
          ))}
        </div>

        {/* Team Dropdown */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-slate-400 font-mono">Team:</span>
          <select
            value={selectedTeam}
            onChange={(e) => setSelectedTeam(e.target.value)}
            aria-label="Filter by NFL team"
            className="px-3 py-1.5 text-xs font-mono bg-slate-950 border border-slate-800 rounded-lg text-slate-200 focus:outline-none focus:border-emerald-500"
          >
            <option value="ALL">All 32 Teams</option>
            {teams.map((tm) => (
              <option key={tm} value={tm}>
                {tm}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Main Grid: Left Roster Directory / Right Detailed Radar & Twin Analysis */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Player Directory (4 cols) */}
        <div className="lg:col-span-4 space-y-3">
          <div className="flex items-center justify-between text-xs font-mono text-slate-400 px-1">
            <span>Starters ({filteredPlayers.length})</span>
            {isCompareMode && (
              <span className="text-cyan-400 font-bold">Select comparison target</span>
            )}
          </div>

          <div className="rounded-xl border border-slate-800/80 bg-surface/50 overflow-hidden divide-y divide-slate-800/60 max-h-[720px] overflow-y-auto">
            {filteredPlayers.slice(0, 80).map((player) => {
              const isSelectedA = player.playerId === selectedPlayer?.playerId;
              const isSelectedB = player.playerId === comparePlayer?.playerId;

              return (
                <button
                  key={player.playerId}
                  onClick={() => {
                    if (isCompareMode) {
                      if (isSelectedA) return;
                      setComparePlayerId(player.playerId);
                    } else {
                      setSelectedPlayerId(player.playerId);
                    }
                  }}
                  className={`w-full text-left p-3 flex items-center justify-between transition-colors ${
                    isSelectedA
                      ? 'bg-emerald-950/40 border-l-4 border-emerald-400'
                      : isSelectedB
                      ? 'bg-cyan-950/40 border-l-4 border-cyan-400'
                      : 'hover:bg-slate-900/40'
                  }`}
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    <TeamLogo team={player.team} size="sm" />
                    <div className="min-w-0">
                      <div className="flex items-center gap-1.5">
                        <span className="font-semibold text-sm text-slate-100 truncate">
                          {player.playerName}
                        </span>
                        <span className="px-1.5 py-0.2 rounded text-[11px] sm:text-[10px] font-mono font-bold bg-slate-800 text-slate-300">
                          {player.position}
                        </span>
                      </div>
                      <p className="text-[11px] text-slate-400 truncate">{player.archetype}</p>
                    </div>
                  </div>

                  <div className="text-right flex-shrink-0 ml-2">
                    <span className="text-xs font-bold font-mono text-emerald-400 block">
                      {player.overallRating.toFixed(1)}
                    </span>
                    <span className="text-[11px] sm:text-[10px] text-slate-500 font-mono uppercase">Rating</span>
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Right Column: Focus Profile, Radar Chart & Comparables (8 cols) */}
        <div className="lg:col-span-8 space-y-6">
          {/* Active Player Card Header */}
          <div className="p-5 rounded-2xl bg-surface-raised border border-slate-800 shadow-md">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800/80 pb-4">
              <div className="flex items-center gap-3.5">
                <TeamLogo team={selectedPlayer.team} size="xl" />
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-2xl font-bold font-space text-white">
                      {selectedPlayer.playerName}
                    </h2>
                    <span className="px-2 py-0.5 rounded text-xs font-mono font-bold bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                      {selectedPlayer.position}
                    </span>
                    <span className="text-xs font-mono text-slate-400">{selectedPlayer.team}</span>
                  </div>
                  <p className="text-sm text-emerald-300/90 font-medium mt-0.5">
                    {selectedPlayer.archetype}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-4">
                <div className="bg-slate-950 p-2.5 rounded-xl border border-slate-800 text-center min-w-[90px]">
                  <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-mono block">
                    DNA Overall
                  </span>
                  <span className="text-2xl font-black font-mono text-emerald-400">
                    {selectedPlayer.overallRating.toFixed(1)}
                  </span>
                </div>
              </div>
            </div>

            {/* Empirical Box Stats Summary Pills */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 mt-4">
              <div className="bg-slate-950/70 p-2.5 rounded-lg border border-slate-800/60">
                <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-mono block">Games</span>
                <span className="text-sm font-bold font-mono text-slate-200">
                  {selectedPlayer.statsSummary.games}
                </span>
              </div>

              {selectedPlayer.position === 'QB' ? (
                <>
                  <div className="bg-slate-950/70 p-2.5 rounded-lg border border-slate-800/60">
                    <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-mono block">
                      Pass Yards / TDs
                    </span>
                    <span className="text-sm font-bold font-mono text-slate-200">
                      {selectedPlayer.statsSummary.passYards} / {selectedPlayer.statsSummary.passTds}
                    </span>
                  </div>
                  <div className="bg-slate-950/70 p-2.5 rounded-lg border border-slate-800/60">
                    <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-mono block">
                      Rush Yards / TDs
                    </span>
                    <span className="text-sm font-bold font-mono text-slate-200">
                      {selectedPlayer.statsSummary.rushYards} / {selectedPlayer.statsSummary.rushTds}
                    </span>
                  </div>
                </>
              ) : (
                <>
                  <div className="bg-slate-950/70 p-2.5 rounded-lg border border-slate-800/60">
                    <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-mono block">
                      Rush / Rec Yards
                    </span>
                    <span className="text-sm font-bold font-mono text-slate-200">
                      {selectedPlayer.statsSummary.rushYards ?? 0} / {selectedPlayer.statsSummary.recYards ?? 0}
                    </span>
                  </div>
                  <div className="bg-slate-950/70 p-2.5 rounded-lg border border-slate-800/60">
                    <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-mono block">
                      Receptions / TDs
                    </span>
                    <span className="text-sm font-bold font-mono text-slate-200">
                      {selectedPlayer.statsSummary.receptions ?? 0} rec / {(selectedPlayer.statsSummary.recTds ?? 0) + (selectedPlayer.statsSummary.rushTds ?? 0)} TD
                    </span>
                  </div>
                </>
              )}

              <div className="bg-slate-950/70 p-2.5 rounded-lg border border-slate-800/60">
                <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-mono block">
                  EPA / Play
                </span>
                <span
                  className={`text-sm font-bold font-mono ${
                    selectedPlayer.statsSummary.epaPerPlay >= 0 ? 'text-emerald-400' : 'text-rose-400'
                  }`}
                >
                  {selectedPlayer.statsSummary.epaPerPlay > 0 ? '+' : ''}
                  {selectedPlayer.statsSummary.epaPerPlay.toFixed(3)}
                </span>
              </div>
            </div>
          </div>

          {/* Comparison Banner if Player B is active */}
          {comparePlayer && (
            <div className="p-3.5 rounded-xl bg-cyan-950/30 border border-cyan-500/30 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <TeamLogo team={comparePlayer.team} size="md" />
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-cyan-400 font-mono uppercase font-bold">
                      Comparing Against:
                    </span>
                    <span className="font-bold text-sm text-white">{comparePlayer.playerName}</span>
                    <span className="text-xs text-slate-400 font-mono">({comparePlayer.position} - {comparePlayer.team})</span>
                  </div>
                  <p className="text-xs text-cyan-200/80">{comparePlayer.archetype}</p>
                </div>
              </div>

              <button
                onClick={() => setComparePlayerId(null)}
                className="p-1 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-white"
                title="Remove comparison"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          )}

          {/* Radar Chart & Dimension Progress Bars */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 items-center">
            {/* SVG Radar Chart */}
            <RadarChart playerA={selectedPlayer} playerB={comparePlayer} size={320} />

            {/* Trait breakdown progress bars */}
            <div className="space-y-3.5 p-4 rounded-xl bg-slate-950/60 border border-slate-800/80">
              <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                <span className="text-xs font-bold font-mono text-slate-300 uppercase tracking-wider">
                  Empirical Percentiles
                </span>
                <span className="text-[11px] font-mono text-slate-500">0 - 100 Scale</span>
              </div>

              {selectedPlayer.radarAxes.map((axis) => {
                const compVal = comparePlayer?.radarAxes.find((ax) => ax.axis === axis.axis)?.value;
                const delta = compVal !== undefined ? axis.value - compVal : null;

                return (
                  <div key={axis.axis} className="space-y-1">
                    <div className="flex items-center justify-between text-xs font-mono">
                      <span className="text-slate-300 font-medium">{axis.label}</span>
                      <div className="flex items-center gap-2">
                        <span className="text-emerald-400 font-bold">{axis.value.toFixed(1)}</span>
                        {delta !== null && (
                          <span
                            className={`text-[11px] sm:text-[10px] font-bold ${
                              delta > 0
                                ? 'text-emerald-400'
                                : delta < 0
                                ? 'text-cyan-400'
                                : 'text-slate-400'
                            }`}
                          >
                            ({delta > 0 ? '+' : ''}
                            {delta.toFixed(1)})
                          </span>
                        )}
                      </div>
                    </div>
                    <div className="h-2 rounded-full bg-slate-800 overflow-hidden relative">
                      <div
                        className="h-full bg-emerald-500 rounded-full transition-all duration-300"
                        style={{ width: `${axis.value}%` }}
                      />
                      {compVal !== undefined && (
                        <div
                          className="h-full bg-cyan-400/80 rounded-full absolute top-0 left-0 transition-all duration-300 opacity-60"
                          style={{ width: `${compVal}%` }}
                        />
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Historical Comparables / Archetype Twins */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Sparkles className="w-4 h-4 text-amber-400" />
                <h3 className="text-base font-bold font-space text-white">
                  Nearest Historical Archetypes & Comparables
                </h3>
              </div>
              <span className="text-xs font-mono text-slate-400">Cosine Similarity Matching</span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {selectedPlayer.historicalTwins.map((twin, idx) => (
                <div
                  key={idx}
                  className="p-3.5 rounded-xl bg-surface-raised border border-slate-800/80 hover:border-emerald-500/40 transition-colors space-y-2"
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="font-bold text-sm text-slate-100">{twin.compName}</span>
                      </div>
                      <p className="text-xs text-emerald-400 font-medium mt-0.5">
                        {twin.archetype}
                      </p>
                    </div>

                    <div className="text-right flex-shrink-0">
                      <span className="text-sm font-bold font-mono text-emerald-300">
                        {twin.similarityPct.toFixed(1)}%
                      </span>
                      <span className="block text-[11px] sm:text-[9px] text-slate-500 uppercase font-mono">
                        Match
                      </span>
                    </div>
                  </div>

                  <div className="w-full bg-slate-800 h-1.5 rounded-full overflow-hidden">
                    <div
                      className="bg-gradient-to-r from-emerald-600 to-emerald-400 h-full rounded-full"
                      style={{ width: `${twin.similarityPct}%` }}
                    />
                  </div>

                  <div className="flex items-center justify-between text-[11px] text-slate-400 font-mono pt-1">
                    <span className="truncate">{twin.keySharedTrait}</span>
                    <span className="px-1.5 py-0.2 rounded bg-slate-800 text-slate-300">
                      Era {twin.era}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* 2D Style Manifold Scatter Embeddings */}
          <div className="p-4 rounded-xl bg-surface-raised/60 border border-slate-800/80 space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Crosshair className="w-4 h-4 text-emerald-400" />
                <h4 className="text-sm font-bold text-slate-200 font-space">
                  2D Stylistic Manifold Projection
                </h4>
              </div>
              <span className="text-xs font-mono text-slate-400">
                {selectedPlayer.position === 'QB'
                  ? 'Verticality vs. Mobility'
                  : 'Explosiveness vs. Workload Volume'}
              </span>
            </div>

            <p className="text-xs text-slate-400">
              Interactive stylistic landscape. Click any node to instantly inspect their DNA radar profile.
            </p>

            <div className="relative h-64 w-full bg-slate-950 rounded-xl border border-slate-800/80 overflow-hidden flex items-center justify-center">
              {/* Axes lines */}
              <div className="absolute inset-y-0 left-1/2 w-px bg-slate-800" />
              <div className="absolute inset-x-0 top-1/2 h-px bg-slate-800" />

              {/* Quadrant labels */}
              <span className="absolute top-2 right-2 text-[11px] sm:text-[10px] font-mono text-slate-600 uppercase">
                {selectedPlayer.position === 'QB' ? 'Gunslinger / Dynamic' : 'High Volume / Explosive'}
              </span>
              <span className="absolute bottom-2 left-2 text-[11px] sm:text-[10px] font-mono text-slate-600 uppercase">
                {selectedPlayer.position === 'QB' ? 'Rhythm / Pocket' : 'Possession / Situational'}
              </span>

              {/* Scatter nodes for filtered players of this position */}
              {filteredPlayers
                .filter((p) => p.position === selectedPlayer.position)
                .slice(0, 70)
                .map((p) => {
                  const isPrimary = p.playerId === selectedPlayer.playerId;
                  const isCompare = p.playerId === comparePlayer?.playerId;

                  // Map manifold coordinates [-50, 50] to [5%, 95%]
                  const left = Math.max(5, Math.min(95, 50 + (p.manifoldX * 0.8)));
                  const top = Math.max(5, Math.min(95, 50 - (p.manifoldY * 0.8)));

                  return (
                    <button
                      key={p.playerId}
                      onClick={() => {
                        if (isCompareMode) {
                          if (p.playerId !== selectedPlayer.playerId) setComparePlayerId(p.playerId);
                        } else {
                          setSelectedPlayerId(p.playerId);
                        }
                      }}
                      title={`${p.playerName} (${p.team}) - ${p.archetype}`}
                      style={{ left: `${left}%`, top: `${top}%` }}
                      className={`absolute -translate-x-1/2 -translate-y-1/2 rounded-full transition-transform hover:scale-150 ${
                        isPrimary
                          ? 'w-4 h-4 bg-emerald-400 ring-4 ring-emerald-500/40 z-20 shadow-[0_0_10px_#10b981]'
                          : isCompare
                          ? 'w-4 h-4 bg-cyan-400 ring-4 ring-cyan-500/40 z-20 shadow-[0_0_10px_#06b6d4]'
                          : 'w-2 h-2 bg-slate-600 hover:bg-slate-300 z-10'
                      }`}
                    />
                  );
                })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
