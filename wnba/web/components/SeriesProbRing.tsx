'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { GameOutcomeProb } from '@/lib/playoffTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface SeriesProbRingProps {
  teamA: string;
  teamB: string;
  winProbA: number;
  winProbB: number;
  avgGames: number;
  gameDistributions: GameOutcomeProb[];
  fairMlA?: number;
  fairMlB?: number;
  size?: number;
}

export const SeriesProbRing: React.FC<SeriesProbRingProps> = ({
  teamA,
  teamB,
  winProbA,
  winProbB,
  avgGames,
  gameDistributions,
  fairMlA,
  fairMlB,
  size = 240,
}) => {
  const strokeWidth = 18;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;

  const pctA = Math.round(winProbA * 100);
  const pctB = Math.round(winProbB * 100);

  const strokeDashoffsetA = circumference - winProbA * circumference;

  // Find most likely outcome
  const mostLikely = [...gameDistributions].sort((a, b) => b.probPct - a.probPct)[0];

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, `${teamA}-vs-${teamB}-series-prob-ring`);
    }
  };

  return (
    <div ref={containerRef} className="flex flex-col items-center select-none">
      <div className="w-full flex items-center justify-between mb-1">
        <span className="text-[10px] font-bold text-slate-300 uppercase tracking-wider">
          {teamA} vs {teamB} — Series Probabilities
        </span>
        <button
          type="button"
          onClick={handleExportPng}
          title="Export PNG"
          aria-label="Export chart as PNG"
          data-export-exclude
          className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
        >
          <Download className="w-3.5 h-3.5" />
        </button>
      </div>
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
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none text-center px-4">
          <span className="text-[10px] text-slate-400 uppercase tracking-wider font-bold">Series Duration</span>
          <span className="font-mono text-2xl font-black text-white">{avgGames}</span>
          <span className="text-[10px] font-mono text-slate-400">Avg Games</span>
          {mostLikely && (
            <span className="mt-1 text-[9px] font-mono px-2 py-0.5 rounded-full bg-slate-800 text-amber-400 border border-slate-700 font-bold truncate max-w-[180px]">
              Peak: {mostLikely.winner} in {mostLikely.games} ({mostLikely.probPct}%)
            </span>
          )}
        </div>
      </div>

      {/* Win % Comparison Row */}
      <div className="flex items-center justify-between w-full max-w-[300px] mt-4 px-2">
        <div className="flex items-center gap-2">
          <TeamLogo team={teamA} size="sm" />
          <div className="text-left">
            <span className="text-xs font-bold text-white block">{teamA}</span>
            <div className="flex items-center gap-1">
              <span className="text-sm font-black font-mono text-amber-400">{pctA}%</span>
              {fairMlA !== undefined && (
                <span className="text-[10px] font-mono text-slate-400">
                  ({fairMlA > 0 ? `+${fairMlA}` : fairMlA})
                </span>
              )}
            </div>
          </div>
        </div>

        <div className="text-[11px] font-bold text-slate-500 uppercase tracking-wider">
          VS
        </div>

        <div className="flex items-center gap-2 flex-row-reverse text-right">
          <TeamLogo team={teamB} size="sm" />
          <div>
            <span className="text-xs font-bold text-white block">{teamB}</span>
            <div className="flex items-center gap-1 justify-end">
              <span className="text-sm font-black font-mono text-sky-400">{pctB}%</span>
              {fairMlB !== undefined && (
                <span className="text-[10px] font-mono text-slate-400">
                  ({fairMlB > 0 ? `+${fairMlB}` : fairMlB})
                </span>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
