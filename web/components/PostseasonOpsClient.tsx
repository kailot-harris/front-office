'use client';

import React, { useState, useMemo } from 'react';
import { PostseasonOpsData } from '@/lib/types';
import {
  Trophy,
  Flame,
  DollarSign,
  ShieldCheck,
  AlertTriangle,
  Activity,
  Award,
  TrendingUp,
  Download,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { exportToCsv } from '@/lib/exportToCsv';

interface PostseasonOpsClientProps {
  data: PostseasonOpsData;
}

export const PostseasonOpsClient: React.FC<PostseasonOpsClientProps> = ({ data }) => {
  const [activeTab, setActiveTab] = useState<'bracket' | 'bullpen' | 'market'>('bracket');
  const [bullpenLeague, setBullpenLeague] = useState<'All' | 'AL' | 'NL'>('All');

  const alSeeds = useMemo(
    () => data.bracket.filter((t) => t.league === 'AL').sort((a, b) => a.seed - b.seed),
    [data.bracket]
  );
  const nlSeeds = useMemo(
    () => data.bracket.filter((t) => t.league === 'NL').sort((a, b) => a.seed - b.seed),
    [data.bracket]
  );

  const filteredBullpen = useMemo(() => {
    return data.bullpen_status.filter((b) =>
      bullpenLeague === 'All' ? true : b.league === bullpenLeague
    );
  }, [data.bullpen_status, bullpenLeague]);

  const wsLeader = useMemo(() => {
    return [...data.bracket].sort((a, b) => b.pct_ws - a.pct_ws)[0];
  }, [data.bracket]);

  const bracketColumns = [
    { key: 'seed', label: 'Seed' },
    { key: 'team_name', label: 'Club' },
    { key: 'division', label: 'Division' },
    { key: 'elo_rating', label: 'Elo' },
    { key: 'pct_ds', label: 'Make DS %' },
    { key: 'pct_lcs', label: 'Make LCS %' },
    { key: 'pct_pennant', label: 'Pennant %' },
    { key: 'pct_ws', label: 'Win WS %' },
  ];

  const handleExportAlBracket = () => {
    exportToCsv(alSeeds as unknown as Record<string, unknown>[], bracketColumns, 'al-postseason-bracket');
  };

  const handleExportNlBracket = () => {
    exportToCsv(nlSeeds as unknown as Record<string, unknown>[], bracketColumns, 'nl-postseason-bracket');
  };

  const handleExportBullpen = () => {
    exportToCsv(
      filteredBullpen as unknown as Record<string, unknown>[],
      [
        { key: 'full_name', label: 'Club' },
        { key: 'division', label: 'Division' },
        { key: 'proj_wins', label: 'Proj Wins' },
        { key: 'active_relievers', label: 'High-Lev Arms' },
        { key: 'relievers_fatigued', label: 'Fatigued Relievers' },
        { key: 'b2b_relievers_count', label: 'Back-to-Back Arms' },
        { key: 'avg_bullpen_fatigue', label: 'Avg Fatigue Index' },
        { key: 'bullpen_vulnerability', label: 'Vulnerability Score' },
        { key: 'vulnerability_grade', label: 'Workload Status' },
      ],
      'bullpen-workload-fatigue'
    );
  };

  const handleExportValueBets = () => {
    exportToCsv(
      data.value_bets as unknown as Record<string, unknown>[],
      [
        { key: 'Matchup', label: 'Matchup' },
        { key: 'game_date', label: 'Date' },
        { key: 'Recommended_Bet', label: 'Recommended Bet' },
        { key: 'Book', label: 'Sportsbook' },
        { key: 'Line', label: 'Moneyline' },
        { key: 'Model_Win_Prob', label: 'Model Win %' },
        { key: 'EV_Percent', label: 'EV %' },
        { key: 'Bankroll_Rec', label: 'Kelly Bankroll %' },
      ],
      'market-edge-value-bets'
    );
  };

  return (
    <div className="space-y-6">
      {/* Top Sub-Navigation Tabs */}
      <div className="flex flex-wrap items-center gap-2 bg-surface-raised/90 border border-slate-800 rounded-xl p-2 shadow-lg">
        <button
          type="button"
          onClick={() => setActiveTab('bracket')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'bracket'
              ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Trophy className="w-4 h-4" />
          <span>12-Team Postseason Bracket</span>
          <span
            className={`text-xs font-mono px-2 py-0.5 rounded-full ${
              activeTab === 'bracket' ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
            }`}
          >
            10,000 Sims
          </span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('bullpen')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'bullpen'
              ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Flame className="w-4 h-4" />
          <span>Bullpen Workload & Fatigue</span>
          <span
            className={`text-xs font-mono px-2 py-0.5 rounded-full ${
              activeTab === 'bullpen' ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
            }`}
          >
            30 Bullpens
          </span>
        </button>

        <button
          type="button"
          onClick={() => setActiveTab('market')}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-bold transition-all ${
            activeTab === 'market'
              ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/30'
              : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <DollarSign className="w-4 h-4" />
          <span>Market Edge (+EV) & Kelly Risk</span>
          <span
            className={`text-xs font-mono px-2 py-0.5 rounded-full ${
              activeTab === 'market' ? 'bg-white/20 text-white' : 'bg-slate-800 text-slate-400'
            }`}
          >
            {data.risk_state.risk_status}
          </span>
        </button>
      </div>

      {/* TAB 1: 12-Team Postseason Bracket */}
      {activeTab === 'bracket' && (
        <div className="space-y-6">
          {/* Postseason Format Banner */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
              <TeamLogo team={wsLeader?.team} size="lg" />
              <div>
                <div className="text-xs text-slate-400 uppercase font-semibold">
                  Bracket Title Favorite
                </div>
                <div className="text-lg font-bold text-white">{wsLeader?.team_name}</div>
                <div className="text-xs text-amber-400 font-mono font-bold">
                  {wsLeader?.pct_ws.toFixed(1)}% World Series • {wsLeader?.pct_pennant.toFixed(1)}% Pennant
                </div>
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="text-xs text-slate-400 uppercase font-semibold">Wild Card Series</div>
              <div className="text-lg font-bold text-white mt-0.5">Best-of-3 (3-0 Home)</div>
              <div className="text-xs text-slate-400 mt-0.5">
                Seeds 1 & 2 earn DS Byes; #3 hosts #6, #4 hosts #5
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="text-xs text-slate-400 uppercase font-semibold">
                Division & League Series
              </div>
              <div className="text-lg font-bold text-white mt-0.5">DS (Bo5) • LCS (Bo7)</div>
              <div className="text-xs text-slate-400 mt-0.5">
                DS uses 2-2-1 home format; LCS & WS use 2-3-2 format
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="text-xs text-slate-400 uppercase font-semibold">
                Extra-Innings Rule
              </div>
              <div className="text-lg font-bold text-emerald-400 mt-0.5">Traditional Rules</div>
              <div className="text-xs text-slate-400 mt-0.5">
                No automatic ghost runner on 2nd in postseason play
              </div>
            </div>
          </div>

          {/* AL & NL Bracket Matchup Cards */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {[
              { title: 'American League (AL) Postseason Field', seeds: alSeeds, badge: 'AL' },
              { title: 'National League (NL) Postseason Field', seeds: nlSeeds, badge: 'NL' },
            ].map((lg) => (
              <div
                key={lg.badge}
                className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl"
              >
                <div className="p-4 bg-surface/80 border-b border-slate-800 flex items-center justify-between">
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <Award className="w-4 h-4 text-amber-400" />
                    <span>{lg.title}</span>
                  </h3>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono px-2 py-0.5 rounded bg-indigo-500/15 text-indigo-300 border border-indigo-500/30">
                      Seeds 1–6
                    </span>
                    <button
                      type="button"
                      onClick={lg.badge === 'AL' ? handleExportAlBracket : handleExportNlBracket}
                      title="Export CSV"
                      aria-label="Export table as CSV"
                      data-export-exclude
                      className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
                    >
                      <Download className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                <div className="overflow-x-auto">
                  <table className="w-full text-left border-collapse">
                    <thead>
                      <tr className="border-b border-slate-800 bg-surface/50 text-[10px] font-bold uppercase tracking-wider text-slate-400">
                        <th className="py-2.5 px-3">Seed</th>
                        <th className="py-2.5 px-3">Club</th>
                        <th className="py-2.5 px-2 text-right">Elo</th>
                        <th className="py-2.5 px-2 text-right">Make DS</th>
                        <th className="py-2.5 px-2 text-right">Make LCS</th>
                        <th className="py-2.5 px-2 text-right">Pennant</th>
                        <th className="py-2.5 px-3 text-right text-amber-400">Win WS</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-800/60 text-xs">
                      {lg.seeds.map((t) => (
                        <tr key={t.team_id} className="hover:bg-slate-800/40">
                          <td className="py-3 px-3 font-mono">
                            <span
                              className={`px-1.5 py-0.5 rounded font-bold ${
                                t.seed <= 2
                                  ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                  : 'bg-slate-800 text-slate-300'
                              }`}
                            >
                              #{t.seed} {t.seed <= 2 ? 'BYE' : 'WC'}
                            </span>
                          </td>
                          <td className="py-3 px-3">
                            <div className="flex items-center gap-2">
                              <TeamLogo team={t.team} size="sm" />
                              <div>
                                <div className="font-bold text-white">{t.team_name}</div>
                                <div className="text-[10px] text-slate-400 font-mono">
                                  {t.wins.toFixed(1)} Proj W • {t.division}
                                </div>
                              </div>
                            </div>
                          </td>
                          <td className="py-3 px-2 text-right font-mono text-slate-300">
                            {t.elo_rating.toFixed(0)}
                          </td>
                          <td className="py-3 px-2 text-right font-mono text-slate-200">
                            {t.pct_ds.toFixed(1)}%
                          </td>
                          <td className="py-3 px-2 text-right font-mono text-slate-200">
                            {t.pct_lcs.toFixed(1)}%
                          </td>
                          <td className="py-3 px-2 text-right font-mono font-semibold text-indigo-300">
                            {t.pct_pennant.toFixed(1)}%
                          </td>
                          <td className="py-3 px-3 text-right font-mono font-bold text-amber-400">
                            {t.pct_ws.toFixed(1)}%
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* TAB 2: Bullpen Workload & Fatigue Monitor */}
      {activeTab === 'bullpen' && (
        <div className="space-y-4">
          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Flame className="w-5 h-5 text-amber-400" />
                <span>30-Club Relief Pitcher Workload & Bullpen Vulnerability</span>
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                Tracks cumulative 3-day pitch counts, back-to-back appearances, and high-leverage reliever exhaustion penalties.
              </p>
            </div>

            <button
              type="button"
              onClick={handleExportBullpen}
              title="Export CSV"
              aria-label="Export table as CSV"
              data-export-exclude
              className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
            </button>
            <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800">
              {(['All', 'AL', 'NL'] as const).map((lg) => (
                <button
                  key={lg}
                  onClick={() => setBullpenLeague(lg)}
                  className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                    bullpenLeague === lg
                      ? 'bg-accent-600 text-white shadow-sm'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {lg === 'All' ? 'All 30 Bullpens' : `${lg} League`}
                </button>
              ))}
            </div>
          </div>

          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b border-slate-800 bg-surface/90 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                    <th className="py-3.5 px-4">Club</th>
                    <th className="py-3.5 px-3">Division</th>
                    <th className="py-3.5 px-3 text-right">High-Lev Arms</th>
                    <th className="py-3.5 px-3 text-right">Back-to-Back (B2B)</th>
                    <th className="py-3.5 px-3 text-right">Avg Fatigue Index</th>
                    <th className="py-3.5 px-3 text-right">Vulnerability Score</th>
                    <th className="py-3.5 px-4 text-right">Workload Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 text-sm">
                  {filteredBullpen.map((bp) => (
                    <tr key={bp.team} className="hover:bg-slate-800/40 transition-colors">
                      <td className="py-3 px-4">
                        <div className="flex items-center gap-2.5">
                          <TeamLogo team={bp.team} size="sm" />
                          <div>
                            <span className="font-bold text-white">{bp.full_name}</span>
                            <span className="text-[10px] font-mono text-slate-400 ml-1.5">
                              ({bp.proj_wins.toFixed(1)}W)
                            </span>
                          </div>
                        </div>
                      </td>
                      <td className="py-3 px-3 font-mono text-xs text-slate-400">
                        {bp.division}
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-slate-200">
                        {bp.active_relievers} Tracked ({bp.relievers_fatigued} Fatigued)
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-slate-200">
                        {bp.b2b_relievers_count} Arms
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-amber-300">
                        {bp.avg_bullpen_fatigue.toFixed(1)} / 100
                      </td>
                      <td className="py-3 px-3 text-right font-mono font-bold text-white">
                        {bp.bullpen_vulnerability.toFixed(1)}
                      </td>
                      <td className="py-3 px-4 text-right">
                        <span
                          className={`text-xs font-mono font-bold px-2.5 py-0.5 rounded-full border ${
                            bp.vulnerability_grade === 'High Vulnerability'
                              ? 'bg-rose-500/15 text-rose-300 border-rose-500/30'
                              : bp.vulnerability_grade === 'Elevated Workload'
                              ? 'bg-amber-500/15 text-amber-300 border-amber-500/30'
                              : 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
                          }`}
                        >
                          {bp.vulnerability_grade}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* TAB 3: Market Edge (+EV Bets) & Kelly Risk Monitor */}
      {activeTab === 'market' && (
        <div className="space-y-6">
          {/* Risk Management KPI Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Bankroll & Stop-Loss Status</span>
                <ShieldCheck className="w-4 h-4 text-emerald-400" />
              </div>
              <div className="text-2xl font-extrabold text-emerald-400 mt-1">
                {data.risk_state.risk_status}
              </div>
              <div className="text-xs text-slate-400 mt-1 font-mono">
                Bankroll: {data.risk_state.current_bankroll.toFixed(1)}u (Max DD{' '}
                {data.risk_state.max_dd_pct.toFixed(2)}%)
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Active Kelly Multiplier</span>
                <Activity className="w-4 h-4 text-indigo-400" />
              </div>
              <div className="text-2xl font-extrabold text-white mt-1 font-mono">
                {data.risk_state.active_kelly_multiplier.toFixed(3)}x Kelly
              </div>
              <div className="text-xs text-slate-400 mt-1">
                Tiers: 0.250 / 0.175 / 0.100 / 0.000 Halt
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Beat Closing Line (CLV)</span>
                <TrendingUp className="w-4 h-4 text-amber-400" />
              </div>
              <div className="text-2xl font-extrabold text-amber-400 mt-1 font-mono">
                {data.risk_state.beat_clv_rate_pct.toFixed(1)}%
              </div>
              <div className="text-xs text-slate-400 mt-1 font-mono">
                7d CLV: +{data.risk_state.rolling_7d_clv_pct.toFixed(2)}% ({data.risk_state.total_bets_audited}{' '}
                bets)
              </div>
            </div>

            <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4">
              <div className="flex items-center justify-between text-xs text-slate-400 uppercase font-semibold">
                <span>Current Drawdown</span>
                <AlertTriangle className="w-4 h-4 text-sky-400" />
              </div>
              <div className="text-2xl font-extrabold text-sky-400 mt-1 font-mono">
                -{data.risk_state.current_dd_pct.toFixed(2)}%
              </div>
              <div className="text-xs text-slate-400 mt-1 truncate">
                {data.risk_state.status_message}
              </div>
            </div>
          </div>

          {/* +EV Value Bets Table */}
          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
            <div className="p-4 bg-surface/80 border-b border-slate-800 flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-white">
                  Devigged Market Odds & +EV Kelly Value Recommendations
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Generated by mlb_market_odds_engine.R comparing 4-Factor Pitcher Elo probabilities against devigged sportsbook lines.
                </p>
              </div>
              <button
                type="button"
                onClick={handleExportValueBets}
                title="Export CSV"
                aria-label="Export table as CSV"
                data-export-exclude
                className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors flex-shrink-0"
              >
                <Download className="w-3.5 h-3.5" />
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b border-slate-800 bg-surface/90 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                    <th className="py-3.5 px-4">Matchup</th>
                    <th className="py-3.5 px-3">Recommended Bet</th>
                    <th className="py-3.5 px-3">Sportsbook</th>
                    <th className="py-3.5 px-3 text-right">Moneyline</th>
                    <th className="py-3.5 px-3 text-right">Model Win%</th>
                    <th className="py-3.5 px-3 text-right">Expected Value (+EV%)</th>
                    <th className="py-3.5 px-4 text-right">Fractional Kelly Stake</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 text-sm">
                  {data.value_bets.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="py-6 text-center text-slate-400 text-xs">
                        No active +EV value bets in current slate cache.
                      </td>
                    </tr>
                  ) : (
                    data.value_bets.map((bet, idx) => (
                      <tr key={idx} className="hover:bg-slate-800/40">
                        <td className="py-3.5 px-4">
                          <div className="font-bold text-white">{bet.Matchup}</div>
                          <div className="text-[11px] text-slate-400 font-mono">
                            Date: {bet.game_date} • Source: {bet.market_data_source}
                          </div>
                        </td>
                        <td className="py-3.5 px-3 font-mono font-bold text-emerald-400">
                          {bet.Recommended_Bet}
                        </td>
                        <td className="py-3.5 px-3 text-slate-300">{bet.Book}</td>
                        <td className="py-3.5 px-3 text-right font-mono text-white">
                          {bet.Line > 0 ? `+${bet.Line}` : bet.Line}
                        </td>
                        <td className="py-3.5 px-3 text-right font-mono text-indigo-300 font-semibold">
                          {(bet.Model_Win_Prob * 100).toFixed(1)}%
                        </td>
                        <td className="py-3.5 px-3 text-right font-mono font-bold text-emerald-400">
                          +{bet.EV_Percent.toFixed(1)}%
                        </td>
                        <td className="py-3.5 px-4 text-right font-mono">
                          <span className="px-2.5 py-1 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30 font-bold text-xs">
                            {bet.Bankroll_Rec.toFixed(2)}% Bankroll
                          </span>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
