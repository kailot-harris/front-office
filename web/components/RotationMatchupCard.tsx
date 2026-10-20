'use client';

import React, { useState } from 'react';
import { GameScheduleDetail, TeamPlayoffProfile } from '@/lib/playoffTypes';
import { Sparkles } from 'lucide-react';

interface RotationMatchupCardProps {
  teamA: string;
  teamB: string;
  profileA: TeamPlayoffProfile;
  profileB: TeamPlayoffProfile;
  gameSchedule: GameScheduleDetail[];
}

export const RotationMatchupCard: React.FC<RotationMatchupCardProps> = ({
  teamA,
  teamB,
  profileA,
  profileB,
  gameSchedule,
}) => {
  const [activeTab, setActiveTab] = useState<'schedule' | 'pitching' | 'lineups'>('schedule');

  return (
    <div className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 shadow-xl space-y-4">
      {/* Tab Navigation */}
      <div className="flex items-center justify-between border-b border-slate-800/80 pb-3">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => setActiveTab('schedule')}
            className={`px-3 py-1.5 rounded-lg text-xs font-mono font-bold transition-all ${
              activeTab === 'schedule'
                ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800'
            }`}
          >
            Game-by-Game Starters
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('pitching')}
            className={`px-3 py-1.5 rounded-lg text-xs font-mono font-bold transition-all ${
              activeTab === 'pitching'
                ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800'
            }`}
          >
            Rotation & Bullpen Staffs
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('lineups')}
            className={`px-3 py-1.5 rounded-lg text-xs font-mono font-bold transition-all ${
              activeTab === 'lineups'
                ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30'
                : 'text-slate-400 hover:text-white hover:bg-slate-800'
            }`}
          >
            Lineup Power Cores
          </button>
        </div>
        <span className="text-xs font-mono text-slate-500 hidden sm:inline">
          Tangotiger rGS & Pitcher Elo
        </span>
      </div>

      {/* Tab 1: Game-by-Game Starters */}
      {activeTab === 'schedule' && (
        <div className="space-y-2">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
            {gameSchedule.map((g) => {
              const isHomeA = g.homeTeam === teamA;
              return (
                <div
                  key={g.gameNumber}
                  className="bg-surface/80 border border-slate-800/80 rounded-xl p-3 space-y-2"
                >
                  <div className="flex items-center justify-between text-xs font-mono border-b border-slate-800 pb-1.5">
                    <span className="font-bold text-amber-400 flex items-center gap-1.5">
                      <Sparkles className="w-3 h-3" /> Game {g.gameNumber}
                    </span>
                    <span className="text-[11px] text-slate-400">
                      Site: <strong className={isHomeA ? 'text-sky-400' : 'text-amber-400'}>{g.homeTeam}</strong>
                    </span>
                  </div>

                  <div className="grid grid-cols-2 gap-3 text-xs">
                    {/* Starter A */}
                    <div className="space-y-0.5">
                      <div className="flex items-center justify-between">
                        <span className="font-bold text-sky-400 font-mono">{teamA}</span>
                        <span className="text-[10.5px] font-mono text-slate-400">rGS {g.starterArGS}</span>
                      </div>
                      <p className="font-semibold text-white truncate text-xs">{g.starterA}</p>
                      <div className="text-[10px] text-slate-400 font-mono">
                        Win Prob: <strong className="text-sky-300">{(g.winProbA * 100).toFixed(1)}%</strong>
                      </div>
                    </div>

                    {/* Starter B */}
                    <div className="space-y-0.5 border-l border-slate-800/80 pl-3">
                      <div className="flex items-center justify-between">
                        <span className="font-bold text-amber-400 font-mono">{teamB}</span>
                        <span className="text-[10.5px] font-mono text-slate-400">rGS {g.starterBrGS}</span>
                      </div>
                      <p className="font-semibold text-white truncate text-xs">{g.starterB}</p>
                      <div className="text-[10px] text-slate-400 font-mono">
                        Win Prob: <strong className="text-amber-300">{(g.winProbB * 100).toFixed(1)}%</strong>
                      </div>
                    </div>
                  </div>

                  {/* Horizontal Mini Probability Bar */}
                  <div className="w-full bg-surface-raised h-1.5 rounded-full overflow-hidden flex">
                    <div className="bg-sky-500 h-full" style={{ width: `${g.winProbA * 100}%` }} />
                    <div className="bg-amber-500 h-full" style={{ width: `${g.winProbB * 100}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Tab 2: Pitching Staffs */}
      {activeTab === 'pitching' && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs font-mono">
          {/* Team A Pitching */}
          <div className="bg-surface/70 border border-sky-900/30 rounded-xl p-3.5 space-y-3">
            <div className="flex items-center justify-between text-sky-400 border-b border-slate-800 pb-2">
              <span className="font-bold">{teamA} Pitching Staff</span>
              <span>Top 4 SP + 4 RP</span>
            </div>

            <div className="space-y-2">
              <span className="text-[10.5px] text-slate-400 uppercase font-bold block">Starting Rotation</span>
              {profileA.starters.map((sp, idx) => (
                <div key={idx} className="flex items-center justify-between bg-surface-raised/60 p-1.5 rounded border border-slate-800/50">
                  <div className="truncate">
                    <span className="text-[10px] text-slate-400 mr-2">{sp.role}:</span>
                    <span className="text-white font-semibold">{sp.playerName}</span>
                  </div>
                  <div className="flex items-center gap-2 text-[10.5px]">
                    <span className="text-amber-400 font-bold">rGS {sp.rGS}</span>
                    <span className="text-slate-400">ERA {sp.projEra}</span>
                    <span className="text-slate-400">K% {sp.kPct}%</span>
                  </div>
                </div>
              ))}
            </div>

            <div className="space-y-2 pt-2 border-t border-slate-800/60">
              <span className="text-[10.5px] text-slate-400 uppercase font-bold block">Bullpen Arms</span>
              {profileA.relievers.map((rp, idx) => (
                <div key={idx} className="flex items-center justify-between bg-surface-raised/60 p-1.5 rounded border border-slate-800/50">
                  <div className="truncate">
                    <span className="text-[10px] text-slate-400 mr-2">{rp.role}:</span>
                    <span className="text-white font-semibold">{rp.playerName}</span>
                  </div>
                  <div className="flex items-center gap-2 text-[10.5px]">
                    <span className="text-emerald-400">xFIP {rp.xFip}</span>
                    <span className="text-slate-400">K% {rp.kPct}%</span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Team B Pitching */}
          <div className="bg-surface/70 border border-amber-900/30 rounded-xl p-3.5 space-y-3">
            <div className="flex items-center justify-between text-amber-400 border-b border-slate-800 pb-2">
              <span className="font-bold">{teamB} Pitching Staff</span>
              <span>Top 4 SP + 4 RP</span>
            </div>

            <div className="space-y-2">
              <span className="text-[10.5px] text-slate-400 uppercase font-bold block">Starting Rotation</span>
              {profileB.starters.map((sp, idx) => (
                <div key={idx} className="flex items-center justify-between bg-surface-raised/60 p-1.5 rounded border border-slate-800/50">
                  <div className="truncate">
                    <span className="text-[10px] text-slate-400 mr-2">{sp.role}:</span>
                    <span className="text-white font-semibold">{sp.playerName}</span>
                  </div>
                  <div className="flex items-center gap-2 text-[10.5px]">
                    <span className="text-amber-400 font-bold">rGS {sp.rGS}</span>
                    <span className="text-slate-400">ERA {sp.projEra}</span>
                    <span className="text-slate-400">K% {sp.kPct}%</span>
                  </div>
                </div>
              ))}
            </div>

            <div className="space-y-2 pt-2 border-t border-slate-800/60">
              <span className="text-[10.5px] text-slate-400 uppercase font-bold block">Bullpen Arms</span>
              {profileB.relievers.map((rp, idx) => (
                <div key={idx} className="flex items-center justify-between bg-surface-raised/60 p-1.5 rounded border border-slate-800/50">
                  <div className="truncate">
                    <span className="text-[10px] text-slate-400 mr-2">{rp.role}:</span>
                    <span className="text-white font-semibold">{rp.playerName}</span>
                  </div>
                  <div className="flex items-center gap-2 text-[10.5px]">
                    <span className="text-emerald-400">xFIP {rp.xFip}</span>
                    <span className="text-slate-400">K% {rp.kPct}%</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Tab 3: Lineup Power Cores */}
      {activeTab === 'lineups' && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs font-mono">
          {/* Team A Lineup */}
          <div className="bg-surface/70 border border-sky-900/30 rounded-xl p-3.5 space-y-2">
            <span className="font-bold text-sky-400 block border-b border-slate-800 pb-2">
              {teamA} Projected 9-Man Lineup Core
            </span>
            {profileA.lineupCore.map((b, idx) => (
              <div key={idx} className="flex items-center justify-between bg-surface-raised/60 p-1.5 rounded border border-slate-800/50">
                <span className="text-white font-semibold truncate mr-2">{b.playerName}</span>
                <div className="flex items-center gap-2 text-[10.5px]">
                  <span className="text-amber-400 font-bold">wOBA {b.wOBA.toFixed(3)}</span>
                  <span className="text-slate-300">ISO {b.iso.toFixed(3)}</span>
                  <span className="text-slate-400">{b.hr} HR</span>
                </div>
              </div>
            ))}
          </div>

          {/* Team B Lineup */}
          <div className="bg-surface/70 border border-amber-900/30 rounded-xl p-3.5 space-y-2">
            <span className="font-bold text-amber-400 block border-b border-slate-800 pb-2">
              {teamB} Projected 9-Man Lineup Core
            </span>
            {profileB.lineupCore.map((b, idx) => (
              <div key={idx} className="flex items-center justify-between bg-surface-raised/60 p-1.5 rounded border border-slate-800/50">
                <span className="text-white font-semibold truncate mr-2">{b.playerName}</span>
                <div className="flex items-center gap-2 text-[10.5px]">
                  <span className="text-amber-400 font-bold">wOBA {b.wOBA.toFixed(3)}</span>
                  <span className="text-slate-300">ISO {b.iso.toFixed(3)}</span>
                  <span className="text-slate-400">{b.hr} HR</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
