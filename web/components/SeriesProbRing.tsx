'use client';

import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { GameOutcomeProb } from '@/lib/playoffTypes';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';

interface SeriesProbRingProps {
  teamA: string;
  teamB: string;
  winProbA: number;
  winProbB: number;
  fairMlA: number;
  fairMlB: number;
  sweepProb: number;
  avgGames: number;
  gameDistributions: GameOutcomeProb[];
  seriesLength: number;
}

export const SeriesProbRing: React.FC<SeriesProbRingProps> = ({
  teamA,
  teamB,
  winProbA,
  winProbB,
  fairMlA,
  fairMlB,
  sweepProb,
  avgGames,
  gameDistributions,
  seriesLength,
}) => {
  const pctA = Math.round(winProbA * 100);
  const pctB = Math.round(winProbB * 100);

  // SVG circular gauge parameters
  const size = 180;
  const strokeWidth = 14;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffsetA = circumference - (winProbA * circumference);

  const formatMl = (ml: number) => (ml > 0 ? `+${ml}` : `${ml}`);

  const sortedDists = [...gameDistributions].sort((a, b) => {
    if (a.winner === b.winner) return a.games - b.games;
    return a.winner === teamA ? -1 : 1;
  });

  const containerRef = useRef<HTMLDivElement | null>(null);

  const handleExportPng = () => {
    if (containerRef.current) {
      exportSvgAsPng(containerRef.current, `series-prob-ring-${teamA}-vs-${teamB}`);
    }
  };

  return (
    <div ref={containerRef} className="bg-surface-raised/90 border border-slate-800 rounded-2xl p-5 shadow-xl flex flex-col justify-between">
      <div className="flex items-center justify-between border-b border-slate-800/80 pb-3 mb-4">
        <div>
          <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
            Series Win Probability Ring
          </h3>
          <p className="text-xs text-slate-400">10,000 Monte Carlo Series Iterations</p>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-[11px] font-mono font-semibold px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
            Best-of-{seriesLength}
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
      </div>

      {/* Donut Ring Visualizer */}
      <div className="flex flex-col sm:flex-row items-center justify-around gap-6 my-2">
        <div className="relative flex items-center justify-center">
          <svg width={size} height={size} className="transform -rotate-90">
            {/* Background circle (Team B) */}
            <circle
              cx={size / 2}
              cy={size / 2}
              r={radius}
              stroke="currentColor"
              strokeWidth={strokeWidth}
              className="text-amber-500/80"
              fill="transparent"
            />
            {/* Foreground circle (Team A) */}
            <circle
              cx={size / 2}
              cy={size / 2}
              r={radius}
              stroke="currentColor"
              strokeWidth={strokeWidth}
              strokeDasharray={circumference}
              strokeDashoffset={strokeDashoffsetA}
              strokeLinecap="round"
              className="text-sky-500 transition-all duration-1000 ease-out"
              fill="transparent"
            />
          </svg>
          <div className="absolute flex flex-col items-center justify-center text-center">
            <span className="text-xs font-mono text-slate-400 uppercase tracking-wide">Favorite</span>
            <span className="text-2xl font-black text-white font-mono">
              {winProbA >= 0.5 ? `${pctA}%` : `${pctB}%`}
            </span>
            <span className="text-[11px] font-bold text-sky-400 font-mono">
              {winProbA >= 0.5 ? teamA : teamB}
            </span>
          </div>
        </div>

        {/* Head-to-Head Odds Cards */}
        <div className="space-y-3 w-full sm:w-44">
          <div className="bg-surface/80 border border-sky-500/30 rounded-xl p-2.5 flex items-center justify-between">
            <div>
              <span className="text-xs font-bold text-sky-400 block font-mono">{teamA}</span>
              <span className="text-[11px] text-slate-400">Fair Line</span>
            </div>
            <div className="text-right">
              <span className="text-base font-black text-white font-mono">{pctA}%</span>
              <span className="text-[11px] font-mono text-sky-300 block">{formatMl(fairMlA)}</span>
            </div>
          </div>

          <div className="bg-surface/80 border border-amber-500/30 rounded-xl p-2.5 flex items-center justify-between">
            <div>
              <span className="text-xs font-bold text-amber-400 block font-mono">{teamB}</span>
              <span className="text-[11px] text-slate-400">Fair Line</span>
            </div>
            <div className="text-right">
              <span className="text-base font-black text-white font-mono">{pctB}%</span>
              <span className="text-[11px] font-mono text-amber-300 block">{formatMl(fairMlB)}</span>
            </div>
          </div>

          <div className="flex items-center justify-between text-[11px] px-1 text-slate-400 font-mono">
            <span>Avg Games: <strong className="text-white">{avgGames}</strong></span>
            <span>Sweep: <strong className="text-white">{sweepProb}%</strong></span>
          </div>
        </div>
      </div>

      {/* Outcome Distribution Bars */}
      <div className="mt-4 pt-3 border-t border-slate-800/80 space-y-1.5">
        <span className="text-[10.5px] uppercase font-mono font-bold text-slate-400 tracking-wider block mb-1">
          Exact Series Outcome Probabilities
        </span>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          {sortedDists.map((d, i) => {
            const isA = d.winner === teamA;
            return (
              <div
                key={i}
                className={`p-2 rounded-lg border text-xs font-mono flex flex-col justify-between ${
                  isA
                    ? 'bg-sky-950/30 border-sky-900/40 text-sky-300'
                    : 'bg-amber-950/30 border-amber-900/40 text-amber-300'
                }`}
              >
                <div className="flex justify-between items-center text-[11px]">
                  <span className="font-bold">{d.winner} in {d.games}</span>
                  <span className="text-white font-black">{d.probPct}%</span>
                </div>
                <div className="w-full bg-surface-raised h-1.5 rounded-full mt-1.5 overflow-hidden">
                  <div
                    className={`h-full rounded-full ${isA ? 'bg-sky-500' : 'bg-amber-500'}`}
                    style={{ width: `${Math.min(100, d.probPct * 2.5)}%` }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
