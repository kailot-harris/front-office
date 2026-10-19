'use client';

import React from 'react';
import { GameOutcomeProb } from '@/lib/playoffTypes';
import { TeamLogo } from '@/components/TeamLogo';

interface SeriesProbRingProps {
  teamA: string;
  teamB: string;
  winProbA: number;
  winProbB: number;
  avgGames: number;
  gameDistributions: GameOutcomeProb[];
  size?: number;
}

export const SeriesProbRing: React.FC<SeriesProbRingProps> = ({
  teamA,
  teamB,
  winProbA,
  winProbB,
  avgGames,
  gameDistributions,
  size = 240,
}) => {
  const strokeWidth = 18;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  
  // Percentages
  const pctA = Math.round(winProbA * 100);
  const pctB = Math.round(winProbB * 100);
  
  const strokeDashoffsetA = circumference - (winProbA * circumference);

  // Group distributions by team
  const distA = gameDistributions.filter((d) => d.winner === teamA);
  const distB = gameDistributions.filter((d) => d.winner === teamB);

  // Find most likely outcome
  const mostLikely = [...gameDistributions].sort((a, b) => b.probPct - a.probPct)[0];

  return (
    <div className="flex flex-col items-center select-none">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="transform -rotate-90">
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="transparent"
            stroke="#1e293b"
            strokeWidth={strokeWidth}
          />
          {/* Team B arc */}
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="transparent"
            stroke="#0ea5e9"
            strokeWidth={strokeWidth}
            strokeDasharray={circumference}
            strokeDashoffset="0"
            className="transition-all duration-700 ease-out"
          />
          {/* Team A arc */}
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="transparent"
            stroke="#f59e0b"
            strokeWidth={strokeWidth}
            strokeDasharray={circumference}
            strokeDashoffset={strokeDashoffsetA}
            strokeLinecap="round"
            className="transition-all duration-700 ease-out"
          />
        </svg>

        {/* Center Badge */}
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-bold">Series Length</span>
          <span className="font-mono text-2xl font-black text-white">{avgGames}</span>
          <span className="text-[10px] font-mono text-slate-400">Avg Games</span>
          {mostLikely && (
            <span className="mt-1 text-[9px] font-mono px-2 py-0.5 rounded-full bg-slate-800 text-amber-400 border border-slate-700 font-bold">
              Peak: {mostLikely.winner} in {mostLikely.games} ({mostLikely.probPct}%)
            </span>
          )}
        </div>
      </div>

      {/* Win % Comparison Row */}
      <div className="flex items-center justify-between w-full max-w-[280px] mt-4 px-2">
        <div className="flex items-center gap-2">
          <TeamLogo team={teamA} size="sm" />
          <div className="text-left">
            <span className="text-xs font-bold text-white block">{teamA}</span>
            <span className="text-sm font-mono font-black text-amber-400">{pctA}%</span>
          </div>
        </div>

        <span className="text-xs font-mono font-bold text-slate-600">VS</span>

        <div className="flex items-center gap-2 flex-row-reverse text-right">
          <TeamLogo team={teamB} size="sm" />
          <div>
            <span className="text-xs font-bold text-white block">{teamB}</span>
            <span className="text-sm font-mono font-black text-sky-400">{pctB}%</span>
          </div>
        </div>
      </div>

      {/* Game-by-Game Probabilities Breakdown */}
      <div className="w-full mt-4 space-y-2 pt-3 border-t border-slate-800/80">
        <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400 block text-center">
          Exact Outcome Distribution (10,000 Sims)
        </span>
        <div className="grid grid-cols-2 gap-2 text-xs font-mono">
          {/* Team A */}
          <div className="space-y-1 p-2 rounded-lg bg-slate-950/60 border border-slate-800/80">
            <span className="text-[10px] text-amber-400 font-bold block mb-1">{teamA} Wins</span>
            {distA.map((d) => (
              <div key={`a-${d.games}`} className="flex items-center justify-between text-[11px]">
                <span className="text-slate-400">in {d.games} G:</span>
                <span className="font-bold text-slate-200">{d.probPct}%</span>
              </div>
            ))}
          </div>

          {/* Team B */}
          <div className="space-y-1 p-2 rounded-lg bg-slate-950/60 border border-slate-800/80">
            <span className="text-[10px] text-sky-400 font-bold block mb-1">{teamB} Wins</span>
            {distB.map((d) => (
              <div key={`b-${d.games}`} className="flex items-center justify-between text-[11px]">
                <span className="text-slate-400">in {d.games} G:</span>
                <span className="font-bold text-slate-200">{d.probPct}%</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
