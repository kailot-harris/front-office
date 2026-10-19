'use client';

import React, { useState, useMemo } from 'react';
import { PlayerDnaProfile, PlayerDnaCatalog } from '@/lib/playerDnaTypes';
import { SkillFingerprintPolygon } from './SkillFingerprintPolygon';
import { HistoricalTwinCard } from './HistoricalTwinCard';
import { DnaManifoldScatter } from './DnaManifoldScatter';
import { TeamLogo } from '@/components/TeamLogo';
import {
  Dna,
  Search,
  Sparkles,
  ChevronRight,
  Filter,
} from 'lucide-react';

interface PlayerDnaClientProps {
  catalog: PlayerDnaCatalog;
}

export const PlayerDnaClient: React.FC<PlayerDnaClientProps> = ({ catalog }) => {
  const [playerType, setPlayerType] = useState<'Batter' | 'Pitcher'>('Batter');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedArchetype, setSelectedArchetype] = useState<string>('ALL');

  // Filter profiles by player type
  const typeProfiles = useMemo(() => {
    return catalog.profiles.filter((p) => p.playerType === playerType);
  }, [catalog.profiles, playerType]);

  // Selected player state
  const [selectedPlayer, setSelectedPlayer] = useState<PlayerDnaProfile>(
    typeProfiles[0] || catalog.profiles[0]
  );

  // When switching playerType, reset selected player to first in that pool
  const handleTypeSwitch = (type: 'Batter' | 'Pitcher') => {
    setPlayerType(type);
    setSelectedArchetype('ALL');
    const firstInPool = catalog.profiles.find((p) => p.playerType === type);
    if (firstInPool) setSelectedPlayer(firstInPool);
  };

  // Distinct archetypes in current pool
  const availableArchetypes = useMemo(() => {
    const archs = new Set<string>();
    typeProfiles.forEach((p) => archs.add(p.archetype));
    return ['ALL', ...Array.from(archs).sort()];
  }, [typeProfiles]);

  // Filtered player directory
  const filteredPlayers = useMemo(() => {
    return typeProfiles.filter((p) => {
      const matchesSearch =
        p.playerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
        p.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
        p.archetype.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesArch = selectedArchetype === 'ALL' || p.archetype === selectedArchetype;
      return matchesSearch && matchesArch;
    });
  }, [typeProfiles, searchQuery, selectedArchetype]);

  // Format 16-D skill vector keys for readable display
  const skillEntries = useMemo(() => {
    if (!selectedPlayer?.skillVector) return [];
    return Object.entries(selectedPlayer.skillVector).map(([key, val]) => {
      const label = key
        .replace(/_/g, ' ')
        .replace(/\b\w/g, (c) => c.toUpperCase());
      return { key, label, val: val as number };
    });
  }, [selectedPlayer]);

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-sky-950/30 to-slate-900 border border-sky-900/30 rounded-2xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute right-0 top-0 bottom-0 w-96 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-sky-500/10 via-indigo-500/5 to-transparent pointer-events-none" />

        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-1.5">
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-sky-500/10 text-sky-400 border border-sky-500/20 flex items-center gap-1 font-mono">
                <Dna className="w-3.5 h-3.5" /> High-Dimensional Player DNA
              </span>
              <span className="text-xs text-slate-400 font-mono">16-D Statcast Skill Manifold</span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
              Player DNA & Nearest Historical Twins (1980–2026)
            </h1>
            <p className="text-sm text-slate-300 max-w-2xl mt-1">
              High-dimensional vector embedding classifying MLB hitters and pitchers into modern tactical archetypes.
              Identifies top nearest historical comparables using cosine similarity against peak seasons from 1980 to 2026.
            </p>
          </div>

          {/* Batter / Pitcher Toggle */}
          <div className="flex items-center gap-2 bg-slate-950/80 p-1.5 rounded-xl border border-slate-800 self-start lg:self-auto font-mono text-xs">
            <button
              type="button"
              onClick={() => handleTypeSwitch('Batter')}
              className={`px-4 py-2 rounded-lg font-bold transition-all ${
                playerType === 'Batter'
                  ? 'bg-sky-600 text-white shadow-md shadow-sky-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Batters (160 Pool)
            </button>
            <button
              type="button"
              onClick={() => handleTypeSwitch('Pitcher')}
              className={`px-4 py-2 rounded-lg font-bold transition-all ${
                playerType === 'Pitcher'
                  ? 'bg-amber-600 text-white shadow-md shadow-amber-600/30'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Pitchers (160 Pool)
            </button>
          </div>
        </div>
      </div>

      {/* Main 12-Column Analysis Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Directory Roster (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-2xl bg-slate-900/90 border border-slate-800 shadow-xl space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3.5 text-slate-400" />
              <input
                type="text"
                placeholder={`Search ${playerType} by name, team, or archetype...`}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-4 py-2.5 bg-slate-950 rounded-xl border border-slate-800 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-sky-500 font-mono"
              />
            </div>

            {/* Archetype Filter Dropdown */}
            <div className="flex items-center gap-2">
              <Filter className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
              <select
                value={selectedArchetype}
                onChange={(e) => setSelectedArchetype(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-sky-500 font-mono cursor-pointer truncate"
              >
                {availableArchetypes.map((arch) => (
                  <option key={arch} value={arch}>
                    {arch === 'ALL' ? `All Archetypes (${typeProfiles.length})` : arch}
                  </option>
                ))}
              </select>
            </div>

            {/* Player Roster List */}
            <div className="space-y-1.5 max-h-[580px] overflow-y-auto pr-1">
              {filteredPlayers.map((p) => {
                const isSelected = p.playerId === selectedPlayer?.playerId;
                return (
                  <div
                    key={p.playerId}
                    onClick={() => setSelectedPlayer(p)}
                    className={`flex items-center justify-between p-2.5 rounded-xl border cursor-pointer transition-all ${
                      isSelected
                        ? 'bg-sky-950/40 border-sky-500/60 shadow-lg shadow-sky-500/10'
                        : 'bg-slate-950/60 border-slate-800/80 hover:bg-slate-800/50 hover:border-slate-700'
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
                        <p className="text-[10.5px] text-slate-400 font-mono truncate">{p.archetype}</p>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 flex-shrink-0">
                      <div className="text-right font-mono">
                        <span className="text-xs font-bold text-sky-400 block">{p.overallRating} OVR</span>
                        <span className="text-[10px] text-slate-500">z: {p.compositeZscore}</span>
                      </div>
                      <ChevronRight className={`w-4 h-4 ${isSelected ? 'text-sky-400' : 'text-slate-600'}`} />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Middle Column: Player Focus Profile & 16-D Breakdown (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          {/* Headline Card */}
          <div className="p-5 rounded-2xl bg-slate-900/90 border border-slate-800 shadow-xl space-y-4">
            <div className="flex items-center justify-between border-b border-slate-800/80 pb-3">
              <div className="flex items-center gap-3">
                <TeamLogo team={selectedPlayer.team} size="lg" />
                <div>
                  <h2 className="text-xl font-extrabold text-white">{selectedPlayer.playerName}</h2>
                  <div className="flex items-center gap-2 text-xs font-mono text-slate-400 mt-0.5">
                    <span>{selectedPlayer.team}</span>
                    <span>•</span>
                    <span>{selectedPlayer.position}</span>
                    <span>•</span>
                    <span>Age {selectedPlayer.age}</span>
                  </div>
                </div>
              </div>

              <div className="text-right font-mono">
                <span className="text-2xl font-black text-white">{selectedPlayer.overallRating}</span>
                <span className="text-[10px] text-sky-400 block font-bold">DNA SCORE</span>
              </div>
            </div>

            {/* Archetype Badge */}
            <div className="p-3 bg-slate-950/80 rounded-xl border border-sky-500/30 flex items-center justify-between">
              <div>
                <span className="text-[10px] uppercase font-mono font-bold text-slate-400 block">Classified Archetype</span>
                <span className="text-sm font-bold text-sky-300 font-mono">{selectedPlayer.archetype}</span>
              </div>
              <Sparkles className="w-5 h-5 text-amber-400 flex-shrink-0" />
            </div>

            {/* Headline Key Stats Grid */}
            <div className="grid grid-cols-4 gap-2 text-center font-mono text-xs">
              <div className="bg-slate-950 p-2 rounded-lg border border-slate-800">
                <span className="text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.stat1Label}</span>
                <span className="font-bold text-white text-xs">{selectedPlayer.headlineStats.stat1Val}</span>
              </div>
              <div className="bg-slate-950 p-2 rounded-lg border border-slate-800">
                <span className="text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.stat2Label}</span>
                <span className="font-bold text-white text-xs">{selectedPlayer.headlineStats.stat2Val}</span>
              </div>
              <div className="bg-slate-950 p-2 rounded-lg border border-slate-800">
                <span className="text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.stat3Label}</span>
                <span className="font-bold text-white text-xs">{selectedPlayer.headlineStats.stat3Val}</span>
              </div>
              <div className="bg-slate-950 p-2 rounded-lg border border-slate-800">
                <span className="text-[10px] text-slate-400 block">{selectedPlayer.headlineStats.countLabel}</span>
                <span className="font-bold text-amber-400 text-xs">{selectedPlayer.headlineStats.countVal}</span>
              </div>
            </div>

            {/* Radar Polygon */}
            <SkillFingerprintPolygon
              playerType={playerType}
              categoryScores={selectedPlayer.categoryScores}
            />

            {/* 16-D Individual Vector Progress Bars */}
            <div className="space-y-2 pt-2 border-t border-slate-800/80">
              <span className="text-[10.5px] uppercase font-mono font-bold text-slate-400 tracking-wider block">
                16-Dimensional Skill Vector Breakdown
              </span>
              <div className="grid grid-cols-2 gap-2 text-xs font-mono">
                {skillEntries.map((item) => (
                  <div key={item.key} className="bg-slate-950/60 p-2 rounded-lg border border-slate-800/50 space-y-1">
                    <div className="flex justify-between text-[10.5px]">
                      <span className="text-slate-400 truncate">{item.label}</span>
                      <span className="font-bold text-white">{item.val}</span>
                    </div>
                    <div className="w-full bg-slate-900 h-1.5 rounded-full overflow-hidden">
                      <div
                        className={`h-full rounded-full ${playerType === 'Batter' ? 'bg-sky-500' : 'bg-amber-500'}`}
                        style={{ width: `${item.val}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Right Column: Historical Twins & 2D Manifold Scatter (4 cols) */}
        <div className="lg:col-span-4 space-y-6">
          {/* Historical Twins List */}
          <div className="p-5 rounded-2xl bg-slate-900/90 border border-slate-800 shadow-xl space-y-3.5">
            <div className="flex items-center justify-between border-b border-slate-800/80 pb-3">
              <div>
                <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
                  Top 5 Historical Twins
                </h3>
                <p className="text-xs text-slate-400">Cosine Similarity (1980–2026 Era)</p>
              </div>
              <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-bold">
                Cosine Comps
              </span>
            </div>

            <div className="space-y-2.5">
              {selectedPlayer.historicalTwins.map((twin, idx) => (
                <HistoricalTwinCard key={idx} twin={twin} rank={idx + 1} />
              ))}
            </div>
          </div>

          {/* 2D Stylistic Manifold Projection */}
          <DnaManifoldScatter
            players={typeProfiles}
            selectedPlayer={selectedPlayer}
            onSelectPlayer={setSelectedPlayer}
            playerType={playerType}
          />
        </div>
      </div>
    </div>
  );
};
