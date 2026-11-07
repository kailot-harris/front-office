'use client';

import React, { useState } from 'react';
import { PlayerDnaProfile, SkillVector } from '@/lib/playerDnaTypes';
import { SkillFingerprintPolygon } from './SkillFingerprintPolygon';
import { DnaManifoldScatter } from './DnaManifoldScatter';
import { TeamLogo } from '@/components/TeamLogo';
import { Search, Dna, BarChart3, ChevronRight, Users } from 'lucide-react';

interface PlayerDnaClientProps {
  initialProfiles: PlayerDnaProfile[];
}

const SKILL_DIMENSION_LABELS: Record<keyof SkillVector, string> = {
  rim_fg: 'Rim FG%',
  paint_power: 'Paint Power',
  cns_3p: 'Catch & Shoot 3P',
  pullup_3p: 'Pull-Up 3P',
  ft_pct: 'Free Throw %',
  ast_pct: 'Assist Rate',
  tov_control: 'Ball Security',
  rim_protection: 'Rim Protection',
  perimeter_havoc: 'Perimeter Havoc',
  d_rapm: 'Defensive RAPM',
  oreb: 'Off. Rebounding',
  dreb: 'Def. Rebounding',
};

export const PlayerDnaClient: React.FC<PlayerDnaClientProps> = ({ initialProfiles }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedPlayer, setSelectedPlayer] = useState<PlayerDnaProfile>(
    initialProfiles.find((p) => p.playerName.includes("A'ja Wilson")) || initialProfiles[0]
  );
  const [selectedPosFilter, setSelectedPosFilter] = useState<string>('ALL');

  const filteredPlayers = initialProfiles.filter((p) => {
    const matchesSearch =
      p.playerName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      p.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
      p.archetype.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesPos = selectedPosFilter === 'ALL' || p.position === selectedPosFilter;
    return matchesSearch && matchesPos;
  });

  const isObserved = selectedPlayer.dnaSource === 'observed_pbp_box';

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-5 rounded-2xl bg-gradient-to-r from-slate-900 via-indigo-950/40 to-slate-900 border border-slate-800 shadow-xl">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 flex items-center gap-1">
              <Dna className="w-3.5 h-3.5" /> High-Dimensional Player DNA
            </span>
            <span className="text-xs text-slate-500 font-mono">12-D Manifold Embedding</span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            Player DNA & Skill Fingerprints
          </h1>
          <p className="text-sm text-slate-300 max-w-2xl mt-1">
            Multivariate stylistic fingerprinting across 12 empirical PBP, box-score, defensive tracking,
            and ridge RAPM skill percentiles with current-roster cosine similarity matching.
          </p>
        </div>
      </div>

      {/* Main Grid: Left Directory / Right Focus Profile */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Player Roster (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-xl bg-surface-raised/50 border border-slate-800 space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-slate-400" />
              <input
                type="text"
                placeholder="Search player, team, or archetype..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-surface border border-slate-800 rounded-lg text-slate-200 placeholder-slate-500 focus:outline-none focus:border-indigo-500 transition-colors"
              />
            </div>

            {/* Position Filter Buttons */}
            <div className="flex items-center gap-1.5">
              {['ALL', 'G', 'F', 'C'].map((pos) => (
                <button
                  key={pos}
                  onClick={() => setSelectedPosFilter(pos)}
                  className={`px-3 py-1 text-xs rounded-md font-medium transition-colors ${
                    selectedPosFilter === pos
                      ? 'bg-accent-600 text-white'
                      : 'bg-surface text-slate-400 hover:text-slate-200 border border-slate-800'
                  }`}
                >
                  {pos === 'ALL' ? 'All Positions' : pos}
                </button>
              ))}
            </div>
          </div>

          {/* Player Cards List */}
          <div className="space-y-2 max-h-[600px] overflow-y-auto pr-1">
            {filteredPlayers.map((player) => {
              const isSelected = player.playerId === selectedPlayer.playerId;
              return (
                <div
                  key={player.playerId}
                  onClick={() => setSelectedPlayer(player)}
                  className={`p-3 rounded-xl border transition-all cursor-pointer flex items-center justify-between gap-3 ${
                    isSelected
                      ? 'bg-accent-950/30 border-accent-500/50 shadow-md shadow-accent-500/10'
                      : 'bg-surface-raised/40 border-slate-800/80 hover:border-slate-700'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <TeamLogo team={player.team} size="sm" />
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-sm font-bold text-slate-100">{player.playerName}</span>
                        <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-slate-400">
                          {player.position}
                        </span>
                      </div>
                      <div className="text-[11px] text-slate-400 truncate max-w-[180px]">
                        {player.archetype}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 text-right">
                    <div>
                      <div className="text-[10px] text-slate-400">Overall</div>
                      <div className="text-xs font-mono font-bold text-indigo-400">
                        {player.overallRating}
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
          {/* Main Focus Dossier Card */}
          <div className="p-6 rounded-2xl bg-surface-raised/60 border border-slate-800 shadow-xl space-y-6">
            {/* Top Bar: Bio & Ratings */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800 pb-4">
              <div className="flex items-center gap-4">
                <TeamLogo team={selectedPlayer.team} size="lg" />
                <div>
                  <div className="flex items-center gap-2 flex-wrap">
                    <h2 className="text-xl sm:text-2xl font-extrabold text-white">
                      {selectedPlayer.playerName}
                    </h2>
                    <span className="px-2 py-0.5 rounded text-xs font-mono font-bold bg-slate-800 text-indigo-400 border border-slate-700">
                      {selectedPlayer.team} • {selectedPlayer.position}
                    </span>
                    <span
                      className={`px-2 py-0.5 rounded text-[10px] font-mono font-semibold border ${
                        isObserved
                          ? 'bg-emerald-950/60 text-emerald-400 border-emerald-800/60'
                          : 'bg-amber-950/60 text-amber-400 border-amber-800/60'
                      }`}
                    >
                      {isObserved ? 'Observed PBP + Box' : 'Positional Prior Fallback'}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-xs text-slate-400 font-medium">Archetype:</span>
                    <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-indigo-500/10 text-indigo-300 border border-indigo-500/30">
                      {selectedPlayer.archetype}
                    </span>
                  </div>
                </div>
              </div>

              {/* Quick Stat Badges */}
              <div className="flex items-center gap-3">
                <div className="p-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[70px]">
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">PTS</div>
                  <div className="text-base font-bold text-slate-100">{selectedPlayer.projPts}</div>
                </div>
                <div className="p-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[70px]">
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">REB</div>
                  <div className="text-base font-bold text-slate-100">{selectedPlayer.projReb}</div>
                </div>
                <div className="p-3 rounded-xl bg-surface/80 border border-slate-800 text-center min-w-[70px]">
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">AST</div>
                  <div className="text-base font-bold text-slate-100">{selectedPlayer.projAst}</div>
                </div>
                <div className="p-3 rounded-xl bg-indigo-950/40 border border-indigo-800/60 text-center min-w-[75px]">
                  <div className="text-[10px] text-indigo-300 uppercase font-semibold">DNA Rtg</div>
                  <div className="text-base font-extrabold text-indigo-400">
                    {selectedPlayer.overallRating}
                  </div>
                </div>
              </div>
            </div>

            {/* Middle Section: Radar Polygon + 12-D Skill Breakdown */}
            <div className="grid grid-cols-1 md:grid-cols-12 gap-6 items-center">
              <div className="md:col-span-5 flex justify-center">
                <SkillFingerprintPolygon categoryScores={selectedPlayer.categoryScores} />
              </div>

              <div className="md:col-span-7 space-y-3">
                <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
                  <BarChart3 className="w-4 h-4 text-indigo-400" />
                  12-Dimensional Skill Percentiles
                </h4>
                <div className="grid grid-cols-2 gap-2 text-xs">
                  {(Object.entries(selectedPlayer.skillVector) as [keyof SkillVector, number][]).map(
                    ([key, val]) => (
                      <div
                        key={key}
                        className="p-2 rounded-lg bg-surface/50 border border-slate-800/80 flex items-center justify-between"
                      >
                        <span className="text-slate-400">
                          {SKILL_DIMENSION_LABELS[key] || key.replace('_', ' ')}
                        </span>
                        <span className="font-mono font-bold text-indigo-400">{val}</span>
                      </div>
                    )
                  )}
                </div>
              </div>
            </div>

            {/* Nearest Current WNBA Peers (Standardized Cosine Similarity) */}
            {selectedPlayer.similarPlayers && selectedPlayer.similarPlayers.length > 0 && (
              <div className="space-y-3 border-t border-slate-800 pt-4">
                <div className="flex items-center justify-between">
                  <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
                    <Users className="w-4 h-4 text-emerald-400" />
                    Nearest Active WNBA Stylistic Peers (12-D Cosine Similarity)
                  </h4>
                  <span className="text-[11px] text-slate-500 font-mono">2026 Active Roster Pool</span>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
                  {selectedPlayer.similarPlayers.map((peer) => {
                    const matchedProfile = initialProfiles.find((p) => p.playerId === peer.playerId);
                    return (
                      <div
                        key={peer.playerId}
                        onClick={() => matchedProfile && setSelectedPlayer(matchedProfile)}
                        className="p-3 rounded-xl bg-surface/60 border border-slate-800 hover:border-indigo-500/40 transition-colors cursor-pointer flex items-center justify-between"
                      >
                        <div className="flex items-center gap-2.5">
                          <TeamLogo team={peer.team} size="sm" />
                          <div>
                            <div className="text-xs font-bold text-slate-100">{peer.playerName}</div>
                            <div className="text-[10px] text-slate-400 font-mono">
                              {peer.team} • {peer.position}
                            </div>
                          </div>
                        </div>
                        <span className="text-xs font-mono font-bold text-emerald-400">
                          {peer.similarityPct.toFixed(1)}%
                        </span>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>

          {/* Manifold Scatter Plot Section */}
          <DnaManifoldScatter
            players={filteredPlayers}
            selectedPlayer={selectedPlayer}
            onSelectPlayer={(p) => setSelectedPlayer(p)}
          />
        </div>
      </div>
    </div>
  );
};
