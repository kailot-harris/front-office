'use client';

import React, { useState } from 'react';
import { ClutchProfile } from '@/lib/clutchTypes';
import { ClutchShotBreakdownCard } from './ClutchShotBreakdownCard';
import { PressureResiliencePlot } from './PressureResiliencePlot';
import { Flame, Search, ChevronRight, Activity, Crosshair, ArrowUpDown, Shield } from 'lucide-react';

interface ClutchClientProps {
  initialProfiles: ClutchProfile[];
}

export const ClutchClient: React.FC<ClutchClientProps> = ({ initialProfiles }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedProfile, setSelectedProfile] = useState<ClutchProfile>(
    initialProfiles.find((p) => p.playerName === 'Luka Doncic') || initialProfiles[0]
  );
  const [selectedArchetypeFilter, setSelectedArchetypeFilter] = useState<string>('ALL');
  const [sortKey, setSortKey] = useState<'usciScore' | 'clutchTsPct' | 'cDwpa' | 'clutchUsgPct'>('usciScore');

  const filteredProfiles = initialProfiles
    .filter((p) => {
      const matchesSearch =
        p.playerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
        p.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
        p.clutchArchetype.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesPos =
        selectedArchetypeFilter === 'ALL' ||
        (selectedArchetypeFilter === 'G' && p.position === 'G') ||
        (selectedArchetypeFilter === 'F' && p.position === 'F') ||
        (selectedArchetypeFilter === 'C' && p.position === 'C');
      return matchesSearch && matchesPos;
    })
    .sort((a, b) => b[sortKey] - a[sortKey]);

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-5 rounded-2xl bg-gradient-to-r from-zinc-900 via-rose-950/20 to-zinc-900 border border-rose-900/30">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-rose-500/10 text-rose-400 border border-rose-500/20 flex items-center gap-1">
              <Flame className="w-3.5 h-3.5" /> True Clutch & Leverage Creation Index
            </span>
            <span className="text-xs text-zinc-500 font-mono">Leverage Index (LI $\le 5$ pts, $\le 5:00$ 4Q)</span>
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-100">
            Late-Game Shot Creation, Efficiency & Defensive Stops
          </h1>
          <p className="text-sm text-zinc-400 max-w-2xl mt-1">
            Filtering non-competitive garbage time to evaluate unassisted isolation scoring (USCI), pressure True Shooting % deltas,
            turnover fragility under late-game blitzes, and clutch defensive stops (c-dWPA).
          </p>
        </div>
      </div>

      {/* Main Grid: Left Roster / Right Focus View */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Leaderboard (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-xl bg-zinc-900/50 border border-zinc-800 space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-zinc-400" />
              <input
                type="text"
                placeholder="Search closer, team, archetype..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-zinc-950 border border-zinc-800 rounded-lg text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-rose-500 transition-colors"
              />
            </div>

            {/* Position Filter Buttons */}
            <div className="flex items-center gap-1.5">
              {[
                { label: 'All Roles', val: 'ALL' },
                { label: 'Guards (G)', val: 'G' },
                { label: 'Wings (F)', val: 'F' },
                { label: 'Bigs (C)', val: 'C' },
              ].map((tab) => (
                <button
                  key={tab.val}
                  onClick={() => setSelectedArchetypeFilter(tab.val)}
                  className={`flex-1 py-1 text-xs font-semibold rounded-md transition-colors ${
                    selectedArchetypeFilter === tab.val
                      ? 'bg-emerald-600 text-white shadow-sm'
                      : 'bg-zinc-800/80 text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {/* Sort Metric Selector */}
            <div className="flex items-center justify-between text-xs text-zinc-400 pt-1">
              <span className="flex items-center gap-1">
                <ArrowUpDown className="w-3 h-3 text-rose-400" /> Sort metric:
              </span>
              <div className="flex gap-2">
                <button
                  onClick={() => setSortKey('usciScore')}
                  className={`underline-offset-2 ${sortKey === 'usciScore' ? 'text-rose-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  USCI
                </button>
                <button
                  onClick={() => setSortKey('clutchTsPct')}
                  className={`underline-offset-2 ${sortKey === 'clutchTsPct' ? 'text-rose-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  Clutch TS%
                </button>
                <button
                  onClick={() => setSortKey('cDwpa')}
                  className={`underline-offset-2 ${sortKey === 'cDwpa' ? 'text-rose-400 underline font-semibold' : 'hover:text-zinc-200'}`}
                >
                  c-dWPA
                </button>
              </div>
            </div>
          </div>

          {/* Player Scroll List */}
          <div className="rounded-xl border border-zinc-800 bg-zinc-900/30 overflow-hidden divide-y divide-zinc-800/60 max-h-[620px] overflow-y-auto">
            {filteredProfiles.slice(0, 50).map((profile) => {
              const isSelected = profile.playerId === selectedProfile.playerId;
              return (
                <button
                  key={profile.playerId}
                  onClick={() => setSelectedProfile(profile)}
                  className={`w-full text-left p-3 flex items-center justify-between transition-colors ${
                    isSelected
                      ? 'bg-rose-950/40 border-l-4 border-l-rose-500 text-zinc-100'
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
                      {profile.clutchArchetype}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="text-right">
                      <div className="text-xs font-bold text-rose-400">
                        {sortKey === 'usciScore'
                          ? `${profile.usciScore}`
                          : sortKey === 'clutchTsPct'
                          ? `${profile.clutchTsPct}%`
                          : `+${profile.cDwpa}%`}
                      </div>
                      <div className="text-[9px] text-zinc-500 uppercase">
                        {sortKey === 'usciScore' ? 'USCI' : sortKey === 'clutchTsPct' ? 'TS%' : 'c-dWPA'}
                      </div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-zinc-500" />
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Right Column: In-Depth Closer Focus Dashboard (8 cols) */}
        <div className="lg:col-span-8 space-y-5">
          {/* Active Profile Header Card */}
          <div className="p-5 rounded-2xl bg-zinc-900/70 border border-zinc-800/90 relative overflow-hidden">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs font-mono px-2 py-0.5 rounded bg-zinc-800 text-rose-400 border border-zinc-700">
                    {selectedProfile.team} · {selectedProfile.position}
                  </span>
                  <span className="text-xs font-medium text-zinc-400">
                    {selectedProfile.clutchMpg} Clutch MPG · {selectedProfile.clutchUsgPct}% USG
                  </span>
                </div>
                <h2 className="text-2xl font-bold text-zinc-100 tracking-tight">
                  {selectedProfile.playerName}
                </h2>
                <p className="text-sm font-semibold text-rose-400 mt-0.5 flex items-center gap-1.5">
                  <Flame className="w-4 h-4" /> {selectedProfile.clutchArchetype}
                </p>
              </div>

              {/* 4 Core Clutch Badges */}
              <div className="flex items-center gap-2.5">
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">USCI</div>
                  <div className="text-base font-bold text-rose-400">{selectedProfile.usciScore}</div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">CLUTCH TS%</div>
                  <div className="text-base font-bold text-zinc-100">{selectedProfile.clutchTsPct}%</div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-[11px] text-zinc-400 font-medium">TS DELTA</div>
                  <div className={`text-base font-bold ${selectedProfile.tsDelta >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                    {selectedProfile.tsDelta >= 0 ? `+${selectedProfile.tsDelta}` : selectedProfile.tsDelta}%
                  </div>
                </div>
                <div className="px-3 py-2 rounded-xl bg-rose-950/60 border border-rose-800/80 text-center">
                  <div className="text-[11px] text-rose-400 font-medium">c-dWPA</div>
                  <div className="text-base font-bold text-rose-200">+{selectedProfile.cDwpa}%</div>
                </div>
              </div>
            </div>
          </div>

          {/* Spatial Clutch Shot Generation Breakdown */}
          <ClutchShotBreakdownCard
            breakdown={selectedProfile.shotBreakdown}
          />

          {/* Pressure Resilience Scatter (TS% vs Turnover Fragility) */}
          <PressureResiliencePlot
            profiles={initialProfiles}
            selectedProfile={selectedProfile}
            onSelectProfile={(p) => setSelectedProfile(p)}
          />

          {/* Explanatory Metric Callout Cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Crosshair className="w-3.5 h-3.5 text-rose-400" />
                Unassisted FGM%: {selectedProfile.unassistedFgmPct}%
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Percentage of clutch baskets scored without a teammate assist, measuring pure late-game isolation engine capacity.
              </p>
            </div>
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Activity className="w-3.5 h-3.5 text-sky-400" />
                Turnover Fragility: {selectedProfile.tovFragility > 0 ? `+${selectedProfile.tovFragility}` : selectedProfile.tovFragility}%
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Shift in turnover rate in 4th-quarter clutch moments. Negative values indicate elite, ice-cold ball security.
              </p>
            </div>
            <div className="p-3.5 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
              <div className="text-xs font-semibold text-zinc-300 flex items-center gap-1.5 mb-1">
                <Shield className="w-3.5 h-3.5 text-emerald-400" />
                Clutch dWPA: +{selectedProfile.cDwpa}%
              </div>
              <p className="text-[11px] text-zinc-400 leading-relaxed">
                Net team win probability added exclusively through late-game defensive stops, contests, deflections, and rebounds.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
