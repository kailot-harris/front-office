'use client';

import React, { useState, useMemo } from 'react';
import { ClutchProfile } from '@/lib/clutchTypes';
import { PressureResiliencePlot } from '@/components/PressureResiliencePlot';
import {
  Flame,
  Search,
  SlidersHorizontal,
  Award,
  Download,
  Zap,
  CheckCircle2,
  AlertTriangle,
} from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';

interface ClutchClientProps {
  initialProfiles: ClutchProfile[];
}

type SortField =
  | 'clutchPoints'
  | 'clutchFga'
  | 'clutchFgPct'
  | 'clutchPpp'
  | 'clutchScoringPlays';

export const ClutchClient: React.FC<ClutchClientProps> = ({ initialProfiles }) => {
  const [search, setSearch] = useState('');
  const [selectedTeam, setSelectedTeam] = useState('ALL');
  const [selectedPos, setSelectedPos] = useState('ALL');
  const [sortField, setSortField] = useState<SortField>('clutchPoints');
  const [sortAsc, setSortAsc] = useState(false);

  // Default selection: highest clutch points player
  const [selectedPlayerId, setSelectedPlayerId] = useState<string>(() => {
    if (!initialProfiles || initialProfiles.length === 0) return '';
    const sorted = [...initialProfiles].sort(
      (a, b) => (b.clutchPoints ?? -1) - (a.clutchPoints ?? -1)
    );
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
        const valA = a[sortField] ?? -Infinity;
        const valB = b[sortField] ?? -Infinity;
        const diff = (valB as number) - (valA as number);
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
      setSortAsc(false); // default descending for points, fga, fg%, etc.
    }
  };

  const handleExportCsv = () => {
    exportToCsv(
      filteredProfiles as unknown as Record<string, unknown>[],
      [
        { key: 'playerName', label: 'Player' },
        { key: 'team', label: 'Team' },
        { key: 'position', label: 'Pos' },
        { key: 'clutchArchetype', label: 'Clutch Archetype' },
        { key: 'clutchFga', label: 'Clutch FGA' },
        { key: 'clutchPoints', label: 'Clutch Points' },
        { key: 'clutchFgPct', label: 'Clutch FG%' },
        { key: 'clutchPpp', label: 'Clutch PPP' },
        { key: 'clutchScoringPlays', label: 'Scoring Plays' },
        { key: 'provenance', label: 'Provenance' },
      ],
      'clutch-leaderboard'
    );
  };

  const qualifiedClosersCount = useMemo(
    () => initialProfiles.filter((p) => p.clutchFga >= 5 && p.clutchFgPct !== null).length,
    [initialProfiles]
  );

  return (
    <div className="space-y-6">
      {/* Overview Banner */}
      <div className="p-6 rounded-2xl bg-gradient-to-r from-rose-950/40 via-slate-900 to-amber-950/30 border border-rose-900/40 shadow-xl">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <div className="space-y-1.5">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs font-semibold">
              <Flame className="w-3.5 h-3.5 text-rose-400" />
              WNBA True Clutch Performance
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
              High-Leverage Execution & Pressure Resilience
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl">
              Real play-by-play scoring volume, efficiency (Clutch FG%), points per attempt, and scoring plays during the final 5:00 of tight contests (&le; 5 pt margin). Low-sample players (&lt; 5 FGA) emit typed NA to maintain statistical integrity.
            </p>
          </div>

          <div className="flex flex-wrap md:flex-nowrap gap-3">
            <div className="px-4 py-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[110px]">
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Tracked Roster</div>
              <div className="text-xl font-black text-rose-400">{initialProfiles.length}</div>
            </div>
            <div className="px-4 py-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[110px]">
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Active Closers</div>
              <div className="text-xl font-black text-emerald-400">{qualifiedClosersCount}</div>
            </div>
            <div className="px-4 py-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[110px]">
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Leverage Margin</div>
              <div className="text-xl font-black text-amber-400">&le; 5 Pts</div>
            </div>
            <div className="px-4 py-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[110px]">
              <div className="text-[11px] text-slate-400 uppercase font-semibold">Time Window</div>
              <div className="text-xl font-black text-indigo-400">Final 5:00</div>
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
                  <div className="text-[10px] uppercase font-bold text-slate-400">Clutch PTS</div>
                  <div className="text-2xl font-black text-rose-400 font-mono">
                    {selectedProfile.clutchPoints !== null ? selectedProfile.clutchPoints : '—'}
                  </div>
                  <div className="text-[10px] text-slate-500">{selectedProfile.clutchFga} FGA</div>
                </div>
              </div>

              {/* Metric Badges */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 pt-1">
                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Clutch FG%</div>
                  <div className="text-base font-extrabold text-emerald-400">
                    {selectedProfile.clutchFgPct !== null ? `${selectedProfile.clutchFgPct.toFixed(1)}%` : 'N/A'}
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">
                    {selectedProfile.clutchFga >= 5 ? 'Qualified' : 'Low Sample'}
                  </div>
                </div>

                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Points / Shot</div>
                  <div className="text-base font-extrabold text-amber-400">
                    {selectedProfile.clutchPpp !== null ? selectedProfile.clutchPpp.toFixed(2) : 'N/A'}
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">
                    Clutch PPP
                  </div>
                </div>

                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Scoring Plays</div>
                  <div className="text-base font-extrabold text-indigo-400">
                    {selectedProfile.clutchScoringPlays !== null ? selectedProfile.clutchScoringPlays : '—'}
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">
                    Total Plays
                  </div>
                </div>

                <div className="p-2.5 rounded-lg bg-surface border border-slate-800/80 text-center">
                  <div className="text-[10px] text-slate-400 uppercase font-medium">Clutch FGA</div>
                  <div className="text-base font-extrabold text-white">
                    {selectedProfile.clutchFga}
                  </div>
                  <div className="text-[10px] text-slate-500 font-mono">
                    Attempts
                  </div>
                </div>
              </div>

              {/* Provenance & Sample Badge */}
              <div className="p-3 bg-surface/80 rounded-xl border border-slate-800/80 space-y-2">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-slate-400 font-medium">Data Provenance:</span>
                  <span className="font-mono text-[11px] px-2 py-0.5 rounded bg-slate-800 text-slate-200 border border-slate-700">
                    {selectedProfile.provenance}
                  </span>
                </div>
                <div className="flex items-center gap-2 text-[11px] text-slate-400">
                  {selectedProfile.clutchFga >= 5 ? (
                    <>
                      <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                      <span>Sufficient real sample ({selectedProfile.clutchFga} clutch FGA) from official ESPN PBP.</span>
                    </>
                  ) : (
                    <>
                      <AlertTriangle className="w-3.5 h-3.5 text-amber-400 shrink-0" />
                      <span>Insufficient sample ({selectedProfile.clutchFga} clutch FGA). Rate metrics emit typed null.</span>
                    </>
                  )}
                </div>
              </div>
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
                <option value="clutchPoints">Clutch PTS</option>
                <option value="clutchFga">Clutch FGA</option>
                <option value="clutchFgPct">Clutch FG%</option>
                <option value="clutchPpp">Points / FGA (PPP)</option>
                <option value="clutchScoringPlays">Scoring Plays</option>
              </select>
            </div>

            <button
              type="button"
              onClick={handleExportCsv}
              title="Export CSV"
              aria-label="Export clutch leaderboard as CSV"
              data-export-exclude
              className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
            </button>
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
                  onClick={() => handleSort('clutchFga')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  Clutch FGA {sortField === 'clutchFga' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('clutchPoints')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  Clutch PTS {sortField === 'clutchPoints' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('clutchFgPct')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  Clutch FG% {sortField === 'clutchFgPct' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('clutchPpp')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  Points/FGA {sortField === 'clutchPpp' && (sortAsc ? '↑' : '↓')}
                </th>
                <th
                  onClick={() => handleSort('clutchScoringPlays')}
                  className="py-2.5 px-3 font-semibold text-right cursor-pointer hover:text-white"
                >
                  Scoring Plays {sortField === 'clutchScoringPlays' && (sortAsc ? '↑' : '↓')}
                </th>
                <th className="py-2.5 px-3 font-semibold text-right">Provenance</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-mono">
              {filteredProfiles.slice(0, 50).map((p, idx) => {
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
                    <td className="py-2.5 px-3 text-right font-black text-white">
                      {p.clutchFga}
                    </td>
                    <td className="py-2.5 px-3 text-right font-black text-rose-400">
                      {p.clutchPoints !== null ? p.clutchPoints : '—'}
                    </td>
                    <td className="py-2.5 px-3 text-right text-emerald-400">
                      {p.clutchFgPct !== null ? `${p.clutchFgPct.toFixed(1)}%` : 'N/A'}
                    </td>
                    <td className="py-2.5 px-3 text-right text-amber-400">
                      {p.clutchPpp !== null ? p.clutchPpp.toFixed(2) : 'N/A'}
                    </td>
                    <td className="py-2.5 px-3 text-right text-slate-300">
                      {p.clutchScoringPlays !== null ? p.clutchScoringPlays : '—'}
                    </td>
                    <td className="py-2.5 px-3 text-right text-[10px] text-slate-500">
                      {p.provenance}
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
