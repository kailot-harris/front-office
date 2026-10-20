'use client';

import React, { useState, useMemo } from 'react';
import { ClutchProfile, ClutchCatalog } from '@/lib/clutchTypes';
import { PressureResiliencePlot } from './PressureResiliencePlot';
import { LeverageDistributionBar } from './LeverageDistributionBar';
import { FiremanLeaderboardCard } from './FiremanLeaderboardCard';
import { TeamLogo } from '@/components/TeamLogo';
import {
  Flame,
  Search,
  Sparkles,
  ChevronRight,
  Filter,
  ArrowUpDown,
} from 'lucide-react';

interface ClutchClientProps {
  catalog: ClutchCatalog;
}

export const ClutchClient: React.FC<ClutchClientProps> = ({ catalog }) => {
  const [playerType, setPlayerType] = useState<'Batter' | 'Pitcher'>('Batter');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedArchetype, setSelectedArchetype] = useState<string>('ALL');
  const [sortKey, setSortKey] = useState<'clutchScore' | 'deltaClutch' | 'highLiWpa' | 'wpaTotal'>('clutchScore');

  // Filter profiles by player type
  const typeProfiles = useMemo(() => {
    return catalog.profiles.filter((p) => p.playerType === playerType);
  }, [catalog.profiles, playerType]);

  // Selected player state
  const [selectedProfile, setSelectedProfile] = useState<ClutchProfile>(
    typeProfiles[0] || catalog.profiles[0]
  );

  // Switch type handler
  const handleTypeSwitch = (type: 'Batter' | 'Pitcher') => {
    setPlayerType(type);
    setSelectedArchetype('ALL');
    const firstInPool = catalog.profiles.find((p) => p.playerType === type);
    if (firstInPool) setSelectedProfile(firstInPool);
  };

  // Archetypes in current pool
  const availableArchetypes = useMemo(() => {
    const archs = new Set<string>();
    typeProfiles.forEach((p) => archs.add(p.clutchArchetype));
    return ['ALL', ...Array.from(archs).sort()];
  }, [typeProfiles]);

  // Filter and sort roster
  const filteredProfiles = useMemo(() => {
    return typeProfiles
      .filter((p) => {
        const matchesSearch =
          p.playerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
          p.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
          p.clutchArchetype.toLowerCase().includes(searchQuery.toLowerCase());
        const matchesArch = selectedArchetype === 'ALL' || p.clutchArchetype === selectedArchetype;
        return matchesSearch && matchesArch;
      })
      .sort((a, b) => {
        if (sortKey === 'deltaClutch' && playerType === 'Pitcher') {
          // For pitchers, negative delta (suppressing wOBA against) is better
          return a.deltaClutch - b.deltaClutch;
        }
        return b[sortKey] - a[sortKey];
      });
  }, [typeProfiles, searchQuery, selectedArchetype, sortKey, playerType]);

  const isBatter = playerType === 'Batter';

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-rose-950/30 to-slate-900 border border-rose-900/30 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute right-0 top-0 bottom-0 w-96 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-rose-500/10 via-amber-500/5 to-transparent pointer-events-none" />

        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-1.5">
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-rose-500/10 text-rose-400 border border-rose-500/20 flex items-center gap-1 font-mono">
                <Flame className="w-3.5 h-3.5" /> True Clutch & Leverage Index Engine
              </span>
              <span className="text-xs text-slate-400 font-mono">Tom Tango Leverage Index (LI &ge; 1.50)</span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
              Late-Game Shot Creation, Pressure Resilience & Firemen
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl mt-1">
              Filtering blowout garbage time to evaluate batter pressure wOBA resilience, 2-out RISP conversion,
              Win Probability Added (WPA), and reliever inherited runner stranding (IRS%).
            </p>
          </div>

          {/* Batter / Pitcher Toggle */}
          <div className="flex items-center gap-2 bg-surface/80 p-1.5 rounded-xl border border-slate-800 self-start lg:self-auto font-mono text-xs">
            <button
              type="button"
              onClick={() => handleTypeSwitch('Batter')}
              className={`px-4 py-2 rounded-lg font-bold transition-all ${
                playerType === 'Batter'
                  ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Clutch Hitters (150)
            </button>
            <button
              type="button"
              onClick={() => handleTypeSwitch('Pitcher')}
              className={`px-4 py-2 rounded-lg font-bold transition-all ${
                playerType === 'Pitcher'
                  ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Relief Firemen (150)
            </button>
          </div>
        </div>
      </div>

      {/* Main 12-Column Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Leaderboard (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-2xl bg-surface-raised/90 border border-slate-800 shadow-xl space-y-3">
            {/* Search Input */}
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3.5 text-slate-400" />
              <input
                type="text"
                placeholder={`Search ${playerType} by name, team, or archetype...`}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-4 py-2.5 bg-surface rounded-xl border border-slate-800 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-rose-500 font-mono"
              />
            </div>

            {/* Filter & Sort Controls */}
            <div className="grid grid-cols-2 gap-2">
              <div className="flex items-center gap-1.5">
                <Filter className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
                <select
                  value={selectedArchetype}
                  onChange={(e) => setSelectedArchetype(e.target.value)}
                  className="w-full bg-surface border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-rose-500 font-mono truncate"
                >
                  {availableArchetypes.map((arch) => (
                    <option key={arch} value={arch}>
                      {arch === 'ALL' ? 'All Archetypes' : arch}
                    </option>
                  ))}
                </select>
              </div>

              <div className="flex items-center gap-1.5">
                <ArrowUpDown className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
                <select
                  value={sortKey}
                  onChange={(e) => setSortKey(e.target.value as 'clutchScore' | 'deltaClutch' | 'highLiWpa' | 'wpaTotal')}
                  className="w-full bg-surface border border-slate-800 rounded-lg px-2 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-rose-500 font-mono"
                >
                  <option value="clutchScore">Sort: Clutch Score</option>
                  <option value="deltaClutch">Sort: ΔwOBA Pressure</option>
                  <option value="highLiWpa">Sort: High-LI WPA</option>
                  <option value="wpaTotal">Sort: Total WPA</option>
                </select>
              </div>
            </div>

            {/* Leaderboard Roster */}
            <div className="space-y-1.5 max-h-[580px] overflow-y-auto pr-1">
              {filteredProfiles.map((p) => {
                const isSelected = p.playerId === selectedProfile?.playerId;
                const isGoodDelta = isBatter ? p.deltaClutch >= 0 : p.deltaClutch <= 0;

                return (
                  <div
                    key={p.playerId}
                    onClick={() => setSelectedProfile(p)}
                    className={`flex items-center justify-between p-2.5 rounded-xl border cursor-pointer transition-all ${
                      isSelected
                        ? 'bg-rose-950/40 border-rose-500/60 shadow-lg shadow-rose-500/10'
                        : 'bg-surface/60 border-slate-800/80 hover:bg-slate-800/50 hover:border-slate-700'
                    }`}
                  >
                    <div className="flex items-center gap-2.5 min-w-0">
                      <TeamLogo team={p.team} size="sm" />
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5">
                          <span className="font-bold text-xs text-white truncate">{p.playerName}</span>
                          <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-slate-400">
                            {p.position}
                          </span>
                        </div>
                        <p className="text-[10.5px] text-slate-400 font-mono truncate">{p.clutchArchetype}</p>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 flex-shrink-0">
                      <div className="text-right font-mono">
                        <span className="text-xs font-bold text-rose-400 block">
                          {p.clutchScore > 0 ? `+${p.clutchScore}` : p.clutchScore} CLUTCH
                        </span>
                        <span
                          className={`text-[10px] font-bold ${
                            isGoodDelta ? 'text-emerald-400' : 'text-slate-500'
                          }`}
                        >
                          Δ {p.deltaClutch > 0 ? `+${p.deltaClutch}` : p.deltaClutch}
                        </span>
                      </div>
                      <ChevronRight className={`w-4 h-4 ${isSelected ? 'text-rose-400' : 'text-slate-600'}`} />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Middle Column: Player Focus Profile & Pressure Resilience Plot (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          {/* Focus Headline Card */}
          <div className="p-5 rounded-2xl bg-surface-raised/90 border border-slate-800 shadow-xl space-y-4">
            <div className="flex items-center justify-between border-b border-slate-800/80 pb-3">
              <div className="flex items-center gap-3">
                <TeamLogo team={selectedProfile.team} size="lg" />
                <div>
                  <h2 className="text-xl font-extrabold text-white">{selectedProfile.playerName}</h2>
                  <div className="flex items-center gap-2 text-xs font-mono text-slate-400 mt-0.5">
                    <span>{selectedProfile.team}</span>
                    <span>•</span>
                    <span>{selectedProfile.position}</span>
                    <span>•</span>
                    <span>{selectedProfile.avgLeverageIndex.toFixed(2)} pLI</span>
                  </div>
                </div>
              </div>

              <div className="text-right font-mono">
                <span className="text-2xl font-black text-rose-400">
                  {selectedProfile.clutchScore > 0 ? `+${selectedProfile.clutchScore}` : selectedProfile.clutchScore}
                </span>
                <span className="text-[10px] text-slate-400 block font-bold">TANGO CLUTCH</span>
              </div>
            </div>

            {/* Archetype Badge */}
            <div className="p-3 bg-surface/80 rounded-xl border border-rose-500/30 flex items-center justify-between">
              <div>
                <span className="text-[10px] uppercase font-mono font-bold text-slate-400 block">Classified Leverage Role</span>
                <span className="text-sm font-bold text-rose-300 font-mono">{selectedProfile.clutchArchetype}</span>
              </div>
              <Sparkles className="w-5 h-5 text-rose-400 flex-shrink-0" />
            </div>

            {/* Base vs High-LI Metric Comparison Grid */}
            <div className="grid grid-cols-3 gap-2 text-center font-mono text-xs">
              <div className="bg-surface p-2 rounded-lg border border-slate-800">
                <span className="text-[10px] text-slate-400 block">{selectedProfile.baseMetricLabel}</span>
                <span className="font-bold text-white text-xs">{selectedProfile.baseMetricVal.toFixed(3)}</span>
              </div>
              <div className="bg-surface p-2 rounded-lg border border-slate-800">
                <span className="text-[10px] text-slate-400 block">{selectedProfile.clutchMetricLabel}</span>
                <span className="font-bold text-sky-400 text-xs">{selectedProfile.clutchMetricVal.toFixed(3)}</span>
              </div>
              <div className="bg-surface p-2 rounded-lg border border-slate-800">
                <span className="text-[10px] text-slate-400 block">Pressure Delta</span>
                <span
                  className={`font-black text-xs ${
                    (isBatter ? selectedProfile.deltaClutch >= 0 : selectedProfile.deltaClutch <= 0)
                      ? 'text-emerald-400'
                      : 'text-rose-400'
                  }`}
                >
                  {selectedProfile.deltaClutch > 0 ? `+${selectedProfile.deltaClutch}` : selectedProfile.deltaClutch}
                </span>
              </div>
            </div>

            {/* Total WPA & High-LI WPA Breakdown */}
            <div className="grid grid-cols-2 gap-2 text-xs font-mono">
              <div className="bg-surface/80 p-2.5 rounded-xl border border-slate-800/60">
                <span className="text-[10px] text-slate-400 block">Total Season WPA</span>
                <span className="text-base font-bold text-white">
                  {selectedProfile.wpaTotal > 0 ? `+${selectedProfile.wpaTotal.toFixed(2)}` : selectedProfile.wpaTotal.toFixed(2)} Wins
                </span>
              </div>
              <div className="bg-surface/80 p-2.5 rounded-xl border border-slate-800/60">
                <span className="text-[10px] text-slate-400 block">High-Leverage WPA (LI &ge; 1.5)</span>
                <span className="text-base font-bold text-rose-400">
                  {selectedProfile.highLiWpa > 0 ? `+${selectedProfile.highLiWpa.toFixed(2)}` : selectedProfile.highLiWpa.toFixed(2)} Wins
                </span>
              </div>
            </div>
          </div>

          {/* Pressure Resilience Scatter Plot */}
          <PressureResiliencePlot
            profiles={typeProfiles}
            selectedProfile={selectedProfile}
            onSelectProfile={setSelectedProfile}
            playerType={playerType}
          />
        </div>

        {/* Right Column: Leverage Distribution & Fireman/RISP Cards (4 cols) */}
        <div className="lg:col-span-4 space-y-6">
          {/* Leverage State Distribution Bar */}
          <LeverageDistributionBar
            breakdown={selectedProfile.leverageBreakdown}
            avgLeverageIndex={selectedProfile.avgLeverageIndex}
          />

          {/* Fireman Reliever / Batter 2-Out RISP Card */}
          <FiremanLeaderboardCard profile={selectedProfile} />
        </div>
      </div>
    </div>
  );
};
