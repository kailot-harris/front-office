'use client';

import React, { useState, useMemo } from 'react';
import { TeamStanding } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { ChevronDown, ChevronUp, Layers, Award } from 'lucide-react';

interface WinDistributionBoxWhiskerProps {
  teams: TeamStanding[];
}

export const WinDistributionBoxWhisker: React.FC<WinDistributionBoxWhiskerProps> = ({ teams }) => {
  const [selectedConf, setSelectedConf] = useState<'All' | 'AFC' | 'NFC'>('All');
  const [isExpanded, setIsExpanded] = useState(true);
  const [filterThreshold, setFilterThreshold] = useState<number>(0.25); // >=25% playoff equity

  // Filter contenders
  const contenders = useMemo(() => {
    return teams
      .filter((t) => t.playoff_prob >= filterThreshold)
      .filter((t) => (selectedConf === 'All' ? true : t.conference === selectedConf))
      .sort((a, b) => b.projected_wins - a.projected_wins);
  }, [teams, selectedConf, filterThreshold]);

  // Scale constants: 0 to 17 wins
  const minWinsScale = 2;
  const maxWinsScale = 16;
  const scaleSpan = maxWinsScale - minWinsScale;

  const toPct = (val: number) => {
    return Math.max(0, Math.min(100, ((val - minWinsScale) / scaleSpan) * 100));
  };

  const winTicks = [4, 6, 8, 10, 12, 14];

  return (
    <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
      {/* Header bar */}
      <div className="p-4 bg-surface/70 border-b border-slate-800 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-emerald-500/10 text-emerald-400 rounded-lg">
            <Layers className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-bold text-white tracking-tight">
                Playoff Contenders Win Distributions (Playoff Equity ≥ {(filterThreshold * 100).toFixed(0)}%)
              </h3>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-semibold">
                {contenders.length} Franchises
              </span>
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              1,000-season Monte Carlo win distributions: Whiskers (p10–p90 range), Box (Core Expected Range), Diamond (Projected Wins).
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2.5">
          {/* Threshold toggle */}
          <div className="inline-flex rounded-lg bg-surface-raised p-1 border border-slate-800 text-xs">
            <button
              onClick={() => setFilterThreshold(0.0)}
              className={`px-2 py-1 rounded-md font-medium transition-all ${
                filterThreshold === 0.0 ? 'bg-slate-800 text-white' : 'text-slate-400 hover:text-white'
              }`}
            >
              All 32
            </button>
            <button
              onClick={() => setFilterThreshold(0.25)}
              className={`px-2 py-1 rounded-md font-medium transition-all ${
                filterThreshold === 0.25 ? 'bg-accent-600 text-white shadow' : 'text-slate-400 hover:text-white'
              }`}
            >
              Contenders (≥25%)
            </button>
          </div>

          {/* Conference filter pills */}
          <div className="inline-flex rounded-lg bg-surface-raised p-1 border border-slate-800">
            {(['All', 'AFC', 'NFC'] as const).map((conf) => (
              <button
                key={conf}
                onClick={() => setSelectedConf(conf)}
                className={`cursor-pointer select-none px-2.5 py-1 text-xs font-semibold rounded-md transition-all ${
                  selectedConf === conf
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {conf}
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
                <div className="w-4 h-2.5 bg-emerald-500/30 border border-emerald-400/80 rounded-xs"></div>
                <span>Expected Range</span>
              </div>
              <div className="flex items-center gap-1.5">
                <div className="w-2.5 h-2.5 bg-white border border-emerald-400 rotate-45"></div>
                <span>Mean Projected Wins</span>
              </div>
              <div className="flex items-center gap-1.5">
                <div className="w-2 h-2 rounded-full bg-cyan-400"></div>
                <span>Playoff Cutoff (~9.5 Wins)</span>
              </div>
            </div>

            <div className="text-[11px] font-mono text-slate-400">
              Season: <span className="text-emerald-400 font-bold">17 Games</span>
            </div>
          </div>

          {/* Team Rows */}
          <div className="space-y-2.5 pt-1">
            {/* Axis Ruler Header */}
            <div className="grid grid-cols-12 items-center gap-2 text-[10px] font-mono text-slate-400 select-none pb-1">
              <div className="col-span-4 sm:col-span-3 font-semibold uppercase tracking-wider">Franchise</div>
              <div className="col-span-8 sm:col-span-9 relative h-4">
                {winTicks.map((tick) => (
                  <div
                    key={tick}
                    className="absolute transform -translate-x-1/2 flex flex-col items-center"
                    style={{ left: `${toPct(tick)}%` }}
                  >
                    <span>{tick}W</span>
                    <div className="w-px h-1.5 bg-slate-700"></div>
                  </div>
                ))}
              </div>
            </div>

            {contenders.map((team) => {
              const p10 = team.wins_p10;
              const p90 = team.wins_p90;
              const mean = team.projected_wins;
              const leftWhiskerPct = toPct(p10);
              const rightWhiskerPct = toPct(p90);
              const whiskerWidthPct = Math.max(1, rightWhiskerPct - leftWhiskerPct);

              const leftBoxPct = toPct(Math.max(p10, mean - 1.2));
              const rightBoxPct = toPct(Math.min(p90, mean + 1.2));
              const boxWidthPct = Math.max(1, rightBoxPct - leftBoxPct);

              const meanPct = toPct(mean);
              const playoffLinePct = toPct(9.5);

              return (
                <div
                  key={team.team}
                  className="grid grid-cols-12 items-center gap-2 p-2 rounded-lg bg-surface/40 hover:bg-slate-800/40 transition-colors border border-slate-800/40"
                >
                  {/* Franchise Identification */}
                  <div className="col-span-4 sm:col-span-3 flex items-center gap-2.5 min-w-0">
                    <TeamLogo team={team.team} size="sm" />
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-1.5">
                        <span className="font-bold text-xs text-slate-100 truncate">{team.team_name}</span>
                        <span className="text-[10px] font-mono text-slate-400 font-semibold hidden md:inline">
                          {team.team}
                        </span>
                      </div>
                      <div className="flex items-center gap-1.5 text-[10px] text-slate-400 font-mono">
                        <span>{team.division}</span>
                        <span>•</span>
                        <span className="text-emerald-400 font-semibold">{mean.toFixed(1)} W</span>
                      </div>
                    </div>
                  </div>

                  {/* Distribution Graphic */}
                  <div className="col-span-8 sm:col-span-9 relative flex items-center h-8">
                    {/* Background Grid Lines */}
                    {winTicks.map((tick) => (
                      <div
                        key={tick}
                        className="absolute top-0 bottom-0 w-px bg-slate-800/40 pointer-events-none"
                        style={{ left: `${toPct(tick)}%` }}
                      />
                    ))}

                    {/* Playoff Line Marker (9.5 Wins) */}
                    <div
                      className="absolute top-0 bottom-0 w-0.5 bg-cyan-500/40 pointer-events-none z-0 border-r border-dashed border-cyan-400/80"
                      style={{ left: `${playoffLinePct}%` }}
                      title="Estimated Playoff Threshold (~9.5 Wins)"
                    />

                    {/* Whisker Line (p10 to p90) */}
                    <div
                      className="absolute h-0.5 bg-slate-500 rounded z-10"
                      style={{
                        left: `${leftWhiskerPct}%`,
                        width: `${whiskerWidthPct}%`,
                      }}
                    >
                      {/* Left Cap */}
                      <div className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-3 bg-slate-400 rounded"></div>
                      {/* Right Cap */}
                      <div className="absolute right-0 top-1/2 -translate-y-1/2 w-0.5 h-3 bg-slate-400 rounded"></div>
                    </div>

                    {/* Box (Interquartile / Core Range) */}
                    <div
                      className="absolute h-5 bg-gradient-to-r from-emerald-600/30 to-teal-600/30 border border-emerald-400/60 rounded-xs shadow-xs z-20 backdrop-blur-xs flex items-center justify-center"
                      style={{
                        left: `${leftBoxPct}%`,
                        width: `${boxWidthPct}%`,
                      }}
                      title={`Range: ${p10.toFixed(1)} to ${p90.toFixed(1)} wins`}
                    />

                    {/* Diamond Marker (Mean Projected Wins) */}
                    <div
                      className="absolute w-3 h-3 bg-white border-2 border-emerald-500 rotate-45 shadow-md shadow-emerald-500/30 z-30 transform -translate-x-1/2"
                      style={{ left: `${meanPct}%` }}
                      title={`Projected Wins: ${mean.toFixed(1)} (p10: ${p10.toFixed(1)}, p90: ${p90.toFixed(1)})`}
                    />

                    {/* Badges Floating on the Right */}
                    <div className="absolute right-0 flex items-center gap-1.5 z-30">
                      <span
                        className={`text-[10px] font-mono px-1.5 py-0.5 rounded font-bold ${
                          team.playoff_prob >= 0.70
                            ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                            : team.playoff_prob >= 0.40
                            ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
                            : 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                        }`}
                        title="Probability of making the playoffs"
                      >
                        {(team.playoff_prob * 100).toFixed(0)}% PO
                      </span>
                      {team.super_bowl_prob >= 0.05 && (
                        <span
                          className="text-[10px] font-mono px-1.5 py-0.5 rounded font-bold bg-amber-500/20 text-amber-300 border border-amber-500/30 flex items-center gap-0.5"
                          title="Super Bowl Win Probability"
                        >
                          <Award className="w-2.5 h-2.5" />
                          {(team.super_bowl_prob * 100).toFixed(1)}%
                        </span>
                      )}
                    </div>
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
