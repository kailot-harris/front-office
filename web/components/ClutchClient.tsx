'use client';

import React, { useState, useMemo } from 'react';
import { ClutchProfile } from '@/lib/clutchTypes';
import { PressureResiliencePlot } from '@/components/PressureResiliencePlot';
import { ClutchShotBreakdownCard } from '@/components/ClutchShotBreakdownCard';
import {
  Flame,
  Search,
  SlidersHorizontal,
  Sparkles,
  Zap,
  Award,
} from 'lucide-react';

interface ClutchClientProps {
  initialProfiles: ClutchProfile[];
}

type SortField =
  | 'usciScore'
  | 'clutchTsPct'
  | 'tsDelta'
  | 'tovFragility'
  | 'cDwpa'
  | 'clutchMpg'
  | 'clutchUsgPct';

export const ClutchClient: React.FC<ClutchClientProps> = ({ initialProfiles }) => {
  const [search, setSearch] = useState('');
  const [selectedTeam, setSelectedTeam] = useState('ALL');
  const [selectedPos, setSelectedPos] = useState('ALL');
  const [sortField, setSortField] = useState<SortField>('usciScore');
  const [sortAsc, setSortAsc] = useState(false);

  // Default selection: highest USCI player
  const [selectedPlayerId, setSelectedPlayerId] = useState<string>(() => {
    if (!initialProfiles || initialProfiles.length === 0) return '';
    const sorted = [...initialProfiles].sort((a, b) => b.usciScore - a.usciScore);
    return sorted[0]?.playerId || '';
  });

  const teams = useMemo(() => {
    const set = new Set<string>();
    initialProfiles.forEach((p) => {
      if (p.team) set.add(p.team);
    });
    return ['ALL', ...Array.from(set).sort()];
  }, [initialProfiles]);

  const filteredProfiles = useMemo(() => {
    return initialProfiles
      .filter((p) => {
        if (selectedTeam !== 'ALL' && p.team !== selectedTeam) return false;
        if (selectedPos !== 'ALL' && !p.position.includes(selectedPos)) return false;
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
        let diff = 0;
        if (sortField === 'tovFragility') {
          // Lower fragility is better
          diff = a.tovFragility - b.tovFragility;
        } else {
          diff = (b[sortField] ?? 0) - (a[sortField] ?? 0);
        }
        return sortAsc ? -diff : diff;
      });
  }, [initialProfiles, selectedTeam, selectedPos, search, sortField, sortAsc]);

  const selectedProfile = useMemo(() => {
    return (
      initialProfiles.find((p) => p.playerId === selectedPlayerId) ||
      filteredProfiles[0] ||
      null
    );
  }, [initialProfiles, filteredProfiles, selectedPlayerId]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortAsc(!sortAsc);
    } else {
      setSortField(field);
      setSortAsc(field === 'tovFragility'); // default ascending for fragility
    }
  };

  return (
    <div className="space-y-6">
      {/* Overview Banner */}
      <div className="p-6 rounded-2xl bg-gradient-to-r from-rose-950/40 via-slate-900 to-amber-950/30 border border-rose-900/40 shadow-xl">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <div className="space-y-1.5">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs font-semibold">
              <Flame className="w-3.5 h-3.5 text-rose-400" />
              WNBA True Clutch Index (TCI)
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
              High-Leverage Execution & Pressure Resilience
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl">
              Decomposing isolation shot generation, unassisted True Shooting delta (&Delta;TS%),
              turnover fragility, and win probability added during the final 5:00 of tight contests (&le; 5 pt margin).
            </p>
          </div>

          <div className="flex flex-wrap md:flex-nowrap gap-3">
            <div className="px-4 py-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[110px]">
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Tracked Closers</div>
              <div className="text-xl font-black text-rose-400">{initialProfiles.length}</div>
            </div>
            <div className="px-4 py-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[110px]">
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Leverage Margin</div>
              <div className="text-xl font-black text-amber-400">&le; 5 Pts</div>
            </div>
            <div className="px-4 py-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[110px]">
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Time Window</div>
              <div className="text-xl font-black text-emerald-400">Final 5:00</div>
            </div>
          </div>
        </div>
      </div>

      {/* Top Interactive Section: Scatter Plot & Deep Dive */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Scatter Matrix (7 cols) */}
        <div className="lg:col-span-7">
          <PressureResiliencePlot
            profiles={initialProfiles}
            selectedPlayerId={selectedProfile?.playerId || ''}
            onSelectPlayer={(id) => setSelectedPlayerId(id)}
          />
        </div>

        {/* Selected Player Deep Dive (5 cols) */}
        <div className="lg:col-span-5 space-y-4">
          {selectedProfile ? (
            <div className="p-5 rounded-2xl bg-surface-raised/80 border border-slate-800 shadow-lg space-y-4">
              {/* Header */}
              <div className="flex items-start justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-rose-500/10 text-rose-400 border border-rose-500/30">
                      {selectedProfile.team}
                    </span>
                    <span className="text-xs font-mono text-slate-400">
                      {selectedProfile.position}
                    </span>
                  </div>
                  <h3 className="text-xl font-extrabold text-white mt-1">
                    {selectedProfile.playerName}
                  </h3>
                  <div className="text-xs font-semibold text-indigo-400 mt-0.5 flex items-center gap-1.5">
                    <Award className="w-3.5 h-3.5 text-indigo-400" />
                    {selectedProfile.clutchArchetype}
                  </div>
                </div>

                <div className="text-right">
                  <div className="text-[10px] uppercase font-bold text-slate-400">USCI Rating</div>
                  <div className="text-2xl font-black text-rose-400 font-mono">
                    {selectedProfile.usciScore.toFixed(0)}
                  </div>
                  <div className="text-[10px] text-slate-500">Percentile 90+</div>
                </div>
              </div>

              {/* Metric Badges */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 pt-1">
                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Clutch TS%</div>
                  <div className="text-base font-extrabold text-emerald-400">
                    {selectedProfile.clutchTsPct.toFixed(1)}%
                  </div>
                  <div className={`text-[10px] font-mono font-bold ${selectedProfile.tsDelta >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                    {selectedProfile.tsDelta >= 0 ? `+${selectedProfile.tsDelta.toFixed(1)}%` : `${selectedProfile.tsDelta.toFixed(1)}%`} vs Reg
                  </div>
                </div>

                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Clutch USG%</div>
                  <div className="text-base font-extrabold text-amber-400">
                    {selectedProfile.clutchUsgPct.toFixed(1)}%
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">
                    {selectedProfile.clutchMpg.toFixed(1)} Clutch MPG
                  </div>
                </div>

                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Turnover Fragility</div>
                  <div className={`text-base font-extrabold ${selectedProfile.tovFragility <= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                    {selectedProfile.tovFragility >= 0 ? `+${selectedProfile.tovFragility.toFixed(1)}%` : `${selectedProfile.tovFragility.toFixed(1)}%`}
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">
                    ΔTOV% Pressure
                  </div>
                </div>

                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Clutch dWPA</div>
                  <div className={`text-base font-extrabold ${selectedProfile.cDwpa >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                    {selectedProfile.cDwpa >= 0 ? `+${selectedProfile.cDwpa.toFixed(2)}%` : `${selectedProfile.cDwpa.toFixed(2)}%`}
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">Defensive Win Prob</div>
                </div>
              </div>

              {/* Unassisted Shot Creation Bar */}
              <div className="p-3 bg-surface/80 rounded-xl border border-slate-800/80 space-y-1.5">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-slate-300 font-medium flex items-center gap-1.5">
                    <Sparkles className="w-3.5 h-3.5 text-indigo-400" />
                    Unassisted Shot Creation Rate
                  </span>
                  <span className="font-mono font-bold text-indigo-400">
                    {selectedProfile.unassistedFgmPct.toFixed(1)}%
                  </span>
                </div>
                <div className="w-full bg-slate-800 rounded-full h-2 overflow-hidden">
                  <div
                    className="bg-indigo-500 h-full rounded-full transition-all duration-300"
                    style={{ width: `${Math.min(100, selectedProfile.unassistedFgmPct)}%` }}
                  />
                </div>
                <div className="flex justify-between text-[10px] text-slate-500 font-mono">
                  <span>Assisted / Catch-and-Shoot</span>
                  <span>Self-Created Iso / Dribble Pullup</span>
                </div>
              </div>

              {/* Shot Breakdown Card */}
              <ClutchShotBreakdownCard breakdown={selectedProfile.shotBreakdown} />
            </div>
          ) : (
            <div className="p-12 text-center text-slate-500 bg-surface-raised/40 rounded-xl border border-slate-800">
              Select a player to view detailed clutch analytics
            </div>
          )}
        </div>
      </div>

      {/* Leaderboard Table Controls */}
      <div className="p-4 bg-surface-raised/60 rounded-xl border border-slate-800 space-y-4">
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
          <div className="relative flex-1 max-w-md">
            <Search className="w-4 h-4 absolute left-3 top-3 text-slate-400" />
            <input
              type="text"
              placeholder="Search closer by name, team, archetype..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-4 py-2 bg-surface border border-slate-800 rounded-lg text-sm text-slate-100 placeholder-slate-500 focus:outline-none focus:border-rose-500"
            />
          </div>

          <div className="flex items-center gap-3 overflow-x-auto pb-1 sm:pb-0">
            {/* Team Filter */}
            <div className="flex items-center gap-1 text-xs">
              <span className="text-slate-400 font-medium">Team:</span>
              <select
                value={selectedTeam}
                onChange={(e) => setSelectedTeam(e.target.value)}
                className="bg-surface border border-slate-800 text-slate-200 text-xs rounded-lg px-2.5 py-1.5 focus:outline-none focus:border-rose-500 font-mono"
              >
                {teams.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </div>

            {/* Position Filter */}
            <div className="flex items-center gap-1 text-xs">
              <span className="text-slate-400 font-medium">Pos:</span>
              <select
                value={selectedPos}
                onChange={(e) => setSelectedPos(e.target.value)}
                className="bg-surface border border-slate-800 text-slate-200 text-xs rounded-lg px-2.5 py-1.5 focus:outline-none focus:border-rose-500 font-mono"
              >
                <option value="ALL">ALL</option>
                <option value="G">Guard (G)</option>
                <option value="F">Forward (F)</option>
                <option value="C">Center (C)</option>
              </select>
            </div>

            {/* Sort Field */}
            <div className="flex items-center gap-1 text-xs">
              <SlidersHorizontal className="w-3.5 h-3.5 text-slate-400" />
              <select
                value={sortField}
                onChange={(e) => handleSort(e.target.value as SortField)}
                className="bg-surface border border-slate-800 text-slate-200 text-xs rounded-lg px-2.5 py-1.5 focus:outline-none focus:border-rose-500 font-mono"
              >
                <option value="usciScore">USCI Rating</option>
                <option value="clutchTsPct">Clutch TS%</option>
                <option value="tsDelta">TS% Delta</option>
                <option value="tovFragility">Turnover Fragility</option>
                <option value="cDwpa">Clutch dWPA</option>
                <option value="clutchUsgPct">Clutch USG%</option>
                <option value="clutchMpg">Clutch MPG</option>
              </select>
            </div>
          </div>
        </div>

        {/* Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-slate-400 bg-surface/40">
                <th className="py-2.5 px-3 font-semibold">Rank</th>
                <th className="py-2.5 px-3 font-semibold">Player</th>
                <th className="py-2.5 px-3 font-semibold">Team</th>
                <th className="py-2.5 px-3 font-semibold">Pos</th>
                <th className="py-2.5 px-3 font-semibold">Clutch Archetype</th>
                <th
                  onClick={() => handleSort('usciScore')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  USCI {sortField === 'usciScore' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('clutchTsPct')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  Clutch TS% {sortField === 'clutchTsPct' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('tsDelta')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  ΔTS% {sortField === 'tsDelta' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('tovFragility')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  ΔTOV% {sortField === 'tovFragility' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('clutchUsgPct')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  Clutch USG% {sortField === 'clutchUsgPct' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('cDwpa')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  c-dWPA {sortField === 'cDwpa' && (sortAsc ? '↑' : '↓')}
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-mono">
              {filteredProfiles.slice(0, 40).map((p, idx) => {
                const isSelected = p.playerId === selectedProfile?.playerId;
                return (
                  <tr
                    key={p.playerId}
                    onClick={() => setSelectedPlayerId(p.playerId)}
                    className={`cursor-pointer transition-colors ${
                      isSelected
                        ? 'bg-rose-950/30 text-white font-semibold'
                        : 'hover:bg-slate-800/40 text-slate-300'
                    }`}
                  >
                    <td className="py-2.5 px-3 text-slate-500 font-mono">{idx + 1}</td>
                    <td className="py-2.5 px-3 font-sans font-bold flex items-center gap-1.5">
                      {isSelected && <Zap className="w-3 h-3 text-rose-400 shrink-0" />}
                      <span className={isSelected ? 'text-rose-300' : 'text-slate-100'}>
                        {p.playerName}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-slate-400">{p.team}</td>
                    <td className="py-2.5 px-3 text-slate-400">{p.position}</td>
                    <td className="py-2.5 px-3 font-sans text-[11px] text-indigo-400">
                      {p.clutchArchetype}
                    </td>
                    <td className="py-2.5 px-3 text-right font-black text-rose-400">
                      {p.usciScore.toFixed(0)}
                    </td>
                    <td className="py-2.5 px-3 text-right text-emerald-400">
                      {p.clutchTsPct.toFixed(1)}%
                    </td>
                    <td className="py-2.5 px-3 text-right">
                      <span
                        className={`px-1.5 py-0.5 rounded text-[10px] ${
                          p.tsDelta >= 0
                            ? 'bg-emerald-950 text-emerald-400 border border-emerald-800'
                            : 'bg-rose-950 text-rose-400 border border-rose-800'
                        }`}
                      >
                        {p.tsDelta >= 0 ? `+${p.tsDelta.toFixed(1)}%` : `${p.tsDelta.toFixed(1)}%`}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-right">
                      <span
                        className={`text-[11px] ${
                          p.tovFragility <= 0 ? 'text-emerald-400' : 'text-rose-400'
                        }`}
                      >
                        {p.tovFragility >= 0 ? `+${p.tovFragility.toFixed(1)}%` : `${p.tovFragility.toFixed(1)}%`}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-right text-amber-400">
                      {p.clutchUsgPct.toFixed(1)}%
                    </td>
                    <td className="py-2.5 px-3 text-right">
                      <span
                        className={
                          p.cDwpa >= 0 ? 'text-emerald-400' : 'text-rose-400'
                        }
                      >
                        {p.cDwpa >= 0 ? `+${p.cDwpa.toFixed(2)}%` : `${p.cDwpa.toFixed(2)}%`}
                      </span>
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
};
