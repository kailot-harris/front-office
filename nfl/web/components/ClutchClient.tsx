'use client';

import React, { useState, useMemo } from 'react';
import { ClutchProfile } from '@/lib/types';
import { TeamLogo } from './TeamLogo';
import {
  Flame,
  Search,
  Award,
  Download,
  Zap,
  ShieldAlert,
  ArrowUpDown,
  ArrowUpRight,
  ArrowDownRight,
  CheckCircle2,
  Info,
} from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';
import { GlossaryTerm } from './Glossary';
import { HowToRead } from './HowToRead';

interface ClutchClientProps {
  initialProfiles: ClutchProfile[];
}

type SortField =
  | 'clutchEpaDelta'
  | 'clutchEpa'
  | 'baselineEpa'
  | 'clutchSuccessRate'
  | 'clutchCpoe'
  | 'clutchAttempts'
  | 'turnoverFragility'
  | 'fourthDownAggressiveness';

export default function ClutchClient({ initialProfiles }: ClutchClientProps) {
  const [search, setSearch] = useState('');
  const [selectedTeam, setSelectedTeam] = useState('ALL');
  const [sampleFilter, setSampleFilter] = useState<'qualified' | 'all'>('qualified');
  const [sortField, setSortField] = useState<SortField>('clutchEpaDelta');
  const [sortAsc, setSortAsc] = useState(false);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string>(() => {
    const qualified = initialProfiles.filter(
      (p) => p.provenance === 'REAL_CURRENT_SEASON' && p.clutchEpaDelta !== null
    );
    const topCloser = qualified.sort((a, b) => (b.clutchEpaDelta ?? -99) - (a.clutchEpaDelta ?? -99))[0];
    return topCloser?.playerId || initialProfiles[0]?.playerId || '';
  });

  const [hoveredQbId, setHoveredQbId] = useState<string | null>(null);

  // Teams list
  const teams = useMemo(() => {
    const set = new Set<string>();
    initialProfiles.forEach((p) => {
      if (p.team) set.add(p.team);
    });
    return ['ALL', ...Array.from(set).sort()];
  }, [initialProfiles]);

  // Qualified count
  const qualifiedCount = useMemo(() => {
    return initialProfiles.filter((p) => p.provenance === 'REAL_CURRENT_SEASON').length;
  }, [initialProfiles]);

  // Filtered & Sorted profiles
  const filteredProfiles = useMemo(() => {
    return initialProfiles
      .filter((p) => {
        if (sampleFilter === 'qualified' && p.provenance !== 'REAL_CURRENT_SEASON') {
          return false;
        }
        if (selectedTeam !== 'ALL' && p.team !== selectedTeam) {
          return false;
        }
        if (search.trim()) {
          const q = search.toLowerCase();
          const matchName = p.playerName.toLowerCase().includes(q);
          const matchTeam = p.team.toLowerCase().includes(q);
          const matchArch = p.clutchArchetype.toLowerCase().includes(q);
          if (!matchName && !matchTeam && !matchArch) return false;
        }
        return true;
      })
      .sort((a, b) => {
        const valA = a[sortField];
        const valB = b[sortField];

        // Nulls always sort to bottom
        if (valA === null && valB === null) return 0;
        if (valA === null) return 1;
        if (valB === null) return -1;

        const diff = (valB as number) - (valA as number);
        return sortAsc ? -diff : diff;
      });
  }, [initialProfiles, sampleFilter, selectedTeam, search, sortField, sortAsc]);

  // Selected QB profile
  const selectedProfile = useMemo(() => {
    return (
      initialProfiles.find((p) => p.playerId === selectedPlayerId) ||
      filteredProfiles[0] ||
      initialProfiles[0]
    );
  }, [initialProfiles, filteredProfiles, selectedPlayerId]);

  // Top performers KPI calculations
  const kpiHighlights = useMemo(() => {
    const qualified = initialProfiles.filter(
      (p) => p.provenance === 'REAL_CURRENT_SEASON' && p.clutchEpaDelta !== null
    );
    if (qualified.length === 0) return null;

    const topDelta = [...qualified].sort((a, b) => (b.clutchEpaDelta ?? -99) - (a.clutchEpaDelta ?? -99))[0];
    const topCpoe = [...qualified].sort((a, b) => (b.clutchCpoe ?? -99) - (a.clutchCpoe ?? -99))[0];
    const bestBallSecurity = [...qualified].sort((a, b) => (a.turnoverFragility ?? 99) - (b.turnoverFragility ?? 99))[0];

    return { topDelta, topCpoe, bestBallSecurity };
  }, [initialProfiles]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortAsc(!sortAsc);
    } else {
      setSortField(field);
      setSortAsc(false);
    }
  };

  const handleExportCsv = () => {
    exportToCsv(
      filteredProfiles as unknown as Record<string, unknown>[],
      [
        { key: 'playerName', label: 'Player Name' },
        { key: 'team', label: 'Team' },
        { key: 'position', label: 'Position' },
        { key: 'isStarter', label: 'Starter' },
        { key: 'clutchArchetype', label: 'Clutch Archetype' },
        { key: 'clutchAttempts', label: 'Clutch Pass Attempts' },
        { key: 'clutchPlays', label: 'Clutch Dropbacks' },
        { key: 'clutchEpa', label: 'Clutch EPA/Play' },
        { key: 'baselineEpa', label: 'Baseline EPA/Play' },
        { key: 'clutchEpaDelta', label: 'EPA Delta (Clutch - Baseline)' },
        { key: 'clutchSuccessRate', label: 'Clutch Success %' },
        { key: 'baselineSuccessRate', label: 'Baseline Success %' },
        { key: 'clutchCpoe', label: 'Clutch CPOE' },
        { key: 'turnoverFragility', label: 'Turnover Fragility %' },
        { key: 'fourthDownAggressiveness', label: '4th Down Aggressiveness %' },
        { key: 'provenance', label: 'Provenance' },
      ],
      'nfl_clutch_leverage_metrics'
    );
  };

  const getArchetypeBadgeClass = (archetype: string) => {
    switch (archetype) {
      case 'Elite Ice-in-Veins Finisher':
        return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
      case 'High-Leverage Shotmaker':
        return 'bg-cyan-500/10 text-cyan-400 border-cyan-500/30';
      case 'Poised Late-Game Closer':
        return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
      case 'Fragile Under Pressure':
        return 'bg-rose-500/10 text-rose-400 border-rose-500/30';
      case 'Efficient Situational Closer':
        return 'bg-teal-500/10 text-teal-400 border-teal-500/30';
      case 'Game Manager Under Pressure':
        return 'bg-blue-500/10 text-blue-400 border-blue-500/30';
      default:
        return 'bg-slate-800/80 text-slate-400 border-slate-700';
    }
  };

  // Scatter plot parameters
  const scatterQbs = useMemo(() => {
    return initialProfiles.filter(
      (p) =>
        p.clutchEpa !== null &&
        p.baselineEpa !== null &&
        p.clutchEpaDelta !== null &&
        p.provenance === 'REAL_CURRENT_SEASON'
    );
  }, [initialProfiles]);

  const minEpa = -0.35;
  const maxEpa = 0.45;
  const toScatterX = (val: number) => 5 + ((val - minEpa) / (maxEpa - minEpa)) * 90;
  const toScatterY = (val: number) => 95 - ((val - minEpa) / (maxEpa - minEpa)) * 90;

  return (
    <div className="space-y-8 animate-fadeIn">
      {/* Hero Header */}
      <div className="bg-gradient-to-r from-surface-raised via-surface-raised to-emerald-950/20 border border-slate-800 rounded-2xl p-6 sm:p-8 shadow-2xl relative overflow-hidden">
        <div className="absolute top-0 right-0 -mt-10 -mr-10 w-64 h-64 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 relative z-10">
          <div className="space-y-2 max-w-3xl">
            <div className="flex items-center gap-3">
              <span className="p-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 shadow-inner">
                <Flame className="w-6 h-6" />
              </span>
              <span className="text-xs font-mono uppercase tracking-wider font-semibold text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-3 py-1 rounded-full">
                4th Quarter & Late-Game Leverage
              </span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold text-white tracking-tight">
              True Clutch Index & Pressure Resilience
            </h1>
            <p className="text-sm text-slate-400 leading-relaxed">
              Empirical play-by-play execution in high-leverage late-game scenarios: one-score margins (≤ 8 points) in 4Q/OT or 10–90% win probability in the final 5 minutes.
            </p>
          </div>

          <button
            onClick={handleExportCsv}
            className="flex items-center gap-2 px-4 py-2.5 bg-surface border border-slate-700 hover:border-emerald-500/50 rounded-xl text-xs font-semibold text-slate-200 hover:text-white transition-all shadow-md self-start md:self-auto"
          >
            <Download className="w-4 h-4 text-emerald-400" />
            Export CSV ({filteredProfiles.length})
          </button>
        </div>
      </div>

      <HowToRead pageKey="clutch">
        <p>
          &quot;Clutch&quot; is defined narrowly here: plays in one-score games (within 8 points) during the 4th
          quarter or overtime, or any play in the final 5 minutes where win probability is between 10% and 90%
          (i.e. the game is genuinely in doubt). The <strong>Clutch Index</strong> compares a player&apos;s{' '}
          <GlossaryTerm term="EPA" className="text-slate-300" /> in those moments to their own baseline EPA in all
          other situations, so it measures a shift in performance under pressure, not just raw talent.
        </p>
      </HowToRead>

      {/* KPI Cards */}
      {kpiHighlights && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-surface-raised/80 border border-slate-800 p-5 rounded-xl shadow-lg relative overflow-hidden">
            <div className="flex items-center justify-between text-xs font-mono text-slate-400 mb-2">
              <span>Top Clutch Closer (EPA Δ)</span>
              <Award className="w-4 h-4 text-emerald-400" />
            </div>
            <div className="flex items-center gap-3">
              <TeamLogo team={kpiHighlights.topDelta.team} size="md" />
              <div>
                <div className="font-bold text-white text-base">
                  {kpiHighlights.topDelta.playerName}
                </div>
                <div className="text-xs text-emerald-400 font-mono font-semibold flex items-center gap-1">
                  <ArrowUpRight className="w-3.5 h-3.5" />
                  +{(kpiHighlights.topDelta.clutchEpaDelta ?? 0).toFixed(3)} EPA/play
                </div>
              </div>
            </div>
          </div>

          <div className="bg-surface-raised/80 border border-slate-800 p-5 rounded-xl shadow-lg relative overflow-hidden">
            <div className="flex items-center justify-between text-xs font-mono text-slate-400 mb-2">
              <span>Clutch CPOE Leader</span>
              <Zap className="w-4 h-4 text-cyan-400" />
            </div>
            <div className="flex items-center gap-3">
              <TeamLogo team={kpiHighlights.topCpoe.team} size="md" />
              <div>
                <div className="font-bold text-white text-base">
                  {kpiHighlights.topCpoe.playerName}
                </div>
                <div className="text-xs text-cyan-400 font-mono font-semibold flex items-center gap-1">
                  +{(kpiHighlights.topCpoe.clutchCpoe ?? 0).toFixed(1)}% over expected
                </div>
              </div>
            </div>
          </div>

          <div className="bg-surface-raised/80 border border-slate-800 p-5 rounded-xl shadow-lg relative overflow-hidden">
            <div className="flex items-center justify-between text-xs font-mono text-slate-400 mb-2">
              <span>Best Pressure Ball Security</span>
              <CheckCircle2 className="w-4 h-4 text-emerald-400" />
            </div>
            <div className="flex items-center gap-3">
              <TeamLogo team={kpiHighlights.bestBallSecurity.team} size="md" />
              <div>
                <div className="font-bold text-white text-base">
                  {kpiHighlights.bestBallSecurity.playerName}
                </div>
                <div className="text-xs text-emerald-400 font-mono font-semibold flex items-center gap-1">
                  {(kpiHighlights.bestBallSecurity.turnoverFragility ?? 0).toFixed(1)}% TO fragility
                </div>
              </div>
            </div>
          </div>

          <div className="bg-surface-raised/80 border border-slate-800 p-5 rounded-xl shadow-lg relative overflow-hidden">
            <div className="flex items-center justify-between text-xs font-mono text-slate-400 mb-2">
              <span>Qualification Pool</span>
              <Info className="w-4 h-4 text-slate-400" />
            </div>
            <div className="space-y-1">
              <div className="font-bold text-white text-2xl font-mono">
                {qualifiedCount} <span className="text-xs font-normal text-slate-400">/ {initialProfiles.length} QBs</span>
              </div>
              <div className="text-xs text-slate-400">
                Threshold: ≥ 5 clutch attempts (4Q/OT)
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Main Grid: Scatter Matrix + Detail Inspector */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Scatter Matrix (2 cols on large) */}
        <div className="lg:col-span-2 bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl flex flex-col">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-800 gap-2 mb-4">
            <div>
              <h2 className="text-base font-semibold text-white flex items-center gap-2">
                Clutch EPA vs. Baseline Efficiency Matrix
                <span className="text-xs font-mono font-normal text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
                  4Q/OT Delta
                </span>
              </h2>
              <p className="text-xs text-slate-400">
                Points above the dashed diagonal indicate higher EPA in high-leverage late-game moments than regular baseline.
              </p>
            </div>

            <div className="flex items-center gap-3 text-xs font-mono">
              <span className="flex items-center gap-1 text-emerald-400">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-500" /> Ice in Veins
              </span>
              <span className="flex items-center gap-1 text-rose-400">
                <span className="w-2.5 h-2.5 rounded-full bg-rose-500" /> Fragile Under Pressure
              </span>
            </div>
          </div>

          {/* SVG Scatter Chart */}
          <div className="relative w-full h-80 sm:h-96 bg-surface/80 rounded-xl border border-slate-800/80 p-4">
            <svg className="w-full h-full overflow-visible" viewBox="0 0 100 100" preserveAspectRatio="none">
              {/* Grid Lines */}
              <line x1="5" y1="50" x2="95" y2="50" stroke="#334155" strokeWidth="0.4" strokeDasharray="1,1" />
              <line x1="50" y1="5" x2="50" y2="95" stroke="#334155" strokeWidth="0.4" strokeDasharray="1,1" />
              
              {/* Parity Diagonal Line (Clutch EPA == Baseline EPA) */}
              <line
                x1={toScatterX(minEpa)}
                y1={toScatterY(minEpa)}
                x2={toScatterX(maxEpa)}
                y2={toScatterY(maxEpa)}
                stroke="#64748b"
                strokeWidth="0.6"
                strokeDasharray="2,2"
              />

              {/* Data Points */}
              {scatterQbs.map((qb) => {
                const cx = toScatterX(qb.baselineEpa as number);
                const cy = toScatterY(qb.clutchEpa as number);
                const isPositive = (qb.clutchEpaDelta ?? 0) >= 0;
                const isSelected = qb.playerId === selectedProfile.playerId;
                const isHovered = qb.playerId === hoveredQbId;

                return (
                  <g
                    key={qb.playerId}
                    className="cursor-pointer transition-transform duration-150"
                    onClick={() => setSelectedPlayerId(qb.playerId)}
                    onMouseEnter={() => setHoveredQbId(qb.playerId)}
                    onMouseLeave={() => setHoveredQbId(null)}
                  >
                    <circle
                      cx={cx}
                      cy={cy}
                      r={isSelected || isHovered ? 3.2 : 2.2}
                      className={`${
                        isPositive ? 'fill-emerald-400' : 'fill-rose-400'
                      } ${isSelected ? 'stroke-white stroke-[0.8]' : 'stroke-slate-900 stroke-[0.4]'}`}
                      opacity={isSelected || isHovered ? 1 : 0.85}
                    />
                    {(isSelected || isHovered) && (
                      <text
                        x={cx}
                        y={cy - 4}
                        textAnchor="middle"
                        className="text-[3.2px] font-mono fill-white font-bold"
                      >
                        {qb.playerName.split(' ').pop()} ({(qb.clutchEpaDelta ?? 0) > 0 ? '+' : ''}
                        {(qb.clutchEpaDelta ?? 0).toFixed(2)})
                      </text>
                    )}
                  </g>
                );
              })}
            </svg>

            {/* Axis Labels */}
            <div className="absolute bottom-2 left-6 text-[11px] sm:text-[10px] font-mono text-slate-500">
              ← Slower Baseline EPA (-0.35)
            </div>
            <div className="absolute bottom-2 right-6 text-[11px] sm:text-[10px] font-mono text-slate-500">
              Higher Baseline EPA (+0.45) →
            </div>
            <div className="absolute top-2 left-3 text-[11px] sm:text-[10px] font-mono text-emerald-400">
              ↑ Elite Clutch EPA (+0.45)
            </div>
            <div className="absolute bottom-6 left-3 text-[11px] sm:text-[10px] font-mono text-rose-400">
              ↓ Lower Clutch EPA (-0.35)
            </div>
          </div>
        </div>

        {/* Selected QB Inspector Card */}
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
              <span className="text-xs font-mono uppercase text-slate-400 font-semibold tracking-wider">
                Situational Profile
              </span>
              <span
                className={`text-[11px] font-mono px-2.5 py-0.5 rounded-full border font-semibold ${
                  selectedProfile.provenance === 'REAL_CURRENT_SEASON'
                    ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                    : 'bg-slate-800 text-slate-400 border-slate-700'
                }`}
              >
                {selectedProfile.provenance === 'REAL_CURRENT_SEASON' ? 'Qualified Sample' : 'Low Sample'}
              </span>
            </div>

            <div className="flex items-center gap-4 mb-5">
              <div className="w-16 h-16 rounded-2xl bg-surface border border-slate-700 overflow-hidden flex items-center justify-center relative shadow-lg">
                {selectedProfile.headshotUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={selectedProfile.headshotUrl}
                    alt={selectedProfile.playerName}
                    className="w-full h-full object-cover"
                  />
                ) : (
                  <TeamLogo team={selectedProfile.team} size="xl" />
                )}
              </div>
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <TeamLogo team={selectedProfile.team} size="sm" />
                  <span className="font-mono text-xs text-slate-400">
                    {selectedProfile.team} • QB
                  </span>
                  {selectedProfile.isStarter && (
                    <span className="text-[11px] sm:text-[10px] font-mono bg-accent-600/30 text-emerald-300 border border-emerald-500/30 px-1.5 py-0.2 rounded">
                      Starter
                    </span>
                  )}
                </div>
                <h3 className="text-xl font-bold text-white tracking-tight truncate">
                  {selectedProfile.playerName}
                </h3>
                <span
                  className={`inline-block mt-1 text-[11px] font-mono font-semibold px-2 py-0.5 rounded border ${getArchetypeBadgeClass(
                    selectedProfile.clutchArchetype
                  )}`}
                >
                  {selectedProfile.clutchArchetype}
                </span>
              </div>
            </div>

            {/* Metrics Breakdown Grid */}
            {selectedProfile.provenance === 'REAL_CURRENT_SEASON' ? (
              <div className="space-y-3.5 text-xs">
                <div className="bg-surface/80 rounded-lg p-3 border border-slate-800/80 space-y-1.5">
                  <div className="flex justify-between items-center text-slate-400">
                    <span>Clutch EPA vs Baseline</span>
                    <span
                      className={`font-mono font-bold ${
                        (selectedProfile.clutchEpaDelta ?? 0) >= 0 ? 'text-emerald-400' : 'text-rose-400'
                      }`}
                    >
                      {(selectedProfile.clutchEpaDelta ?? 0) >= 0 ? '+' : ''}
                      {(selectedProfile.clutchEpaDelta ?? 0).toFixed(3)}
                    </span>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-[11px] font-mono pt-1 border-t border-slate-800/50">
                    <div>Clutch: {(selectedProfile.clutchEpa ?? 0).toFixed(3)}</div>
                    <div>Base: {(selectedProfile.baselineEpa ?? 0).toFixed(3)}</div>
                  </div>
                </div>

                <div className="bg-surface/80 rounded-lg p-3 border border-slate-800/80 space-y-1.5">
                  <div className="flex justify-between items-center text-slate-400">
                    <span>Success Rate (Clutch vs Base)</span>
                    <span className="font-mono font-bold text-white">
                      {(selectedProfile.clutchSuccessRate ?? 0).toFixed(1)}%
                    </span>
                  </div>
                  <div className="text-[11px] font-mono text-slate-400">
                    Baseline: {(selectedProfile.baselineSuccessRate ?? 0).toFixed(1)}%
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-2">
                  <div className="bg-surface/80 rounded-lg p-3 border border-slate-800/80">
                    <div className="text-slate-400 text-[11px] mb-1">Clutch CPOE</div>
                    <div className="font-mono font-bold text-white text-base">
                      {(selectedProfile.clutchCpoe ?? 0) > 0 ? '+' : ''}
                      {(selectedProfile.clutchCpoe ?? 0).toFixed(1)}%
                    </div>
                  </div>

                  <div className="bg-surface/80 rounded-lg p-3 border border-slate-800/80">
                    <div className="text-slate-400 text-[11px] mb-1">TO Fragility</div>
                    <div
                      className={`font-mono font-bold text-base ${
                        (selectedProfile.turnoverFragility ?? 0) > 0 ? 'text-rose-400' : 'text-emerald-400'
                      }`}
                    >
                      {(selectedProfile.turnoverFragility ?? 0) > 0 ? '+' : ''}
                      {(selectedProfile.turnoverFragility ?? 0).toFixed(1)}%
                    </div>
                  </div>
                </div>

                <div className="bg-surface/80 rounded-lg p-3 border border-slate-800/80 flex items-center justify-between">
                  <span className="text-slate-400">4th Down Aggressiveness</span>
                  <span className="font-mono font-bold text-white">
                    {(selectedProfile.fourthDownAggressiveness ?? 0).toFixed(1)}%
                  </span>
                </div>
              </div>
            ) : (
              <div className="p-6 text-center text-slate-500 bg-surface/40 rounded-xl border border-slate-800/80 space-y-2">
                <ShieldAlert className="w-8 h-8 text-slate-600 mx-auto" />
                <p className="text-xs">
                  Fewer than 5 clutch attempts in current sample ({selectedProfile.clutchAttempts} attempt{selectedProfile.clutchAttempts === 1 ? '' : 's'}). Typed null emitted for rate metrics.
                </p>
              </div>
            )}
          </div>

          <div className="pt-4 border-t border-slate-800/80 text-[11px] font-mono text-slate-500 flex justify-between items-center">
            <span>Clutch Att: {selectedProfile.clutchAttempts}</span>
            <span>Total Drops: {selectedProfile.baselinePlays}</span>
          </div>
        </div>
      </div>

      {/* Leaderboard Table Card */}
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl space-y-4">
        {/* Controls Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-3 border-b border-slate-800">
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-bold text-white">High-Leverage Leaderboard</h2>
            <span className="text-xs font-mono text-slate-400">({filteredProfiles.length} quarterbacks)</span>
          </div>

          <div className="flex items-center gap-3 flex-wrap">
            {/* Search Input */}
            <div className="relative">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search QB, team, archetype..."
                className="pl-9 pr-3 py-1.5 bg-surface border border-slate-700 rounded-lg text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500 w-48 sm:w-56"
              />
            </div>

            {/* Team Filter */}
            <select
              value={selectedTeam}
              onChange={(e) => setSelectedTeam(e.target.value)}
              className="px-3 py-1.5 bg-surface border border-slate-700 rounded-lg text-xs text-white focus:outline-none focus:border-emerald-500 font-mono"
            >
              {teams.map((t) => (
                <option key={t} value={t}>
                  {t === 'ALL' ? 'All Teams' : t}
                </option>
              ))}
            </select>

            {/* Sample Toggle */}
            <div className="flex items-center gap-1 bg-surface border border-slate-800 p-0.5 rounded-lg text-xs font-mono">
              <button
                onClick={() => setSampleFilter('qualified')}
                className={`px-2.5 py-1 rounded-md transition-all ${
                  sampleFilter === 'qualified'
                    ? 'bg-accent-600 text-white font-bold shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Qualified ({qualifiedCount})
              </button>
              <button
                onClick={() => setSampleFilter('all')}
                className={`px-2.5 py-1 rounded-md transition-all ${
                  sampleFilter === 'all'
                    ? 'bg-accent-600 text-white font-bold shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                All ({initialProfiles.length})
              </button>
            </div>
          </div>
        </div>

        {/* Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-slate-400 font-mono">
                <th className="py-2.5 px-3">#</th>
                <th className="py-2.5 px-3">Quarterback</th>
                <th className="py-2.5 px-3">Archetype</th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('clutchAttempts')}
                >
                  <div className="flex items-center gap-1">
                    Att <ArrowUpDown className="w-3 h-3 text-slate-500" />
                  </div>
                </th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('clutchEpa')}
                >
                  <div className="flex items-center gap-1">
                    Clutch EPA <ArrowUpDown className="w-3 h-3 text-slate-500" />
                  </div>
                </th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('baselineEpa')}
                >
                  <div className="flex items-center gap-1">
                    Base EPA <ArrowUpDown className="w-3 h-3 text-slate-500" />
                  </div>
                </th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('clutchEpaDelta')}
                >
                  <div className="flex items-center gap-1 text-emerald-400 font-bold">
                    EPA Delta <ArrowUpDown className="w-3 h-3" />
                  </div>
                </th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('clutchSuccessRate')}
                >
                  <div className="flex items-center gap-1">
                    Success % <ArrowUpDown className="w-3 h-3 text-slate-500" />
                  </div>
                </th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('clutchCpoe')}
                >
                  <div className="flex items-center gap-1">
                    CPOE <ArrowUpDown className="w-3 h-3 text-slate-500" />
                  </div>
                </th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('turnoverFragility')}
                >
                  <div className="flex items-center gap-1">
                    TO Fragility <ArrowUpDown className="w-3 h-3 text-slate-500" />
                  </div>
                </th>
                <th
                  className="py-2.5 px-3 cursor-pointer hover:text-white"
                  onClick={() => handleSort('fourthDownAggressiveness')}
                >
                  <div className="flex items-center gap-1">
                    4th Conv % <ArrowUpDown className="w-3 h-3 text-slate-500" />
                  </div>
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-mono">
              {filteredProfiles.map((p, idx) => {
                const isSelected = p.playerId === selectedProfile.playerId;
                return (
                  <tr
                    key={p.playerId}
                    onClick={() => setSelectedPlayerId(p.playerId)}
                    className={`cursor-pointer transition-colors ${
                      isSelected ? 'bg-emerald-950/20' : 'hover:bg-slate-800/40'
                    }`}
                  >
                    <td className="py-2.5 px-3 text-slate-500 font-mono">{idx + 1}</td>
                    <td className="py-2.5 px-3 font-sans">
                      <div className="flex items-center gap-2.5">
                        <TeamLogo team={p.team} size="sm" />
                        <div>
                          <div className="font-bold text-white flex items-center gap-1.5">
                            {p.playerName}
                            {p.isStarter && (
                              <span className="text-[11px] sm:text-[9px] font-mono bg-emerald-950 text-emerald-400 border border-emerald-800 px-1 rounded">
                                QB1
                              </span>
                            )}
                          </div>
                          <div className="text-[11px] text-slate-400 font-mono">{p.team}</div>
                        </div>
                      </div>
                    </td>
                    <td className="py-2.5 px-3">
                      <span
                        className={`text-[11px] sm:text-[10px] font-semibold px-2 py-0.5 rounded border ${getArchetypeBadgeClass(
                          p.clutchArchetype
                        )}`}
                      >
                        {p.clutchArchetype}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-slate-300">
                      {p.clutchAttempts} <span className="text-slate-500">/ {p.clutchPlays}</span>
                    </td>
                    <td className="py-2.5 px-3">
                      {p.clutchEpa !== null ? (
                        <span className={p.clutchEpa >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                          {p.clutchEpa.toFixed(3)}
                        </span>
                      ) : (
                        <span className="text-slate-600">—</span>
                      )}
                    </td>
                    <td className="py-2.5 px-3 text-slate-400">
                      {p.baselineEpa !== null ? p.baselineEpa.toFixed(3) : '—'}
                    </td>
                    <td className="py-2.5 px-3 font-bold">
                      {p.clutchEpaDelta !== null ? (
                        <span
                          className={`flex items-center gap-0.5 ${
                            p.clutchEpaDelta >= 0 ? 'text-emerald-400' : 'text-rose-400'
                          }`}
                        >
                          {p.clutchEpaDelta >= 0 ? (
                            <ArrowUpRight className="w-3 h-3" />
                          ) : (
                            <ArrowDownRight className="w-3 h-3" />
                          )}
                          {p.clutchEpaDelta > 0 ? '+' : ''}
                          {p.clutchEpaDelta.toFixed(3)}
                        </span>
                      ) : (
                        <span className="text-slate-600">—</span>
                      )}
                    </td>
                    <td className="py-2.5 px-3 text-slate-300">
                      {p.clutchSuccessRate !== null ? `${p.clutchSuccessRate.toFixed(1)}%` : '—'}
                    </td>
                    <td className="py-2.5 px-3">
                      {p.clutchCpoe !== null ? (
                        <span className={p.clutchCpoe >= 0 ? 'text-cyan-400' : 'text-slate-400'}>
                          {p.clutchCpoe > 0 ? '+' : ''}
                          {p.clutchCpoe.toFixed(1)}%
                        </span>
                      ) : (
                        <span className="text-slate-600">—</span>
                      )}
                    </td>
                    <td className="py-2.5 px-3">
                      {p.turnoverFragility !== null ? (
                        <span className={p.turnoverFragility > 0 ? 'text-rose-400' : 'text-emerald-400'}>
                          {p.turnoverFragility > 0 ? '+' : ''}
                          {p.turnoverFragility.toFixed(1)}%
                        </span>
                      ) : (
                        <span className="text-slate-600">—</span>
                      )}
                    </td>
                    <td className="py-2.5 px-3 text-slate-300">
                      {p.fourthDownAggressiveness !== null ? `${p.fourthDownAggressiveness.toFixed(1)}%` : '—'}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
