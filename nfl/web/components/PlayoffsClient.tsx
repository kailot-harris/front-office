'use client';

import React from 'react';
import { PlayoffDataset } from '@/lib/types';
import { PlayoffBracketSimulator } from '@/components/PlayoffBracketSimulator';
import { TeamLogo } from '@/components/TeamLogo';
import {
  Award,
  Trophy,
  Shield,
  HelpCircle,
} from 'lucide-react';

interface PlayoffsClientProps {
  dataset: PlayoffDataset;
}

export const PlayoffsClient: React.FC<PlayoffsClientProps> = ({ dataset }) => {
  const afc1 = dataset.afc_seeds[0];
  const nfc1 = dataset.nfc_seeds[0];

  // Top Super Bowl Favorite across all seeds
  const allSeeds = [...dataset.afc_seeds, ...dataset.nfc_seeds];
  const topSbFav = [...allSeeds].sort((a, b) => b.super_bowl_win_prob - a.super_bowl_win_prob)[0];

  return (
    <div className="space-y-6">
      {/* Top Postseason Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        {/* AFC #1 Seed */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={afc1?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-red-500/20 text-red-400 rounded-md border border-red-500/30 shadow">
              <Award className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono flex items-center gap-1">
              <span>AFC #1 Seed (1st-Round Bye)</span>
            </div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{afc1?.team_name}</span>
              <span className="text-xs font-semibold text-emerald-400 flex-shrink-0 font-mono">
                {afc1?.role === 'division_winner' ? 'Div Champ' : 'Wild Card'}
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">
              Div: {afc1?.division} • Pwr: +{afc1?.power_rating.toFixed(1)}
            </div>
          </div>
        </div>

        {/* NFC #1 Seed */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={nfc1?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-blue-500/20 text-blue-400 rounded-md border border-blue-500/30 shadow">
              <Award className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono flex items-center gap-1">
              <span>NFC #1 Seed (1st-Round Bye)</span>
            </div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{nfc1?.team_name}</span>
              <span className="text-xs font-semibold text-emerald-400 flex-shrink-0 font-mono">
                {nfc1?.role === 'division_winner' ? 'Div Champ' : 'Wild Card'}
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">
              Div: {nfc1?.division} • Pwr: +{nfc1?.power_rating.toFixed(1)}
            </div>
          </div>
        </div>

        {/* Super Bowl Equity Leader */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topSbFav?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-amber-500/20 text-amber-400 rounded-md border border-amber-500/30 shadow">
              <Trophy className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">Super Bowl Equity Leader</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topSbFav?.team_name}</span>
              <span className="text-xs font-semibold text-amber-400 flex-shrink-0 font-mono">
                {(topSbFav?.super_bowl_win_prob * 100).toFixed(1)}% SB
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">
              Conf: {(topSbFav?.conf_champ_win_prob * 100).toFixed(0)}% • Div: {(topSbFav?.divisional_win_prob * 100).toFixed(0)}%
            </div>
          </div>
        </div>
      </div>

      {/* Playoff Bracket Simulator Component */}
      <PlayoffBracketSimulator dataset={dataset} />

      {/* Bubble Contenders Grid ("In the Hunt") */}
      <div className="space-y-3">
        <div className="flex items-center justify-between border-b border-slate-800 pb-2">
          <div className="flex items-center gap-2">
            <Shield className="w-4 h-4 text-emerald-400" />
            <h2 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
              In The Hunt • Playoff Bubble Franchises
            </h2>
          </div>
          <span className="text-xs font-mono text-slate-400">Next 4 Teams Out Per Conference</span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* AFC Bubble */}
          <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 space-y-3">
            <div className="flex items-center justify-between border-b border-slate-800/80 pb-2">
              <span className="text-xs font-mono uppercase text-red-400 font-bold flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-red-500" />
                AFC Bubble Contenders
              </span>
              <span className="text-[10px] font-mono text-slate-500">Playoff Equity</span>
            </div>
            <div className="space-y-2">
              {dataset.afc_bubble.map((team, idx) => (
                <div
                  key={team.team}
                  className="flex items-center justify-between p-2 rounded-lg bg-slate-950/40 hover:bg-slate-800/40 transition-colors"
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    <span className="text-xs font-mono font-bold text-slate-500 w-4">
                      #{idx + 8}
                    </span>
                    <TeamLogo team={team.team} size="sm" />
                    <div className="min-w-0">
                      <span className="font-bold text-xs text-white block truncate">{team.team_name}</span>
                      <span className="text-[10px] font-mono text-slate-500">{team.division}</span>
                    </div>
                  </div>
                  <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-cyan-500/10 text-cyan-400 border border-cyan-500/20">
                    {(team.playoff_prob * 100).toFixed(1)}% Playoff Prob
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* NFC Bubble */}
          <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 space-y-3">
            <div className="flex items-center justify-between border-b border-slate-800/80 pb-2">
              <span className="text-xs font-mono uppercase text-blue-400 font-bold flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-blue-500" />
                NFC Bubble Contenders
              </span>
              <span className="text-[10px] font-mono text-slate-500">Playoff Equity</span>
            </div>
            <div className="space-y-2">
              {dataset.nfc_bubble.map((team, idx) => (
                <div
                  key={team.team}
                  className="flex items-center justify-between p-2 rounded-lg bg-slate-950/40 hover:bg-slate-800/40 transition-colors"
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    <span className="text-xs font-mono font-bold text-slate-500 w-4">
                      #{idx + 8}
                    </span>
                    <TeamLogo team={team.team} size="sm" />
                    <div className="min-w-0">
                      <span className="font-bold text-xs text-white block truncate">{team.team_name}</span>
                      <span className="text-[10px] font-mono text-slate-500">{team.division}</span>
                    </div>
                  </div>
                  <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-cyan-500/10 text-cyan-400 border border-cyan-500/20">
                    {(team.playoff_prob * 100).toFixed(1)}% Playoff Prob
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Official NFL Tiebreaker Mechanics Reference */}
      <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 space-y-2.5">
        <div className="flex items-center gap-2 text-xs font-mono font-bold text-slate-300 uppercase tracking-wide">
          <HelpCircle className="w-4 h-4 text-emerald-400" />
          <span>Official Tiebreaker Engine Mechanics (nfl_tiebreakers.R)</span>
        </div>
        <p className="text-xs text-slate-400 leading-relaxed font-sans">
          {dataset.seeding_method}
        </p>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2 pt-1 text-[11px] font-mono">
          <div className="bg-slate-950 p-2 rounded-lg border border-slate-800/80">
            <span className="text-emerald-400 font-bold block">1. Head-to-Head</span>
            <span className="text-slate-500 text-[10px]">Direct game sweeps</span>
          </div>
          <div className="bg-slate-950 p-2 rounded-lg border border-slate-800/80">
            <span className="text-emerald-400 font-bold block">2. Division Record</span>
            <span className="text-slate-500 text-[10px]">Within division</span>
          </div>
          <div className="bg-slate-950 p-2 rounded-lg border border-slate-800/80">
            <span className="text-emerald-400 font-bold block">3. Common Games</span>
            <span className="text-slate-500 text-[10px]">Min 4 common opponents</span>
          </div>
          <div className="bg-slate-950 p-2 rounded-lg border border-slate-800/80">
            <span className="text-emerald-400 font-bold block">4. Conf Record</span>
            <span className="text-slate-500 text-[10px]">Intra-conference</span>
          </div>
          <div className="bg-slate-950 p-2 rounded-lg border border-slate-800/80">
            <span className="text-emerald-400 font-bold block">5. SOV</span>
            <span className="text-slate-500 text-[10px]">Strength of victory</span>
          </div>
          <div className="bg-slate-950 p-2 rounded-lg border border-slate-800/80">
            <span className="text-emerald-400 font-bold block">6. SOS</span>
            <span className="text-slate-500 text-[10px]">Strength of schedule</span>
          </div>
        </div>
      </div>
    </div>
  );
};
