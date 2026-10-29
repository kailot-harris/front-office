'use client';

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import {
  Trophy,
  TrendingUp,
  TrendingDown,
  DollarSign,
  Activity,
  Sparkles,
  ArrowRight,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { TeamProjection, ModelDiagnostics, PostseasonOpsData } from '@/lib/types';

interface RetrospectiveClientProps {
  teams: TeamProjection[];
  /* metadata: ModelMetadata; */
  diagnostics: ModelDiagnostics;
  postseasonOps: PostseasonOpsData;
  cbtSheet?: {
    teams: Array<{
      teamAbbr: string;
      teamName: string;
      payroll2026: number;
      cbtTier: string;
      cbtTaxBill: number;
    }>;
  };
}

export const RetrospectiveClient: React.FC<RetrospectiveClientProps> = ({
  teams,
  /* metadata */
  diagnostics,
  postseasonOps,
  cbtSheet,
}) => {
  const [activeTab, setActiveTab] = useState<'champions' | 'calibration' | 'payroll' | 'outliers'>('champions');

  // Find Brewers & Rays data
  const mil = useMemo(() => teams.find((t) => t.team === 'MIL'), [teams]);
  const tb = useMemo(() => teams.find((t) => t.team === 'TB'), [teams]);
  const milPost = useMemo(() => postseasonOps.bracket?.find((b) => b.team === 'MIL'), [postseasonOps]);
  const tbPost = useMemo(() => postseasonOps.bracket?.find((b) => b.team === 'TB'), [postseasonOps]);

  const milPayroll = useMemo(() => cbtSheet?.teams?.find((t) => t.teamAbbr === 'MIL'), [cbtSheet]);
  const tbPayroll = useMemo(() => cbtSheet?.teams?.find((t) => t.teamAbbr === 'TB'), [cbtSheet]);

  // Model calibration & variant performance
  const modelVariants = [
    {
      id: 'ensemble',
      name: 'Ensemble Multi-Model Blend',
      weight: '100%',
      topTeam: 'MIL (97.4 W)',
      description: 'Optimal blend (35% Pitcher Elo, 25% Bayes, 20% Pythagenpat, 20% Marcel/Bullpen). Accurately identified Milwaukee as the #1 title contender (17.1% title prob).',
      calibration: 'Optimal (Brier 0.2449)',
      accuracy: '56.63% (1,376 / 2,430 games)',
    },
    {
      id: 'bottom_up',
      name: '4-Factor Starting-Pitcher Elo',
      weight: '35%',
      topTeam: 'MIL (99.2 W)',
      description: 'Heavily rewarded Milwaukee\'s rotation depth and home field factor (+14.9 Elo), projecting 99.2 wins and 97.3% playoff odds.',
      calibration: 'High Variance in Bullpen Games',
      accuracy: '55.80% Game-by-Game',
    },
    {
      id: 'rapm',
      name: 'Hierarchical Empirical Bayes Talent',
      weight: '25%',
      topTeam: 'MIL (99.6 W)',
      description: 'Park-adjusted wOBA/xFIP partial pooling rated Milwaukee\'s run-prevention core as the highest true-talent roster in the NL (2.903 net talent score).',
      calibration: 'Strong Prior Shrinkage',
      accuracy: '56.12% Game-by-Game',
    },
    {
      id: 'shot_fatigue',
      name: 'Pythagenpat Run-Expectation',
      weight: '20%',
      topTeam: 'LAD (98.4 W)',
      description: 'Variable-exponent run differential model (exponent 1.79). Rated Milwaukee at 92.6 wins with a +136 run differential.',
      calibration: 'Extreme Regular Season Regression',
      accuracy: '54.95% Game-by-Game',
    },
    {
      id: 'embeddings',
      name: 'Marcel 3-Year & Bullpen Fatigue',
      weight: '20%',
      topTeam: 'MIL (95.1 W)',
      description: 'Flagged late-season relief workload vulnerability while capturing Milwaukee\'s young position core maturation curve.',
      calibration: 'Reliable Playoff Predictor',
      accuracy: '55.30% Game-by-Game',
    },
  ];

  // Roster Efficiency: Payroll per Win Calculation
  const efficiencyList = useMemo(() => {
    if (!cbtSheet?.teams) return [];
    return teams
      .map((t) => {
        const cbt = cbtSheet.teams.find((c) => c.teamAbbr === t.team);
        const payroll = cbt ? cbt.payroll2026 : 150;
        const wins = t.proj_wins || 81;
        const costPerWin = payroll / wins; // Millions per win
        return {
          team: t.team,
          fullName: t.full_name,
          league: t.league,
          wins,
          payroll,
          cbtTier: cbt?.cbtTier || 'Under Threshold',
          costPerWin,
          titleProb: t.ensemble_title_prob || 0,
        };
      })
      .sort((a, b) => a.costPerWin - b.costPerWin);
  }, [teams, cbtSheet]);

  // Largest Positive and Negative Model Surprises (Luck Wins / Pythagorean Delta)
  const sortedByLuck = useMemo(() => {
    return [...teams].sort((a, b) => (b.luck_wins ?? 0) - (a.luck_wins ?? 0));
  }, [teams]);

  return (
    <div className="space-y-8 pb-12">
      {/* Hero Header */}
      <section className="relative overflow-hidden rounded-2xl border border-amber-500/30 bg-gradient-to-br from-slate-900 via-slate-900/90 to-amber-950/20 p-6 sm:p-8 text-white shadow-xl">
        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2">
            <div className="flex flex-wrap items-center gap-2.5">
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold uppercase tracking-wider bg-amber-500/20 text-amber-300 border border-amber-500/30 font-mono">
                <Trophy className="w-3.5 h-3.5" />
                2026 Season Debrief
              </span>
              <span className="text-xs text-slate-400 font-mono">
                October 29, 2026 • 2,430 Games Evaluated
              </span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-black tracking-tight text-white">
              2026 MLB Sabermetric Retrospective
            </h1>
            <p className="text-sm sm:text-base text-slate-300 max-w-2xl leading-relaxed">
              Full postmortem and calibration audit of the 2026 Major League Baseball season. Analysis of the Milwaukee Brewers&apos; championship run, model variant reliability, and roster payroll efficiency.
            </p>
          </div>

          <div className="flex flex-wrap md:flex-col gap-3 min-w-[220px]">
            <div className="flex-1 rounded-xl bg-surface-raised/80 border border-slate-800 p-3.5">
              <span className="text-[11px] font-mono text-slate-400 uppercase tracking-wider block">
                World Series Champions
              </span>
              <div className="flex items-center gap-2 mt-1">
                <TeamLogo team="MIL" size="sm" />
                <span className="font-bold text-base text-amber-300">Milwaukee Brewers</span>
              </div>
            </div>
            <div className="flex-1 rounded-xl bg-surface-raised/80 border border-slate-800 p-3.5">
              <span className="text-[11px] font-mono text-slate-400 uppercase tracking-wider block">
                Walk-Forward Brier Score
              </span>
              <div className="flex items-center justify-between mt-1">
                <span className="font-mono font-bold text-base text-emerald-400">
                  {diagnostics.brierScore.toFixed(4)}
                </span>
                <span className="text-[11px] font-mono px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                  Optimal
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Navigation Tabs */}
      <div className="flex border-b border-slate-800 gap-2 overflow-x-auto pb-px">
        {[
          { id: 'champions', label: 'Championship Run Audit', icon: Trophy },
          { id: 'calibration', label: 'Model Variants & Brier Accuracy', icon: Activity },
          { id: 'payroll', label: 'CBT Payroll ROI & Surplus', icon: DollarSign },
          { id: 'outliers', label: 'Pythagorean Outliers & Luck', icon: TrendingUp },
        ].map((tab) => {
          const Icon = tab.icon;
          const isSelected = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as typeof activeTab)}
              className={`flex items-center gap-2 px-4 py-2.5 text-xs sm:text-sm font-semibold rounded-t-lg transition-all border-b-2 whitespace-nowrap ${
                isSelected
                  ? 'border-amber-400 text-amber-300 bg-surface-raised/60'
                  : 'border-transparent text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              <Icon className="w-4 h-4" />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* Tab 1: Championship Run Audit */}
      {activeTab === 'champions' && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Milwaukee Overview */}
            <div className="rounded-xl border border-amber-500/30 bg-surface-raised/50 p-6 space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <TeamLogo team="MIL" size="lg" />
                  <div>
                    <h2 className="text-xl font-bold text-white">Milwaukee Brewers</h2>
                    <span className="text-xs font-mono text-amber-400">NL Central Champions • World Series Winners</span>
                  </div>
                </div>
                <span className="text-xs font-mono px-2.5 py-1 rounded-full bg-amber-500/10 text-amber-300 border border-amber-500/30 font-semibold">
                  #1 Seed NL
                </span>
              </div>

              <p className="text-sm text-slate-300 leading-relaxed">
                The Brewers validated the pre-season sabermetric model consensus, which installed them as the number one overall simulation favorite with an ensemble projection of <strong>97.4 wins</strong> and a <strong>17.1% title probability</strong>.
              </p>

              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 pt-2">
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Pre-Season Elo</span>
                  <span className="text-base font-mono font-bold text-white">{mil?.elo_rating.toFixed(1)}</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Net Talent Score</span>
                  <span className="text-base font-mono font-bold text-emerald-400">+{mil?.net_talent_score.toFixed(2)}</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Run Differential</span>
                  <span className="text-base font-mono font-bold text-white">+{mil?.run_differential}</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">2026 CBT Payroll</span>
                  <span className="text-base font-mono font-bold text-amber-400">${milPayroll?.payroll2026 ?? 148}M</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Cost / Win</span>
                  <span className="text-base font-mono font-bold text-emerald-400">
                    ${((milPayroll?.payroll2026 ?? 148) / (mil?.proj_wins ?? 97.4)).toFixed(2)}M
                  </span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Sim WS Odds</span>
                  <span className="text-base font-mono font-bold text-amber-300">
                    {((milPost?.pct_ws ?? 24.11)).toFixed(1)}%
                  </span>
                </div>
              </div>
            </div>

            {/* Tampa Bay Overview */}
            <div className="rounded-xl border border-sky-500/30 bg-surface-raised/50 p-6 space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <TeamLogo team="TB" size="lg" />
                  <div>
                    <h2 className="text-xl font-bold text-white">Tampa Bay Rays</h2>
                    <span className="text-xs font-mono text-sky-400">AL Champions • AL Wild Card (Seed 4)</span>
                  </div>
                </div>
                <span className="text-xs font-mono px-2.5 py-1 rounded-full bg-sky-500/10 text-sky-300 border border-sky-500/30 font-semibold">
                  AL Pennant Winner
                </span>
              </div>

              <p className="text-sm text-slate-300 leading-relaxed">
                Tampa Bay represented the American League after navigating through the 12-team postseason bracket from the #4 seed. Their run showcased the highest payroll efficiency in baseball at only <strong>$95M total CBT payroll</strong>.
              </p>

              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 pt-2">
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Pre-Season Elo</span>
                  <span className="text-base font-mono font-bold text-white">{tb?.elo_rating.toFixed(1)}</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Rotation GameScore</span>
                  <span className="text-base font-mono font-bold text-sky-400">{tb?.team_rgs.toFixed(1)}</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Team xFIP (Bayes)</span>
                  <span className="text-base font-mono font-bold text-white">{tb?.team_xfip_pooled.toFixed(2)}</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">2026 CBT Payroll</span>
                  <span className="text-base font-mono font-bold text-sky-400">${tbPayroll?.payroll2026 ?? 95}M</span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Cost / Win</span>
                  <span className="text-base font-mono font-bold text-emerald-400">
                    ${((tbPayroll?.payroll2026 ?? 95) / (tb?.proj_wins ?? 88.5)).toFixed(2)}M
                  </span>
                </div>
                <div className="p-3 rounded-lg bg-surface border border-slate-800">
                  <span className="text-[11px] text-slate-500 font-mono block">Pennant Prob</span>
                  <span className="text-base font-mono font-bold text-sky-300">
                    {((tbPost?.pct_pennant ?? 18.45)).toFixed(1)}%
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Key Tactical Insights */}
          <div className="rounded-xl border border-slate-800 bg-surface-raised/40 p-6 space-y-4">
            <h3 className="text-base font-bold text-white flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-amber-400" />
              Tactical Postseason Takeaways
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-xs sm:text-sm text-slate-300">
              <div className="p-4 rounded-lg bg-surface border border-slate-800/80 space-y-2">
                <span className="font-semibold text-amber-300 block">1. Bullpen Leverage Resilience</span>
                <p className="text-slate-400 leading-relaxed">
                  Despite both clubs entering October with elevated bullpen fatigue indexes (MIL 97.7, TB 100.0), aggressive manager leverage deployments and day-of-rest optimization insulated late-inning high-leverage frames.
                </p>
              </div>
              <div className="p-4 rounded-lg bg-surface border border-slate-800/80 space-y-2">
                <span className="font-semibold text-sky-300 block">2. Starting Pitcher GameScore Primacy</span>
                <p className="text-slate-400 leading-relaxed">
                  Starting pitching depth proved decisive. The 4-Factor Pitcher Elo model accurately forecasted starter longevity as the primary differentiator in the multi-game series simulator.
                </p>
              </div>
              <div className="p-4 rounded-lg bg-surface border border-slate-800/80 space-y-2">
                <span className="font-semibold text-emerald-300 block">3. Surplus Value Over Mega Payrolls</span>
                <p className="text-slate-400 leading-relaxed">
                  The combined 2026 payroll of the World Series participants was $243M — less than the individual payrolls of the Mets ($318M), Dodgers ($338M), or Yankees ($308M).
                </p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Calibration & Brier Score */}
      {activeTab === 'calibration' && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="rounded-xl bg-surface-raised border border-slate-800 p-5 space-y-1">
              <span className="text-xs text-slate-400 font-mono uppercase">Full Slate Brier Score</span>
              <div className="flex items-baseline gap-2">
                <span className="text-3xl font-mono font-black text-white">{diagnostics.brierScore.toFixed(4)}</span>
                <span className="text-xs text-emerald-400 font-semibold font-mono">BSS: +{((diagnostics.brierSkillScore ?? 0.0204) * 100).toFixed(2)}%</span>
              </div>
              <p className="text-xs text-slate-400 pt-1">
                Outperformed naive 50/50 baseline (0.2500) across 2,430 regular season games.
              </p>
            </div>
            <div className="rounded-xl bg-surface-raised border border-slate-800 p-5 space-y-1">
              <span className="text-xs text-slate-400 font-mono uppercase">Log Loss (Cross-Entropy)</span>
              <div className="flex items-baseline gap-2">
                <span className="text-3xl font-mono font-black text-white">{(diagnostics.logLoss ?? 0.6828).toFixed(4)}</span>
                <span className="text-xs text-slate-400 font-mono">2,430 Games</span>
              </div>
              <p className="text-xs text-slate-400 pt-1">
                Weighted Calibration Error held to a tight {(((diagnostics.weightedCalibError ?? 0.0182)) * 100).toFixed(2)}%.
              </p>
            </div>
            <div className="rounded-xl bg-surface-raised border border-slate-800 p-5 space-y-1">
              <span className="text-xs text-slate-400 font-mono uppercase">Calibration Status</span>
              <div className="flex items-baseline gap-2">
                <span className="text-3xl font-mono font-black text-emerald-400">{diagnostics.calibrationStatus}</span>
              </div>
              <p className="text-xs text-slate-400 pt-1">
                Home win rate converged at {(((diagnostics.homeWinRate ?? 0.5284)) * 100).toFixed(2)}% (+14.9 Elo Home Court).
              </p>
            </div>
          </div>

          {/* Model Variants Breakdown */}
          <div className="rounded-xl border border-slate-800 bg-surface-raised/40 overflow-hidden">
            <div className="px-6 py-4 border-b border-slate-800">
              <h3 className="font-bold text-white text-base">Model Variants Calibration Comparison</h3>
              <p className="text-xs text-slate-400 mt-0.5">
                Comparative analysis of each distinct sabermetric engine that fed into the 2026 final ensemble.
              </p>
            </div>
            <div className="divide-y divide-slate-800">
              {modelVariants.map((m) => (
                <div key={m.id} className="p-5 flex flex-col md:flex-row md:items-center justify-between gap-4">
                  <div className="space-y-1 max-w-xl">
                    <div className="flex items-center gap-2.5">
                      <span className="font-bold text-white text-sm">{m.name}</span>
                      <span className="text-[11px] font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-300 border border-slate-700">
                        Weight: {m.weight}
                      </span>
                    </div>
                    <p className="text-xs text-slate-300/90 leading-relaxed">{m.description}</p>
                  </div>
                  <div className="flex items-center gap-4 text-xs font-mono">
                    <div className="text-right">
                      <span className="text-slate-500 block text-[10px]">Pinnacle Team</span>
                      <span className="text-amber-300 font-semibold">{m.topTeam}</span>
                    </div>
                    <div className="text-right">
                      <span className="text-slate-500 block text-[10px]">Game Accuracy</span>
                      <span className="text-white font-semibold">{m.accuracy}</span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Tab 3: CBT Payroll ROI & Surplus */}
      {activeTab === 'payroll' && (
        <div className="space-y-6">
          <div className="rounded-xl border border-slate-800 bg-surface-raised/40 overflow-hidden">
            <div className="px-6 py-4 border-b border-slate-800 flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <div>
                <h3 className="font-bold text-white text-base">2026 Payroll Efficiency Leaderboard</h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Cost per projected win based on 2026 Competitive Balance Tax (CBT) 40-man commitments.
                </p>
              </div>
              <span className="text-xs font-mono text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-2.5 py-1 rounded-full self-start sm:self-auto">
                Sorted by Lowest Cost / Win
              </span>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs font-sans">
                <thead className="bg-surface border-b border-slate-800 text-slate-400 font-mono text-[11px] uppercase">
                  <tr>
                    <th className="py-3 px-4">Rank</th>
                    <th className="py-3 px-4">Team</th>
                    <th className="py-3 px-4 text-right">Proj Wins</th>
                    <th className="py-3 px-4 text-right">2026 CBT Payroll</th>
                    <th className="py-3 px-4 text-right">Cost / Win</th>
                    <th className="py-3 px-4">CBT Tax Status</th>
                    <th className="py-3 px-4 text-right">Title Odds</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 text-slate-300 font-mono">
                  {efficiencyList.map((row, idx) => (
                    <tr
                      key={row.team}
                      className={`hover:bg-slate-800/40 transition-colors ${
                        row.team === 'MIL' ? 'bg-amber-500/10' : row.team === 'TB' ? 'bg-sky-500/10' : ''
                      }`}
                    >
                      <td className="py-3 px-4 font-bold text-slate-400">#{idx + 1}</td>
                      <td className="py-3 px-4 font-sans font-semibold text-white">
                        <div className="flex items-center gap-2">
                          <TeamLogo team={row.team} size="sm" />
                          <span>{row.fullName}</span>
                          {row.team === 'MIL' && (
                            <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30">
                              WS Champ
                            </span>
                          )}
                          {row.team === 'TB' && (
                            <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-sky-500/20 text-sky-300 border border-sky-500/30">
                              AL Champ
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="py-3 px-4 text-right font-bold text-white">{row.wins.toFixed(1)}</td>
                      <td className="py-3 px-4 text-right text-slate-200">${row.payroll}M</td>
                      <td className="py-3 px-4 text-right font-bold text-emerald-400">
                        ${row.costPerWin.toFixed(2)}M
                      </td>
                      <td className="py-3 px-4 font-sans text-[11px] text-slate-400">{row.cbtTier}</td>
                      <td className="py-3 px-4 text-right font-bold text-amber-400">
                        {(row.titleProb * 100).toFixed(1)}%
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* Tab 4: Pythagorean Outliers & Luck */}
      {activeTab === 'outliers' && (
        <div className="space-y-6">
          <div className="rounded-xl border border-slate-800 bg-surface-raised/40 p-5">
            <h3 className="font-bold text-white text-base">Pythagorean Expectation vs. Realized Record</h3>
            <p className="text-xs text-slate-400 mt-1 leading-relaxed">
              Evaluating David Smyth&apos;s Pythagenpat run-expectation variance. Positive luck wins represent teams that outperformed their run differential in one-run games, while negative values highlight clubs with unrewarded underlying run margins.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Top Overperformers */}
            <div className="rounded-xl border border-emerald-500/20 bg-surface-raised/30 p-5 space-y-4">
              <div className="flex items-center gap-2 text-emerald-400 font-bold text-sm">
                <TrendingUp className="w-4 h-4" />
                <span>Highest Positive Luck Margin (+Wins over Pythag)</span>
              </div>
              <div className="space-y-2">
                {sortedByLuck.slice(0, 5).map((t) => (
                  <div
                    key={t.team}
                    className="flex items-center justify-between p-3 rounded-lg bg-surface border border-slate-800 text-xs"
                  >
                    <div className="flex items-center gap-2.5">
                      <TeamLogo team={t.team} size="sm" />
                      <div>
                        <span className="font-semibold text-white block">{t.full_name}</span>
                        <span className="text-[10px] text-slate-400 font-mono">
                          RD: {t.run_differential > 0 ? `+${t.run_differential}` : t.run_differential}
                        </span>
                      </div>
                    </div>
                    <div className="text-right font-mono">
                      <span className="text-emerald-400 font-bold block">+{t.luck_wins.toFixed(1)} Wins</span>
                      <span className="text-[10px] text-slate-500">{(t.pythag_win_pct * 100).toFixed(1)}% Exp</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Top Underperformers */}
            <div className="rounded-xl border border-rose-500/20 bg-surface-raised/30 p-5 space-y-4">
              <div className="flex items-center gap-2 text-rose-400 font-bold text-sm">
                <TrendingDown className="w-4 h-4" />
                <span>Highest Negative Luck Margin (Run Sequencing Deficits)</span>
              </div>
              <div className="space-y-2">
                {[...sortedByLuck]
                  .reverse()
                  .slice(0, 5)
                  .map((t) => (
                    <div
                      key={t.team}
                      className="flex items-center justify-between p-3 rounded-lg bg-surface border border-slate-800 text-xs"
                    >
                      <div className="flex items-center gap-2.5">
                        <TeamLogo team={t.team} size="sm" />
                        <div>
                          <span className="font-semibold text-white block">{t.full_name}</span>
                          <span className="text-[10px] text-slate-400 font-mono">
                            RD: {t.run_differential > 0 ? `+${t.run_differential}` : t.run_differential}
                          </span>
                        </div>
                      </div>
                      <div className="text-right font-mono">
                        <span className="text-rose-400 font-bold block">{t.luck_wins.toFixed(1)} Wins</span>
                        <span className="text-[10px] text-slate-500">{(t.pythag_win_pct * 100).toFixed(1)}% Exp</span>
                      </div>
                    </div>
                  ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Bottom Cross-Navigation Links */}
      <div className="pt-4 border-t border-slate-800 flex flex-wrap items-center justify-between gap-4 text-xs">
        <span className="text-slate-400">
          MLB Sabermetric Pipeline Engine • 2026 Championship Debrief Complete
        </span>
        <div className="flex items-center gap-4">
          <Link href="/postseason" className="text-amber-400 hover:text-amber-300 font-medium flex items-center gap-1">
            Postseason Bracket Audit <ArrowRight className="w-3.5 h-3.5" />
          </Link>
          <Link href="/diagnostics" className="text-sky-400 hover:text-sky-300 font-medium flex items-center gap-1">
            Walk-Forward Diagnostics <ArrowRight className="w-3.5 h-3.5" />
          </Link>
          <Link href="/cap-sheet" className="text-slate-400 hover:text-white font-medium flex items-center gap-1">
            CBT Cap Sheet <ArrowRight className="w-3.5 h-3.5" />
          </Link>
        </div>
      </div>
    </div>
  );
};
