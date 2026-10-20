'use client';

import React, { useState, useMemo } from 'react';
import { TeamProjection } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { ChevronDown, ChevronUp, Layers, Info } from 'lucide-react';

interface PlayoffContendersBoxWhiskerProps {
  teams: TeamProjection[];
}

export const PlayoffContendersBoxWhisker: React.FC<PlayoffContendersBoxWhiskerProps> = ({ teams }) => {
  const [selectedConf, setSelectedConf] = useState<'All' | 'East' | 'West'>('All');
  const [isExpanded, setIsExpanded] = useState(true);

  // Filter teams with >= 40% playoff probability
  const contenders = useMemo(() => {
    return teams
      .filter((t) => t.ensemble_playoff_prob >= 0.40)
      .filter((t) => (selectedConf === 'All' ? true : t.conference === selectedConf))
      .sort((a, b) => b.ensemble_mean_wins - a.ensemble_mean_wins);
  }, [teams, selectedConf]);

  // Overall scale constants
  const minWinsScale = 25;
  const maxWinsScale = 67;
  const scaleSpan = maxWinsScale - minWinsScale;

  const toPct = (val: number) => {
    return Math.max(0, Math.min(100, ((val - minWinsScale) / scaleSpan) * 100));
  };

  const winTicks = [30, 35, 41, 50, 55, 60, 65];

  return (
    <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
      {/* Header bar */}
      <div className="p-4 bg-slate-950/70 border-b border-slate-800 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-indigo-500/10 text-indigo-400 rounded-lg">
            <Layers className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-bold text-white tracking-tight">
                Playoff Contenders Snapshot (Playoff Equity ≥ 40%)
              </h3>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-semibold">
                {contenders.length} Franchises
              </span>
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              1,000-season Monte Carlo win distributions: Whiskers (p10–p90), Box (IQR p25–p75), Marker (p50 / Mean).
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2.5">
          {/* Conference filter pills */}
          <div className="inline-flex rounded-lg bg-slate-900 p-1 border border-slate-800">
            {(['All', 'East', 'West'] as const).map((conf) => (
              <button
                key={conf}
                onClick={() => setSelectedConf(conf)}
                className={`cursor-pointer select-none px-2.5 py-1 text-xs font-semibold rounded-md transition-all ${
                  selectedConf === conf
                    ? 'bg-emerald-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {conf} {conf !== 'All' ? 'Conf' : ''}
              </button>
            ))}
          </div>

          {/* Toggle Expand/Collapse */}
          <button
            onClick={() => setIsExpanded(!isExpanded)}
            className="cursor-pointer select-none p-1.5 rounded-lg bg-slate-800 text-slate-400 hover:text-white transition-colors"
            title={isExpanded ? 'Collapse Snapshot' : 'Expand Snapshot'}
          >
            {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
          </button>
        </div>
      </div>

      {isExpanded && (
        <div className="p-4 sm:p-5 space-y-4">
          {/* Plot Legend & Axis Ruler */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between text-xs text-slate-400 gap-2 border-b border-slate-800/80 pb-3">
            <div className="flex flex-wrap items-center gap-4 text-[11px]">
              <div className="flex items-center gap-1.5">
                <div className="w-3.5 h-1 bg-slate-400 rounded"></div>
                <span>Whiskers (10th - 90th Pct)</span>
              </div>
              <div className="flex items-center gap-1.5">
                <div className="w-4 h-2.5 bg-indigo-500/40 border border-indigo-400 rounded-sm"></div>
                <span>IQR Box (25th - 75th Pct)</span>
              </div>
              <div className="flex items-center gap-1.5">
                <div className="w-1.5 h-2.5 bg-amber-400 rounded-sm"></div>
                <span>Median (p50)</span>
              </div>
            </div>

            <div className="text-[11px] text-slate-400 flex items-center gap-1.5 font-mono">
              <Info className="w-3 h-3 text-indigo-400" />
              <span>Dashed line at 41 wins (.500 mark)</span>
            </div>
          </div>

          {/* Scale Axis Labels */}
          <div className="relative h-6 text-[10px] font-mono text-slate-400 select-none pl-36 sm:pl-48 pr-28 sm:pr-36">
            <div className="relative w-full h-full">
              {winTicks.map((tick) => {
                const pos = toPct(tick);
                const isSpecial = tick === 41 || tick === 50;
                return (
                  <div
                    key={tick}
                    className="absolute -translate-x-1/2 flex flex-col items-center"
                    style={{ left: `${pos}%` }}
                  >
                    <span className={isSpecial ? 'text-amber-400 font-bold' : 'text-slate-400'}>
                      {tick}W
                    </span>
                    <div className={`w-px h-1.5 ${isSpecial ? 'bg-amber-400' : 'bg-slate-700'}`} />
                  </div>
                );
              })}
            </div>
          </div>

          {/* Teams Contenders Box-Whisker Rows */}
          <div className="space-y-2">
            {contenders.map((team) => {
              const p10 = toPct(team.ensemble_p10);
              const p25 = toPct(team.ensemble_p25);
              const p50 = toPct(team.ensemble_p50);
              const p75 = toPct(team.ensemble_p75);
              const p90 = toPct(team.ensemble_p90);

              const boxLeft = Math.min(p25, p75);
              const boxWidth = Math.max(1.5, Math.abs(p75 - p25));
              const whiskerLeft = Math.min(p10, p90);
              const whiskerWidth = Math.max(2, Math.abs(p90 - p10));

              const isPlayoffLock = team.ensemble_playoff_prob >= 0.85;

              return (
                <div
                  key={team.team}
                  className="flex items-center gap-2 sm:gap-4 py-1.5 px-2 rounded-lg hover:bg-slate-800/40 transition-colors group"
                >
                  {/* Team Identity Column */}
                  <div className="w-32 sm:w-44 flex items-center gap-2 flex-shrink-0">
                    <div className="w-7 h-7 rounded-md bg-slate-950 p-0.5 border border-slate-800 flex items-center justify-center flex-shrink-0">
                      <TeamLogo team={team.team} size="xs" />
                    </div>
                    <div className="min-w-0">
                      <div className="font-semibold text-white text-xs truncate group-hover:text-indigo-400 transition-colors">
                        {team.team_name}
                      </div>
                      <div className="text-[10px] font-mono text-slate-400 flex items-center gap-1.5">
                        <span className="text-amber-400 font-bold">{team.team}</span>
                        <span>•</span>
                        <span className={team.conference === 'East' ? 'text-blue-400' : 'text-red-400'}>
                          {team.conference}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Box and Whisker Visual Track */}
                  <div className="relative flex-1 h-6 flex items-center">
                    {/* Background track line */}
                    <div className="absolute inset-x-0 h-1 bg-slate-800/60 rounded-full" />

                    {/* .500 (41 wins) reference guideline */}
                    <div
                      className="absolute inset-y-0 w-px border-r border-dashed border-slate-700/80 z-0"
                      style={{ left: `${toPct(41)}%` }}
                    />
                    {/* 50 wins reference guideline */}
                    <div
                      className="absolute inset-y-0 w-px border-r border-dashed border-amber-500/30 z-0"
                      style={{ left: `${toPct(50)}%` }}
                    />

                    {/* Whisker Line (p10 to p90) */}
                    <div
                      className="absolute h-0.5 bg-slate-400/80 rounded z-10"
                      style={{ left: `${whiskerLeft}%`, width: `${whiskerWidth}%` }}
                    />

                    {/* Whisker End Cap Left (p10) */}
                    <div
                      className="absolute w-0.5 h-3 bg-slate-400 rounded-sm z-10"
                      style={{ left: `${whiskerLeft}%` }}
                      title={`10th percentile: ${team.ensemble_p10.toFixed(1)} wins`}
                    />

                    {/* Whisker End Cap Right (p90) */}
                    <div
                      className="absolute w-0.5 h-3 bg-slate-400 rounded-sm z-10"
                      style={{ left: `${whiskerLeft + whiskerWidth}%` }}
                      title={`90th percentile: ${team.ensemble_p90.toFixed(1)} wins`}
                    />

                    {/* IQR Box (p25 to p75) */}
                    <div
                      className="absolute h-4 bg-indigo-500/30 border border-indigo-400/60 rounded-sm z-20 transition-transform group-hover:scale-y-110 shadow-sm"
                      style={{ left: `${boxLeft}%`, width: `${boxWidth}%` }}
                      title={`IQR (25th - 75th): ${team.ensemble_p25.toFixed(1)} to ${team.ensemble_p75.toFixed(1)} wins`}
                    />

                    {/* Median / Mean Marker (p50) */}
                    <div
                      className="absolute w-1.5 h-5 bg-amber-400 rounded-sm z-30 shadow"
                      style={{ left: `${p50}%`, marginLeft: '-3px' }}
                      title={`Median: ${team.ensemble_p50.toFixed(1)} | Mean: ${team.ensemble_mean_wins.toFixed(1)} wins`}
                    />
                  </div>

                  {/* Stats Badges Column */}
                  <div className="w-24 sm:w-32 flex items-center justify-end gap-2 flex-shrink-0 text-right font-mono">
                    <span className="text-xs font-bold text-white">
                      {team.ensemble_mean_wins.toFixed(1)}W
                    </span>
                    <span
                      className={`text-[10px] px-1.5 py-0.5 rounded font-bold ${
                        isPlayoffLock
                          ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                          : 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                      }`}
                    >
                      {(team.ensemble_playoff_prob * 100).toFixed(0)}%
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
