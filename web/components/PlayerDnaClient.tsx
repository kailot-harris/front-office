'use client';

import React, { useState } from 'react';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import { SkillFingerprintPolygon } from './SkillFingerprintPolygon';
import { HistoricalTwinCard } from './HistoricalTwinCard';
import { DnaManifoldScatter } from './DnaManifoldScatter';
import { Search, Dna, Activity, Crosshair, BarChart3, ChevronRight } from 'lucide-react';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';

interface PlayerDnaClientProps {
  initialProfiles: PlayerDnaProfile[];
}

export const PlayerDnaClient: React.FC<PlayerDnaClientProps> = ({ initialProfiles }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedPlayer, setSelectedPlayer] = useState<PlayerDnaProfile>(
    initialProfiles.find((p) => p.playerName === 'Victor Wembanyama') || initialProfiles[0]
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

  return (
    <div className="space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-5 rounded-2xl bg-gradient-to-r from-zinc-900 via-sky-950/20 to-zinc-900 border border-sky-900/30">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-sky-500/10 text-sky-400 border border-sky-500/20 flex items-center gap-1">
              <Dna className="w-3.5 h-3.5" /> High-Dimensional Player DNA
            </span>
            <span className="text-xs text-zinc-500 font-mono">16-D Manifold Embedding</span>
            <SeasonSourceBadge
              season={SEASON_SOURCES.playerDna.season}
              kind="projection"
              label="Projected season"
              title={SEASON_SOURCES.playerDna.note}
            />
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-100">
            Player DNA & Nearest Historical Comparables
          </h1>
          <p className="text-sm text-zinc-400 max-w-2xl mt-1">
            Multivariate stylistic fingerprinting quantifying finishing, perimeter gravity, playmaking leverage,
            switchability, and rim deterrence with cosine-similarity matching against 1990–2025 all-time peaks.
          </p>
        </div>
      </div>

      {/* Main Grid: Left Directory / Right Focus Profile */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Column: Search & Player Roster (4 cols) */}
        <div className="lg:col-span-4 space-y-4">
          <div className="p-4 rounded-xl bg-zinc-900/50 border border-zinc-800 space-y-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-zinc-400" />
              <input
                type="text"
                placeholder="Search player, team, or archetype..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-zinc-950 border border-zinc-800 rounded-lg text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-sky-500 transition-colors"
              />
            </div>

            {/* Position filter buttons */}
            <div className="flex items-center gap-1.5">
              {['ALL', 'G', 'F', 'C'].map((pos) => (
                <button
                  key={pos}
                  onClick={() => setSelectedPosFilter(pos)}
                  className={`flex-1 py-1 text-xs font-semibold rounded-md transition-colors ${
                    selectedPosFilter === pos
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'bg-zinc-800/80 text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800'
                  }`}
                >
                  {pos === 'ALL' ? 'All Roles' : pos}
                </button>
              ))}
            </div>
          </div>

          {/* Player Scroll List */}
          <div className="rounded-xl border border-zinc-800 bg-zinc-900/30 overflow-hidden divide-y divide-zinc-800/60 max-h-[620px] overflow-y-auto">
            {filteredPlayers.slice(0, 50).map((player) => {
              const isSelected = player.playerId === selectedPlayer.playerId;
              return (
                <button
                  key={player.playerId}
                  onClick={() => setSelectedPlayer(player)}
                  className={`w-full text-left p-3 flex items-center justify-between transition-colors ${
                    isSelected
                      ? 'bg-sky-950/40 border-l-4 border-l-sky-500 text-zinc-100'
                      : 'hover:bg-zinc-800/40 text-zinc-300'
                  }`}
                >
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-sm">{player.playerName}</span>
                      <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400">
                        {player.team} · {player.position}
                      </span>
                    </div>
                    <div className="text-xs text-zinc-400 truncate max-w-[210px] mt-0.5">
                      {player.archetype}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="text-right">
                      <div className="text-xs font-bold text-sky-400">{player.overallRating}</div>
                      <div className="text-[9px] text-zinc-500 uppercase">Rating</div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-zinc-500" />
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Right Column: In-Depth DNA Card (8 cols) */}
        <div className="lg:col-span-8 space-y-5">
          {/* Active Profile Header Card */}
          <div className="p-5 rounded-2xl bg-zinc-900/70 border border-zinc-800/90 relative overflow-hidden">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-xs font-mono px-2 py-0.5 rounded bg-zinc-800 text-sky-400 border border-zinc-700">
                    {selectedPlayer.team} · {selectedPlayer.position}
                  </span>
                  <span className="text-xs font-medium text-zinc-400">
                    {selectedPlayer.projMpg} MPG Proj
                  </span>
                </div>
                <h2 className="text-2xl font-bold text-zinc-100 tracking-tight">
                  {selectedPlayer.playerName}
                </h2>
                <p className="text-sm font-semibold text-sky-400 mt-0.5 flex items-center gap-1.5">
                  <Crosshair className="w-4 h-4" /> {selectedPlayer.archetype}
                </p>
              </div>

              {/* 3 Core Proj Stats */}
              <div className="flex items-center gap-3">
                <div className="px-3.5 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-xs text-zinc-400 font-medium">PTS</div>
                  <div className="text-base font-bold text-zinc-100">{selectedPlayer.projPts}</div>
                </div>
                <div className="px-3.5 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-xs text-zinc-400 font-medium">REB</div>
                  <div className="text-base font-bold text-zinc-100">{selectedPlayer.projReb}</div>
                </div>
                <div className="px-3.5 py-2 rounded-xl bg-zinc-950/80 border border-zinc-800 text-center">
                  <div className="text-xs text-zinc-400 font-medium">AST</div>
                  <div className="text-base font-bold text-zinc-100">{selectedPlayer.projAst}</div>
                </div>
                <div className="px-3.5 py-2 rounded-xl bg-sky-950/60 border border-sky-800/80 text-center">
                  <div className="text-xs text-sky-400 font-medium">INDEX</div>
                  <div className="text-base font-bold text-sky-200">{selectedPlayer.overallRating}</div>
                </div>
              </div>
            </div>
          </div>

          {/* Polygon Radar + Nearest Historical Twins Grid */}
          <div className="grid grid-cols-1 md:grid-cols-12 gap-5">
            {/* Skill Radar (5 cols) */}
            <div className="md:col-span-5">
              <SkillFingerprintPolygon
                categoryScores={selectedPlayer.categoryScores}
              />
            </div>

            {/* Historical Twins List (7 cols) */}
            <div className="md:col-span-7 flex flex-col justify-between space-y-2">
              <div className="flex items-center justify-between mb-1">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-zinc-400 flex items-center gap-1.5">
                  <Activity className="w-3.5 h-3.5 text-sky-400" />
                  Top Historical Stylistic Twins (Cosine Metric)
                </h3>
                <span className="text-[10px] text-zinc-500">1990–2025 Era</span>
              </div>
              <div className="space-y-2">
                {selectedPlayer.historicalTwins.map((twin, idx) => (
                  <HistoricalTwinCard key={twin.compName} twin={twin} rank={idx + 1} />
                ))}
              </div>
            </div>
          </div>

          {/* 16-D Detailed Skill Decomposition Breakdown */}
          <div className="p-4 rounded-xl bg-zinc-950/60 border border-zinc-800/80">
            <h4 className="text-xs font-semibold text-zinc-300 uppercase tracking-wider mb-3 flex items-center gap-1.5">
              <BarChart3 className="w-3.5 h-3.5 text-sky-400" />
              16-Dimensional Skill Vector Breakdown
            </h4>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
              <div className="p-2.5 rounded-lg bg-zinc-900/60 border border-zinc-800">
                <div className="text-zinc-400 font-medium mb-1">Finishing</div>
                <div className="text-[11px] text-zinc-300 space-y-0.5">
                  <div className="flex justify-between"><span>Rim FG%:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.rim_fg}</span></div>
                  <div className="flex justify-between"><span>Dunk Freq:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.dunks}</span></div>
                  <div className="flex justify-between"><span>Paint Touches:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.paint_touches}</span></div>
                </div>
              </div>
              <div className="p-2.5 rounded-lg bg-zinc-900/60 border border-zinc-800">
                <div className="text-zinc-400 font-medium mb-1">Shooting</div>
                <div className="text-[11px] text-zinc-300 space-y-0.5">
                  <div className="flex justify-between"><span>C&S 3PT%:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.cns_3p}</span></div>
                  <div className="flex justify-between"><span>Pull-Up 3PT%:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.pullup_3p}</span></div>
                  <div className="flex justify-between"><span>FT%:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.ft_pct}</span></div>
                </div>
              </div>
              <div className="p-2.5 rounded-lg bg-zinc-900/60 border border-zinc-800">
                <div className="text-zinc-400 font-medium mb-1">Playmaking</div>
                <div className="text-[11px] text-zinc-300 space-y-0.5">
                  <div className="flex justify-between"><span>Assist%:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.ast_pct}</span></div>
                  <div className="flex justify-between"><span>Pot. Assists:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.pot_ast}</span></div>
                  <div className="flex justify-between"><span>Drive Ast%:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.drive_ast}</span></div>
                  <div className="flex justify-between"><span>TOV Control:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.tov_control}</span></div>
                </div>
              </div>
              <div className="p-2.5 rounded-lg bg-zinc-900/60 border border-zinc-800">
                <div className="text-zinc-400 font-medium mb-1">Defense & Glass</div>
                <div className="text-[11px] text-zinc-300 space-y-0.5">
                  <div className="flex justify-between"><span>Switchability:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.switchability}</span></div>
                  <div className="flex justify-between"><span>Rim Protect:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.rim_protection}</span></div>
                  <div className="flex justify-between"><span>Perimeter Havoc:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.perimeter_havoc}</span></div>
                  <div className="flex justify-between"><span>D-RAPM:</span> <span className="font-mono text-sky-400">{selectedPlayer.skillVector.d_rapm}</span></div>
                </div>
              </div>
            </div>
          </div>

          {/* 2D Manifold Scatter */}
          <DnaManifoldScatter
            players={initialProfiles}
            selectedPlayer={selectedPlayer}
            onSelectPlayer={(p) => setSelectedPlayer(p)}
          />
        </div>
      </div>
    </div>
  );
};
