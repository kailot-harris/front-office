'use client';

import React, { useState, useMemo } from 'react';
import { TeamEpaProfile } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { Layers } from 'lucide-react';

interface EpaQuadrantScatterProps {
  teams: TeamEpaProfile[];
  onSelectTeam?: (team: TeamEpaProfile) => void;
  selectedTeam?: string | null;
}

export const EpaQuadrantScatter: React.FC<EpaQuadrantScatterProps> = ({
  teams,
  onSelectTeam,
  selectedTeam,
}) => {
  const [selectedConf, setSelectedConf] = useState<'All' | 'AFC' | 'NFC'>('All');
  const [hoveredTeam, setHoveredTeam] = useState<TeamEpaProfile | null>(null);

  const filteredTeams = useMemo(() => {
    return teams.filter((t) => (selectedConf === 'All' ? true : t.conference === selectedConf));
  }, [teams, selectedConf]);

  // Dynamic axis range calculation with comfortable margins
  const minOffEpa = -0.22;
  const maxOffEpa = 0.22;
  const offSpan = maxOffEpa - minOffEpa;

  // Defensive EPA allowed: lower is better, so inverted (-0.22 top, +0.22 bottom)
  const minDefEpa = -0.22; // elite defense (top)
  const maxDefEpa = 0.22; // poor defense (bottom)
  const defSpan = maxDefEpa - minDefEpa;

  const getXPercent = (offEpa: number) => {
    return Math.max(3, Math.min(97, ((offEpa - minOffEpa) / offSpan) * 100));
  };

  const getYPercent = (defEpa: number) => {
    // Invert: lower defEpa should be near 0% (top of container)
    return Math.max(3, Math.min(97, ((defEpa - minDefEpa) / defSpan) * 100));
  };

  return (
    <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg space-y-4">
      {/* Header bar */}
      <div className="p-4 bg-slate-950/70 border-b border-slate-800 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-emerald-500/10 text-emerald-400 rounded-lg">
            <Layers className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-sm font-bold text-white tracking-tight">
                Offensive vs. Defensive EPA/Play Quadrant
              </h2>
              <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-semibold">
                32 Franchises
              </span>
            </div>
            <p className="text-xs text-slate-400 mt-0.5">
              X-Axis: Offensive EPA/Play (right = elite). Y-Axis: Defensive EPA/Play Allowed (up = elite defense).
            </p>
          </div>
        </div>

        {/* Conference Filter */}
        <div className="inline-flex rounded-lg bg-slate-900 p-1 border border-slate-800">
          {(['All', 'AFC', 'NFC'] as const).map((conf) => (
            <button
              key={conf}
              onClick={() => setSelectedConf(conf)}
              className={`cursor-pointer select-none px-2.5 py-1 text-xs font-semibold rounded-md transition-all ${
                selectedConf === conf
                  ? 'bg-emerald-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              {conf}
            </button>
          ))}
        </div>
      </div>

      {/* Main Scatter Canvas Area */}
      <div className="p-4 sm:p-6">
        <div className="relative w-full h-[460px] sm:h-[520px] bg-slate-950/70 rounded-xl border border-slate-800/80 p-4 overflow-hidden select-none">
          {/* Quadrant Background Tints */}
          {/* Top-Right: Elite Tier (Good Offense, Good Defense) */}
          <div className="absolute top-0 right-0 w-1/2 h-1/2 bg-emerald-500/5 border-b border-l border-slate-800/60 pointer-events-none">
            <span className="absolute top-3 right-3 text-[10px] font-mono uppercase tracking-widest text-emerald-400 font-bold bg-emerald-500/10 px-2 py-0.5 rounded border border-emerald-500/20">
              Contenders (Elite Off & Def)
            </span>
          </div>

          {/* Top-Left: Defensive Grinders (Poor Offense, Good Defense) */}
          <div className="absolute top-0 left-0 w-1/2 h-1/2 bg-cyan-500/5 border-b border-r border-slate-800/60 pointer-events-none">
            <span className="absolute top-3 left-3 text-[10px] font-mono uppercase tracking-widest text-cyan-400 font-bold bg-cyan-500/10 px-2 py-0.5 rounded border border-cyan-500/20">
              Defensive Grinders
            </span>
          </div>

          {/* Bottom-Right: High-Flying Shootouts (Good Offense, Vulnerable Def) */}
          <div className="absolute bottom-0 right-0 w-1/2 h-1/2 bg-amber-500/5 border-t border-l border-slate-800/60 pointer-events-none">
            <span className="absolute bottom-3 right-3 text-[10px] font-mono uppercase tracking-widest text-amber-400 font-bold bg-amber-500/10 px-2 py-0.5 rounded border border-amber-500/20">
              High-Flying Shootouts
            </span>
          </div>

          {/* Bottom-Left: Rebuilding Tiers (Poor Offense & Defense) */}
          <div className="absolute bottom-0 left-0 w-1/2 h-1/2 bg-red-500/5 border-t border-r border-slate-800/60 pointer-events-none">
            <span className="absolute bottom-3 left-3 text-[10px] font-mono uppercase tracking-widest text-red-400 font-bold bg-red-500/10 px-2 py-0.5 rounded border border-red-500/20">
              Rebuilding Tiers
            </span>
          </div>

          {/* Center Zero Lines */}
          <div
            className="absolute top-0 bottom-0 w-px bg-slate-700/80 pointer-events-none z-0"
            style={{ left: `${getXPercent(0)}%` }}
          >
            <span className="absolute bottom-1 left-1.5 text-[9px] font-mono text-slate-500">
              0.00 Offense
            </span>
          </div>
          <div
            className="absolute left-0 right-0 h-px bg-slate-700/80 pointer-events-none z-0"
            style={{ top: `${getYPercent(0)}%` }}
          >
            <span className="absolute top-1.5 left-2 text-[9px] font-mono text-slate-500">
              0.00 Defense
            </span>
          </div>

          {/* Scatter Points (Franchise Logos) */}
          {filteredTeams.map((team) => {
            const leftPct = getXPercent(team.off_epa_per_play);
            const topPct = getYPercent(team.def_epa_per_play);
            const isHovered = hoveredTeam?.team === team.team;
            const isSelected = selectedTeam === team.team;

            return (
              <div
                key={team.team}
                onClick={() => onSelectTeam && onSelectTeam(team)}
                onMouseEnter={() => setHoveredTeam(team)}
                onMouseLeave={() => setHoveredTeam(null)}
                style={{
                  left: `${leftPct}%`,
                  top: `${topPct}%`,
                }}
                className={`absolute transform -translate-x-1/2 -translate-y-1/2 cursor-pointer z-10 transition-transform duration-150 ${
                  isHovered || isSelected ? 'scale-135 z-30' : 'hover:scale-120'
                }`}
              >
                <div
                  className={`p-1 rounded-full transition-all shadow-md ${
                    isSelected
                      ? 'bg-emerald-500 ring-2 ring-white ring-offset-2 ring-offset-slate-900 shadow-emerald-500/40'
                      : isHovered
                      ? 'bg-slate-800 ring-2 ring-emerald-400 shadow-lg'
                      : 'bg-slate-900/90 border border-slate-700/70 hover:border-emerald-400'
                  }`}
                >
                  <TeamLogo team={team.team} size="sm" />
                </div>
              </div>
            );
          })}

          {/* Hover Tooltip Card */}
          {hoveredTeam && (
            <div
              className="absolute z-40 bg-slate-900/95 border border-emerald-500/50 rounded-xl p-3 shadow-2xl backdrop-blur-md pointer-events-none text-xs space-y-1.5 min-w-[200px]"
              style={{
                left: `${Math.min(75, Math.max(5, getXPercent(hoveredTeam.off_epa_per_play)))}%`,
                top: `${Math.min(75, Math.max(5, getYPercent(hoveredTeam.def_epa_per_play)))}%`,
                transform: 'translate(-50%, -120%)',
              }}
            >
              <div className="flex items-center gap-2 border-b border-slate-800 pb-1.5">
                <TeamLogo team={hoveredTeam.team} size="xs" />
                <span className="font-bold text-white text-xs">{hoveredTeam.team_name}</span>
                <span className="text-[10px] font-mono text-slate-400 ml-auto">{hoveredTeam.division}</span>
              </div>
              <div className="grid grid-cols-2 gap-2 font-mono text-[11px] pt-0.5">
                <div>
                  <span className="text-[10px] text-slate-500 block">Offense EPA</span>
                  <strong className={hoveredTeam.off_epa_per_play > 0 ? 'text-emerald-400' : 'text-red-400'}>
                    {hoveredTeam.off_epa_per_play > 0 ? `+${hoveredTeam.off_epa_per_play.toFixed(3)}` : hoveredTeam.off_epa_per_play.toFixed(3)}
                  </strong>
                </div>
                <div>
                  <span className="text-[10px] text-slate-500 block">Defense EPA</span>
                  <strong className={hoveredTeam.def_epa_per_play < 0 ? 'text-emerald-400' : 'text-red-400'}>
                    {hoveredTeam.def_epa_per_play > 0 ? `+${hoveredTeam.def_epa_per_play.toFixed(3)}` : hoveredTeam.def_epa_per_play.toFixed(3)}
                  </strong>
                </div>
                <div>
                  <span className="text-[10px] text-slate-500 block">Net EPA/Play</span>
                  <strong className={hoveredTeam.net_epa_per_play > 0 ? 'text-emerald-400' : 'text-red-400'}>
                    {hoveredTeam.net_epa_per_play > 0 ? `+${hoveredTeam.net_epa_per_play.toFixed(3)}` : hoveredTeam.net_epa_per_play.toFixed(3)}
                  </strong>
                </div>
                <div>
                  <span className="text-[10px] text-slate-500 block">Success Rate</span>
                  <strong className="text-white">{hoveredTeam.off_success_rate.toFixed(1)}%</strong>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
