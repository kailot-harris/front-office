'use client';

import React, { useState, useMemo } from 'react';
import { TeamProjection } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { ChevronDown, ChevronUp, Layers, Info } from 'lucide-react';

interface PlayoffContendersBoxWhiskerProps {
  teams: TeamProjection[];
}

export const PlayoffContendersBoxWhisker: React.FC<PlayoffContendersBoxWhiskerProps> = ({ teams }) => {
  const [selectedLeague, setSelectedLeague] = useState<'All' | 'AL' | 'NL'>('All');
  const [isExpanded, setIsExpanded] = useState(true);

  // Filter teams with >= 25% playoff probability (captures all MLB wild card contenders)
  const contenders = useMemo(() => {
    return teams
      .filter((t) => t.ensemble_playoff_prob >= 0.25)
      .filter((t) => (selectedLeague === 'All' ? true : t.league === selectedLeague))
      .sort((a, b) => b.ensemble_mean_wins - a.ensemble_mean_wins);
  }, [teams, selectedLeague]);

  // 162-game MLB win scale constants
  const minWinsScale = 60;
  const maxWinsScale = 112;
  const scaleSpan = maxWinsScale - minWinsScale;

  const toPct = (val: number) => {
    return Math.max(0, Math.min(100, ((val - minWinsScale) / scaleSpan) * 100));
  };

  const winTicks = [65, 73, 81, 88, 95, 102, 108];

  return (
    <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
      {/* Header bar */}
      <div className="p-4 bg-surface/70 border-b border-slate-800 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-indigo-500/10 text-indigo-400 rounded-lg">
            <Layers className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-bold text-white tracking-tight">
                Postseason Contenders Snapshot (Playoff Equity ≥ 25%)
              </h3>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-semibold">
                {contenders.length} Clubs
              </span>
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              1,000-season 162-game Monte Carlo win distributions: Whiskers (p10–p90), Box (IQR p25–p75), Marker (p50 / Median).
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2.5">
          {/* League filter pills */}
          <div className="inline-flex rounded-lg bg-surface-raised p-1 border border-slate-800">
            {(['All', 'AL', 'NL'] as const).map((lg) => (
              <button
                key={lg}
                onClick={() => setSelectedLeague(lg)}
                className={`px-2.5 py-1 text-xs font-semibold rounded-md transition-all ${
                  selectedLeague === lg
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {lg === 'All' ? 'All MLB' : `${lg} League`}
              </button>
            ))}
          </div>

          {/* Toggle Expand/Collapse */}
          <button
            onClick={() => setIsExpanded(!isExpanded)}
            className="p-1.5 rounded-lg bg-slate-800 text-slate-400 hover:text-white transition-colors"
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
              <span>Dashed lines at 81 wins (.500) & 88 wins (Wild Card pace)</span>
            </div>
          </div>

          {/* Scale Axis Labels */}
          <div className="relative h-6 text-[10px] font-mono text-slate-400 select-none pl-36 sm:pl-48 pr-28 sm:pr-36">
            <div className="relative w-full h-full">
              {winTicks.map((tick) => {
                const pos = toPct(tick);
                const isSpecial = tick === 81 || tick === 95;
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
                  className="group flex items-center gap-2 sm:gap-3 py-1.5 px-2 rounded-lg hover:bg-slate-800/50 transition-colors"
                >
                  {/* Left Team Identity */}
                  <div className="w-32 sm:w-44 flex items-center gap-2.5 flex-shrink-0 min-w-0">
                    <span className="text-[11px] font-mono text-slate-400 w-4 text-right">
                      {team.rank}
                    </span>
                    <TeamLogo team={team.team} size="sm" />
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-1.5">
                        <span className="text-xs font-bold text-white truncate">
                          {team.team_name}
                        </span>
                        <span
                          className={`text-[9px] px-1 rounded font-mono ${
                            team.league === 'AL'
                              ? 'bg-sky-500/10 text-sky-400'
                              : 'bg-amber-500/10 text-amber-400'
                          }`}
                        >
                          {team.league}
                        </span>
                      </div>
                      <span className="text-[10px] font-mono text-slate-400 block">
                        {team.ensemble_mean_wins.toFixed(1)}W – {team.proj_losses.toFixed(1)}L
                      </span>
                    </div>
                  </div>

                  {/* Center Box-Whisker Track */}
                  <div className="flex-1 relative h-6 bg-surface/80 rounded border border-slate-800/70 overflow-hidden">
                    {/* Vertical Reference Line at 81 Wins (.500) */}
                    <div
                      className="absolute top-0 bottom-0 w-px border-l border-dashed border-amber-500/40 z-0"
                      style={{ left: `${toPct(81)}%` }}
                    />
                    {/* Vertical Reference Line at 88 Wins (WC Pace) */}
                    <div
                      className="absolute top-0 bottom-0 w-px border-l border-dashed border-indigo-500/30 z-0"
                      style={{ left: `${toPct(88)}%` }}
                    />

                    {/* Whisker Line (p10 to p90) */}
                    <div
                      className="absolute top-1/2 -translate-y-1/2 h-0.5 bg-slate-400/80 z-10"
                      style={{ left: `${whiskerLeft}%`, width: `${whiskerWidth}%` }}
                    />
                    {/* Whisker Left Cap (p10) */}
                    <div
                      className="absolute top-1/2 -translate-y-1/2 w-0.5 h-2.5 bg-slate-300 z-10"
                      style={{ left: `${p10}%` }}
                    />
                    {/* Whisker Right Cap (p90) */}
                    <div
                      className="absolute top-1/2 -translate-y-1/2 w-0.5 h-2.5 bg-slate-300 z-10"
                      style={{ left: `${p90}%` }}
                    />

                    {/* IQR Box (p25 to p75) */}
                    <div
                      className={`absolute top-1 bottom-1 rounded-sm border z-20 transition-all ${
                        isPlayoffLock
                          ? 'bg-indigo-500/40 border-indigo-400'
                          : 'bg-sky-500/30 border-sky-400/80'
                      }`}
                      style={{ left: `${boxLeft}%`, width: `${boxWidth}%` }}
                    />

                    {/* Median Marker (p50) */}
                    <div
                      className="absolute top-0.5 bottom-0.5 w-1 bg-amber-400 rounded-sm shadow z-30 -translate-x-1/2"
                      style={{ left: `${p50}%` }}
                      title={`Median: ${team.ensemble_p50}W`}
                    />
                  </div>

                  {/* Right Stats Summary (p10-p90 & Playoff/WS Prob) */}
                  <div className="w-28 sm:w-36 flex items-center justify-end gap-2 text-right font-mono flex-shrink-0">
                    <div className="hidden sm:block text-[10px] text-slate-400">
                      {team.ensemble_p10.toFixed(0)}–{team.ensemble_p90.toFixed(0)}W
                    </div>
                    <span
                      className={`text-[11px] font-bold px-1.5 py-0.5 rounded ${
                        team.ensemble_playoff_prob >= 0.85
                          ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                          : 'bg-indigo-500/15 text-indigo-300 border border-indigo-500/30'
                      }`}
                      title={`World Series Equity: ${(team.ensemble_title_prob * 100).toFixed(1)}%`}
                    >
                      {(team.ensemble_playoff_prob * 100).toFixed(0)}% PO
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
