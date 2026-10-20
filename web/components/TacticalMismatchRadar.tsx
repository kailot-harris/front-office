'use client';

import React from 'react';
import { TacticalRatings, TacticalEdge } from '@/lib/playoffTypes';
import { Zap, Shield, Target, Flame, Layers } from 'lucide-react';

interface TacticalMismatchRadarProps {
  teamA: string;
  teamB: string;
  ratingsA: TacticalRatings;
  ratingsB: TacticalRatings;
  tacticalEdges: TacticalEdge[];
}

export const TacticalMismatchRadar: React.FC<TacticalMismatchRadarProps> = ({
  teamA,
  teamB,
  ratingsA,
  ratingsB,
  tacticalEdges,
}) => {
  const dimensions = [
    { key: 'perimeterCreation', label: 'Perimeter Creation', desc: 'Pull-up 3PT & primary initiator shot-making', icon: Target },
    { key: 'dropVulnerability', label: 'Drop Vulnerability', desc: 'Susceptibility to PnR pull-ups (lower is better)', icon: Shield },
    { key: 'interiorDominance', label: 'Interior Dominance', desc: 'Rim pressure, glass crashes & paint deterrence', icon: Flame },
    { key: 'switchability', label: '1-to-5 Switchability', desc: 'Point-of-attack switch equity & screen neutralization', icon: Layers },
    { key: 'clutchExecution', label: 'Clutch Half-Court PPP', desc: 'Late-clock execution in high-leverage possessions', icon: Zap },
  ];

  return (
    <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-5 shadow-lg space-y-5">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 gap-2">
        <div>
          <h3 className="text-sm font-bold text-white tracking-tight flex items-center gap-2">
            <span>Tactical Profile Comparison</span>
            <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-slate-800 text-slate-300">
              0-100 Ratings
            </span>
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">
            Comparative head-to-head tactical metrics influencing playoff margin adjustments.
          </p>
        </div>

        <div className="flex items-center gap-3 text-xs font-mono">
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-amber-500"></span>
            <span className="text-white font-bold">{teamA}</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-sky-500"></span>
            <span className="text-white font-bold">{teamB}</span>
          </div>
        </div>
      </div>

      {/* Comparative Bars */}
      <div className="space-y-4">
        {dimensions.map((dim) => {
          const valA = ratingsA[dim.key as keyof TacticalRatings] || 50;
          const valB = ratingsB[dim.key as keyof TacticalRatings] || 50;
          const Icon = dim.icon;

          return (
            <div key={dim.key} className="space-y-1.5">
              <div className="flex items-center justify-between text-xs">
                <div className="flex items-center gap-1.5">
                  <Icon className="w-3.5 h-3.5 text-slate-400" />
                  <span className="font-semibold text-slate-200">{dim.label}</span>
                </div>
                <div className="flex items-center gap-3 font-mono font-bold text-xs">
                  <span className="text-amber-400">{valA}</span>
                  <span className="text-slate-600">vs</span>
                  <span className="text-sky-400">{valB}</span>
                </div>
              </div>

              {/* Dual Progress Bar */}
              <div className="grid grid-cols-2 gap-1.5 h-2 bg-surface/80 rounded-full p-0.5 border border-slate-800/80">
                {/* Team A bar (Right aligned) */}
                <div className="h-full flex justify-end">
                  <div
                    className="h-full bg-amber-500 rounded-full transition-all duration-500"
                    style={{ width: `${Math.min(100, valA)}%` }}
                  />
                </div>
                {/* Team B bar (Left aligned) */}
                <div className="h-full flex justify-start">
                  <div
                    className="h-full bg-sky-500 rounded-full transition-all duration-500"
                    style={{ width: `${Math.min(100, valB)}%` }}
                  />
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Detected Tactical Mismatch Edges */}
      {tacticalEdges && tacticalEdges.length > 0 && (
        <div className="pt-3 border-t border-slate-800/80 space-y-2">
          <span className="text-[11px] font-bold text-slate-400 uppercase tracking-wider block">
            Detected Matchup Edges ({tacticalEdges.length})
          </span>
          <div className="grid grid-cols-1 gap-2">
            {tacticalEdges.map((edge, idx) => {
              const isA = edge.advantageTeam === teamA;
              return (
                <div
                  key={idx}
                  className={`p-3 rounded-lg border text-xs flex items-start justify-between gap-3 ${
                    isA
                      ? 'bg-amber-950/20 border-amber-800/40 text-amber-200'
                      : 'bg-sky-950/20 border-sky-800/40 text-sky-200'
                  }`}
                >
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <span
                        className={`text-[10px] font-mono px-1.5 py-0.5 rounded font-black ${
                          isA ? 'bg-amber-500 text-slate-950' : 'bg-sky-500 text-slate-950'
                        }`}
                      >
                        +{edge.deltaMargin.toFixed(1)} PTS/100
                      </span>
                      <span className="font-bold">{edge.title}</span>
                    </div>
                    <p className="text-[11px] text-slate-400 leading-relaxed">
                      {edge.description}
                    </p>
                  </div>
                  <span className="font-mono font-bold text-[11px] px-2 py-0.5 rounded bg-surface-raised border border-slate-800 text-slate-300">
                    Adv: {edge.advantageTeam}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
