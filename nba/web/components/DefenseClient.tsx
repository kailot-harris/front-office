'use client';

import React, { useState } from 'react';
import { DefensiveProfile } from '@/lib/defenseTypes';
import { MatchupHeatmap } from './MatchupHeatmap';
import { VersatilityScatter } from './VersatilityScatter';
import { Shield, Search, ChevronRight, Activity, Crosshair, ArrowUpDown } from 'lucide-react';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';

interface DefenseClientProps {
  initialProfiles: DefensiveProfile[];
}

export const DefenseClient: React.FC<DefenseClientProps> = ({ initialProfiles }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedProfile, setSelectedProfile] = useState<DefensiveProfile>(
    initialProfiles.find((p) => p.playerName === 'Victor Wembanyama') || initialProfiles[0]
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
      return b[sortKey] - a[sortKey];
    });

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-5 rounded-2xl bg-gradient-to-r from-zinc-900 via-emerald-950/20 to-zinc-900 border border-emerald-900/30">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center gap-1">
              <Shield className="w-3.5 h-3.5" /> Positional Versatility & Coverage Matrix
            </span>
            <span className="text-xs text-zinc-500 font-mono">Shannon Entropy (H<sub>v</sub>) & Tracking Shares</span>
            <SeasonSourceBadge
              season={SEASON_SOURCES.defense.season}
              kind="projection"
              label="Projected season"
              title={SEASON_SOURCES.defense.note}
            />
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-100">
            Defensive Versatility & Rim Protection Architecture
          </h1>
          <p className="text-sm text-zinc-400 max-w-2xl mt-1">
            Quantifying defensive assignment difficulty, 1-through-5 switch entropy, point-of-attack screen navigation,
            and expected field goal suppression at the rim.
          </p>
        </div>
      </div>

      {/* Main Grid: Left Roster / Right Profile View */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Leaderboard (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-xl bg-zinc-900/50 border border-zinc-800 space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-zinc-400" />
              <input
                type="text"
                placeholder="Search defender, team, role..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-zinc-950 border border-zinc-800 rounded-lg text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-emerald-500 transition-colors"
              />
            </div>

            {/* Role Filter Buttons */}
            <div className="flex items-center gap-1.5">
              {[
                { label: 'All Tiers', val: 'ALL' },
                { label: 'Anchors (C)', val: 'ANCHOR' },
                { label: 'Wings (F)', val: 'WING' },
                { label: 'POA (G)', val: 'POA' },
              ].map((tab) => (
                <button
                  key={tab.val}
                  onClick={() => setSelectedRoleFilter(tab.val)}
                  className={`flex-1 py-1 text-xs font-semibold rounded-md transition-colors ${
                    selectedRoleFilter === tab.val
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'bg-zinc-800/80 text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {/* Sort Options */}
            <div className="flex items-center justify-between text-xs text-zinc-400 pt-1">
              <span className="flex items-center gap-1">
                <ArrowUpDown className="w-3 h-3 text-emerald-400" /> Sort metric:
              </span>
              <div className="flex gap-2">
                <button
                  onClick={() => setSortKey('versatilityScore')}
                  className={`underline-offset-2 ${sortKey === 'versatilityScore' ? 'text-emerald-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  H<sub>v</sub> Switch
                </button>
                <button
                  onClick={() => setSortKey('rimDfgDelta')}
                  className={`underline-offset-2 ${sortKey === 'rimDfgDelta' ? 'text-emerald-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  Rim DFG
                </button>
                <button
                  onClick={() => setSortKey('dRapm')}
                  className={`underline-offset-2 ${sortKey === 'dRapm' ? 'text-emerald-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  D-RAPM
                </button>
              </div>
            </div>
          </div>

          {/* Defenders List */}
          <div className="rounded-xl border border-zinc-800 bg-zinc-900/30 overflow-hidden divide-y divide-zinc-800/60 max-h-[620px] overflow-y-auto">
            {filteredProfiles.slice(0, 50).map((profile) => {
              const isSelected = profile.playerId === selectedProfile.playerId;
              return (
                <button
                  key={profile.playerId}
                  onClick={() => setSelectedProfile(profile)}
                  className={`w-full text-left p-3 flex items-center justify-between transition-colors ${
                    isSelected
                      ? 'bg-emerald-950/40 border-l-4 border-l-emerald-500 text-zinc-100'
                      : 'hover:bg-zinc-800/40 text-zinc-300'
                  }`}
                >
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-sm">{profile.playerName}</span>
                      <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400">
                        {profile.team} · {profile.position}
                      </span>
                    </div>
                    <div className="text-xs text-zinc-400 truncate max-w-[210px] mt-0.5">
                      {profile.defensiveRole}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="text-right">
                      <div className="text-xs font-bold text-emerald-400">
                        {sortKey === 'rimDfgDelta'
                          ? `${profile.rimDfgDelta > 0 ? '+' : ''}${profile.rimDfgDelta}%`
                          : sortKey === 'dRapm'
                          ? `${profile.dRapm > 0 ? '+' : ''}${profile.dRapm}`
                          : `${profile.versatilityScore}`}
                      </div>
                      <div className="text-[9px] text-zinc-500 uppercase">
                        {sortKey === 'rimDfgDelta' ? 'Rim Delta' : sortKey === 'dRapm' ? 'D-RAPM' : 'Entropy'}
                      </div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-zinc-500" />
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Right Column: Focus Defender Dashboard (8 cols) */}
        <div className="lg:col-span-8 space-y-5">
          {/* Active Profile Header Card */}
          <div className="p-5 rounded-2xl bg-zinc-900/70 border border-zinc-800/90 relative overflow-hidden">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs font-mono px-2 py-0.5 rounded bg-zinc-800 text-emerald-400 border border-zinc-700">
                    {selectedProfile.team} · {selectedProfile.position}
                  </span>
                  <span className="text-xs font-medium text-zinc-400">
                    {selectedProfile.projMpg} MPG Rotation
                  </span>
                </div>
                <h2 className="text-2xl font-bold text-zinc-100 tracking-tight">
                  {selectedProfile.playerName}
                </h2>
                <p className="text-sm font-semibold text-emerald-400 mt-0.5 flex items-center gap-1.5">
                  <Shield className="w-4 h-4" /> {selectedProfile.defensiveRole}
                </p>
              </div>

              {/* 4 Core Defensive Metrics */}
              <div className="flex items-center gap-2.5">
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">H_VERS</div>
                  <div className="text-base font-bold text-emerald-400">{selectedProfile.versatilityScore}</div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">RIM DFG</div>
                  <div className={`text-base font-bold ${selectedProfile.rimDfgDelta <= -5.0 ? 'text-emerald-400' : 'text-zinc-200'}`}>
                    {selectedProfile.rimDfgDelta > 0 ? `+${selectedProfile.rimDfgDelta}` : selectedProfile.rimDfgDelta}%
                  </div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">POA NAV</div>
                  <div className="text-base font-bold text-zinc-200">{selectedProfile.poaNavigation}</div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-emerald-950/60 border border-emerald-800/80 text-center">
                  <div className="text-[11px] text-emerald-400 font-medium">D-RAPM</div>
                  <div className="text-base font-bold text-emerald-200">
                    {selectedProfile.dRapm > 0 ? `+${selectedProfile.dRapm}` : selectedProfile.dRapm}
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Positional Matchup Heatmap */}
          <MatchupHeatmap dist={selectedProfile.matchupDist} playerName={selectedProfile.playerName} />

          {/* Versatility vs Rim Deterrence 2D Scatter Matrix */}
          <VersatilityScatter
            profiles={initialProfiles}
            selectedProfile={selectedProfile}
            onSelectProfile={(p) => setSelectedProfile(p)}
          />

          {/* Defensive Impact Explanatory Callouts */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Crosshair className="w-3.5 h-3.5 text-emerald-400" />
                Rim Deterrence Index: {selectedProfile.rimDeterrenceIndex}
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Measures how drastically opponents abandon paint attacks when this defender is active on court vs on bench.
              </p>
            </div>
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Activity className="w-3.5 h-3.5 text-sky-400" />
                Screen Navigation: {selectedProfile.poaNavigation} / 100
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Rates avoidance of screen-contact stalls, direct drive recovery, and blow-by prevention on initial ball containment.
              </p>
            </div>
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Shield className="w-3.5 h-3.5 text-indigo-400" />
                Shannon Entropy (H<sub>v</sub>): {selectedProfile.versatilityScore}
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                A score of 100 indicates perfect 20% parity defending all 5 positions without team defensive rotation compromises.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
