'use client';

import React, { useState } from 'react';
import { DefensiveProfile } from '@/lib/defenseTypes';
import { DRAPM_POOLED_SEASON_LABEL, dRapmMeta, dRapmColorClass } from '@/lib/defenseTypes';
import { MatchupHeatmap } from './MatchupHeatmap';
import { VersatilityScatter } from './VersatilityScatter';
import { TeamLogo } from '@/components/TeamLogo';
import { Shield, Search, ChevronRight, Activity, Crosshair } from 'lucide-react';

interface DefenseClientProps {
  initialProfiles: DefensiveProfile[];
}

export const DefenseClient: React.FC<DefenseClientProps> = ({ initialProfiles }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedProfile, setSelectedProfile] = useState<DefensiveProfile>(
    initialProfiles.find((p) => p.playerName.includes("A'ja Wilson")) || initialProfiles[0]
  );
  const [selectedRoleFilter, setSelectedRoleFilter] = useState<string>('ALL');
  const [sortKey, setSortKey] = useState<'versatilityScore' | 'rimDfgDelta' | 'dRapm' | 'poaNavigation'>('versatilityScore');

  const filteredProfiles = initialProfiles
    .filter((p) => {
      const matchesSearch =
        p.playerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
        p.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
        p.defensiveRole.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesRole =
        selectedRoleFilter === 'ALL' ||
        (selectedRoleFilter === 'ANCHOR' && p.position === 'C') ||
        (selectedRoleFilter === 'WING' && p.position === 'F') ||
        (selectedRoleFilter === 'POA' && p.position === 'G');
      return matchesSearch && matchesRole;
    })
    .sort((a, b) => {
      if (sortKey === 'rimDfgDelta') return a.rimDfgDelta - b.rimDfgDelta; // Lower (more negative) is better
      if (sortKey === 'dRapm') {
        // dRapm is zero-centred (0 = league average), so plain descending order is
        // correct — but a heuristic estimate is not on the same scale as a fitted
        // dRAPM, so never interleave the two: rank all fitted values first.
        const aReal = a.dRapmSource !== 'heuristic_fallback';
        const bReal = b.dRapmSource !== 'heuristic_fallback';
        if (aReal !== bReal) return aReal ? -1 : 1;
        return b.dRapm - a.dRapm;
      }
      return b[sortKey] - a[sortKey];
    });

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-5 rounded-2xl bg-gradient-to-r from-slate-900 via-indigo-950/30 to-slate-900 border border-slate-800 shadow-xl">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 flex items-center gap-1">
              <Shield className="w-3.5 h-3.5" /> Positional Versatility & Coverage Matrix
            </span>
            <span className="text-xs text-slate-500 font-mono">Shannon Entropy (H<sub>v</sub>) & Tracking Shares</span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            Defensive Versatility & Rim Protection Architecture
          </h1>
          <p className="text-sm text-slate-300 max-w-2xl mt-1">
            Quantifying 1-through-5 switch entropy across all 15 WNBA rosters, rim contest field goal suppression,
            point-of-attack screen navigation, and ridge-fitted defensive RAPM.
          </p>
          <p className="text-xs text-slate-400 max-w-2xl mt-2">
            Defensive RAPM comes from the ridge fit over {DRAPM_POOLED_SEASON_LABEL} seasons — a
            multi-season career-to-date rating, not a 2026-only one — where 0 is league average and
            higher is better defence. The {' '}
            <span className="text-amber-400 font-semibold">amber &ldquo;est.&rdquo;</span> players had
            no matching RAPM row, so they show a heuristic estimate from rebounds and assists instead;
            that estimate is not RAPM and is not comparable to the fitted values.
          </p>
        </div>
      </div>

      {/* Main Grid: Left Roster / Right Profile View */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Leaderboard (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-xl bg-surface-raised/50 border border-slate-800 space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-slate-400" />
              <input
                type="text"
                placeholder="Search defender, team, role..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-surface border border-slate-800 rounded-lg text-slate-200 placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
              />
            </div>

            {/* Role Filter Buttons */}
            <div className="flex items-center gap-1.5 flex-wrap">
              {[
                { label: 'All Tiers', val: 'ALL' },
                { label: 'Anchors (C)', val: 'ANCHOR' },
                { label: 'Wings (F)', val: 'WING' },
                { label: 'POA Guards (G)', val: 'POA' },
              ].map((rf) => (
                <button
                  key={rf.val}
                  onClick={() => setSelectedRoleFilter(rf.val)}
                  className={`px-2.5 py-1 text-xs rounded-md font-medium transition-colors ${
                    selectedRoleFilter === rf.val
                      ? 'bg-accent-600 text-white'
                      : 'bg-surface text-slate-400 hover:text-slate-200 border border-slate-800'
                  }`}
                >
                  {rf.label}
                </button>
              ))}
            </div>

            {/* Sort Key Selector */}
            <div className="flex items-center justify-between text-xs text-slate-400 pt-1 border-t border-slate-800/80">
              <span>Sort leaderboard by:</span>
              <select
                value={sortKey}
                onChange={(e) =>
                  setSortKey(
                    e.target.value as 'versatilityScore' | 'rimDfgDelta' | 'dRapm' | 'poaNavigation'
                  )
                }
                className="bg-surface border border-slate-800 rounded px-2 py-0.5 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
              >
                <option value="versatilityScore">Versatility Score (H_v)</option>
                <option value="rimDfgDelta">Rim DFG% Delta (Low is Best)</option>
                <option value="poaNavigation">POA Screen Nav</option>
                <option value="dRapm">Defensive Rating (dRAPM, est. where unmatched)</option>
              </select>
            </div>
          </div>

          {/* Defenders List */}
          <div className="space-y-2 max-h-[640px] overflow-y-auto pr-1">
            {filteredProfiles.map((p) => {
              const isSelected = p.playerId === selectedProfile.playerId;
              return (
                <div
                  key={p.playerId}
                  onClick={() => setSelectedProfile(p)}
                  className={`p-3 rounded-xl border transition-all cursor-pointer flex items-center justify-between gap-3 ${
                    isSelected
                      ? 'bg-accent-950/30 border-accent-500/50 shadow-md shadow-accent-500/10'
                      : 'bg-surface-raised/40 border-slate-800/80 hover:border-slate-700'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <TeamLogo team={p.team} size="sm" />
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-sm font-bold text-slate-100">{p.playerName}</span>
                        <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-slate-400">
                          {p.position}
                        </span>
                      </div>
                      <div className="text-[11px] text-slate-400 truncate max-w-[180px]">
                        {p.defensiveRole}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 text-right">
                    <div>
                      <div className="text-[10px] text-slate-400">
                        {sortKey === 'rimDfgDelta'
                          ? 'Rim Δ'
                          : sortKey === 'poaNavigation'
                          ? 'POA'
                          : sortKey === 'dRapm'
                          ? dRapmMeta(p).badge
                          : 'H_vers'}
                      </div>
                      <div
                        className={`text-xs font-mono font-bold ${
                          sortKey === 'dRapm'
                            ? dRapmColorClass(p)
                            : sortKey === 'rimDfgDelta' && p.rimDfgDelta <= -5
                            ? 'text-emerald-400'
                            : 'text-indigo-400'
                        }`}
                      >
                        {sortKey === 'rimDfgDelta'
                          ? `${p.rimDfgDelta}%`
                          : sortKey === 'poaNavigation'
                          ? p.poaNavigation
                          : sortKey === 'dRapm'
                          ? `${p.dRapm > 0 ? '+' : ''}${p.dRapm.toFixed(2)}`
                          : p.versatilityScore}
                      </div>
                    </div>
                    <ChevronRight
                      className={`w-4 h-4 text-slate-500 transition-transform ${
                        isSelected ? 'text-accent-400 translate-x-0.5' : ''
                      }`}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right Column: Deep-Dive Dossier (8 cols) */}
        <div className="lg:col-span-8 space-y-6">
          {/* Header Card */}
          <div className="p-6 rounded-2xl bg-surface-raised/60 border border-slate-800 shadow-xl space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800 pb-4">
              <div className="flex items-center gap-4">
                <TeamLogo team={selectedProfile.team} size="lg" />
                <div>
                  <div className="flex items-center gap-2">
                    <h2 className="text-xl sm:text-2xl font-extrabold text-white">
                      {selectedProfile.playerName}
                    </h2>
                    <span className="px-2 py-0.5 rounded text-xs font-mono font-bold bg-slate-800 text-indigo-400 border border-slate-700">
                      {selectedProfile.team} • {selectedProfile.position}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-xs text-slate-400 font-medium">Role:</span>
                    <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-indigo-500/10 text-indigo-300 border border-indigo-500/30">
                      {selectedProfile.defensiveRole}
                    </span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-3">
                <div className="p-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[90px]">
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">Versatility H_v</div>
                  <div className="text-lg font-black text-indigo-400">{selectedProfile.versatilityScore}</div>
                </div>
                <div className="p-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[90px]">
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">Rim DFG Δ</div>
                  <div
                    className={`text-lg font-black ${
                      selectedProfile.rimDfgDelta <= -5.0 ? 'text-emerald-400' : 'text-slate-200'
                    }`}
                  >
                    {selectedProfile.rimDfgDelta > 0 ? `+${selectedProfile.rimDfgDelta}` : selectedProfile.rimDfgDelta}%
                  </div>
                </div>
              </div>
            </div>

            {/* Key Metric Gauges */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 pt-1">
              <div className="p-3 bg-surface/50 rounded-xl border border-slate-800">
                <div className="flex items-center gap-1.5 text-xs text-slate-400 mb-1">
                  <Shield className="w-3.5 h-3.5 text-indigo-400" />
                  <span>POA Screen Nav</span>
                </div>
                <div className="text-base font-bold text-slate-100">{selectedProfile.poaNavigation} / 100</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Pick-and-roll navigation</div>
              </div>

              <div className="p-3 bg-surface/50 rounded-xl border border-slate-800">
                <div className="flex items-center gap-1.5 text-xs text-slate-400 mb-1">
                  <Crosshair className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Rim Deterrence</span>
                </div>
                <div className="text-base font-bold text-emerald-400">+{selectedProfile.rimDeterrenceIndex}</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Attempts suppressed/100</div>
              </div>

              <div className="p-3 bg-surface/50 rounded-xl border border-slate-800">
                <div className="flex items-center gap-1.5 text-xs text-slate-400 mb-1">
                  <Activity className="w-3.5 h-3.5 text-amber-400" />
                  <span>{dRapmMeta(selectedProfile).label}</span>
                </div>
                <div className={`text-base font-bold ${dRapmColorClass(selectedProfile)}`}>
                  {selectedProfile.dRapm > 0
                    ? `+${selectedProfile.dRapm.toFixed(2)}`
                    : selectedProfile.dRapm.toFixed(2)}
                  {!dRapmMeta(selectedProfile).isReal && (
                    <span className="ml-1.5 text-[10px] font-semibold uppercase tracking-wide text-amber-400">
                      est.
                    </span>
                  )}
                  {selectedProfile.dRapmAmbiguous && (
                    <span className="ml-1.5 text-[10px] font-semibold uppercase tracking-wide text-slate-400">
                      shared surname
                    </span>
                  )}
                </div>
                <div className="text-[10px] text-slate-500 mt-0.5">
                  Pts saved / 100 poss · {dRapmMeta(selectedProfile).caption}
                </div>
              </div>

              <div className="p-3 bg-surface/50 rounded-xl border border-slate-800">
                <div className="text-xs text-slate-400 mb-1">Projected MPG</div>
                <div className="text-base font-bold text-slate-100">{selectedProfile.projMpg} MPG</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Rotation workload</div>
              </div>
            </div>

            {/* Matchup Distribution Heatmap */}
            <MatchupHeatmap dist={selectedProfile.matchupDist} playerName={selectedProfile.playerName} />
          </div>

          {/* Versatility vs Rim Scatter Explorer */}
          <VersatilityScatter
            profiles={filteredProfiles}
            selectedProfile={selectedProfile}
            onSelectProfile={(p) => setSelectedProfile(p)}
          />
        </div>
      </div>
    </div>
  );
};
